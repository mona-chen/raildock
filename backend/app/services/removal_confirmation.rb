# frozen_string_literal: true

# Signed proof that a user has seen the destructive part of a manifest apply.
#
# A manifest apply can only destroy services that are missing from the desired
# state. Computing that set is not enough on its own: a stale preview, a typo in
# a one-service manifest, or a library call that forgets to pass the flag must
# not be able to delete production data. Callers therefore have to echo back a
# token that is bound to the project, the exact manifest revision, and the exact
# list of services that will be destroyed.
class RemovalConfirmation
  EXPIRY = 30.minutes

  class InvalidConfirmation < StandardError; end

  class << self
    def issue(project:, digest:, removals:)
      verifier.generate(
        {
          "project_id" => project.id,
          "digest" => digest,
          "removals" => normalize(removals)
        },
        expires_in: EXPIRY
      )
    end

    # Returns the removals the token authorises, or raises InvalidConfirmation.
    def verify!(token:, project:, digest:, removals:)
      raise InvalidConfirmation, "Removal confirmation is required" if token.blank?

      payload = verifier.verify(token)
      unless payload.is_a?(Hash) && payload["project_id"] == project.id
        raise InvalidConfirmation, "Removal confirmation does not belong to this project"
      end
      unless ActiveSupport::SecurityUtils.secure_compare(payload["digest"].to_s, digest.to_s)
        raise InvalidConfirmation, "The manifest changed after removal confirmation — review the diff again"
      end
      unless payload["removals"] == normalize(removals)
        raise InvalidConfirmation, "The list of services to destroy changed — review the diff again"
      end

      payload["removals"]
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidConfirmation, "Removal confirmation is invalid or expired — review the diff again"
    end

    # Stable fingerprint of the manifest revision the user reviewed.
    def digest_for(content)
      Digest::SHA256.hexdigest(content.to_s)
    end

    def verifier
      ActiveSupport::MessageVerifier.new(
        Rails.application.secret_key_base,
        digest: "SHA256",
        serializer: JSON,
        url_safe: true
      )
    end

    private
      def normalize(removals)
        Array(removals).map(&:to_s).sort
      end
  end
end

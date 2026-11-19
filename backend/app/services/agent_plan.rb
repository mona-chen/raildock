# frozen_string_literal: true

# A reviewed manifest change.
#
# The plan is a signed, self-contained token: it carries the exact content that
# was diffed, the base revision it was diffed against, the removals it would
# perform, and the token that issued it. Nothing is persisted, so a plan cannot
# outlive the state it was reviewed against — applying it after the stored
# manifest moved raises Drifted instead of applying a stale diff.
class AgentPlan
  EXPIRY = 15.minutes

  class Invalid < StandardError; end
  class Drifted < Invalid; end
  class Expired < Invalid; end

  attr_reader :project, :content, :format, :changes, :removals, :warnings,
              :severity, :token, :digest, :base_digest, :expires_at, :jti

  class << self
    def build(project:, content:, format: nil, actor: nil)
      content = content.to_s
      format = format.presence || project.manifest_format.presence || "raildock.toml"

      desired = parse!(content, format)
      validate!(desired, content)

      reconciler = ManifestReconciler.new(project, desired)
      changes = reconciler.diff

      new(
        project: project,
        content: content,
        format: format,
        desired: desired,
        changes: changes,
        removals: reconciler.removal_plan,
        actor: actor
      )
    end

    def decode!(token)
      raise Invalid, "A plan is required" if token.blank?

      payload = verifier.verify(token)
      raise Invalid, "Plan payload is invalid" unless payload.is_a?(Hash)

      payload.with_indifferent_access
    rescue ActiveSupport::MessageVerifier::InvalidSignature => error
      raise Expired, "Plan expired — create a new one" if error.message.to_s.include?("expired")

      raise Invalid, "Plan is invalid or expired — create a new one"
    rescue ArgumentError
      raise Invalid, "Plan is invalid or expired — create a new one"
    end

    def verify!(payload:, project:, actor: nil)
      unless payload[:project_id].to_i == project.id
        raise Invalid, "This plan belongs to another project"
      end

      if payload[:api_token_id].present? && actor && payload[:api_token_id].to_i != actor.id
        raise Invalid, "This plan was created by a different token"
      end

      if payload[:base_digest].to_s != RemovalConfirmation.digest_for(project.manifest_content.to_s)
        raise Drifted, "The project manifest changed after this plan was created — create a new plan"
      end

      payload
    end

    def verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.secret_key_base,
        digest: "SHA256",
        serializer: JSON,
        url_safe: true
      )
    end

    private

    def parse!(content, format)
      ManifestParser.parse(content, filename: format)
    rescue ManifestParser::ParseError => error
      raise Invalid, "Parse error: #{error.message}"
    end

    def validate!(desired, content)
      schema_content = desired.repaired_content || content
      parsed = begin
        JSON.parse(schema_content)
      rescue JSON::ParserError
        TomlRB.parse(schema_content)
      end

      validation = ManifestSchema.validate(parsed)
      raise Invalid, "Validation failed: #{validation.errors.join('; ')}" unless validation.success?

      parsed
    rescue TomlRB::ParseError => error
      raise Invalid, "Parse error: #{error.message}"
    end
  end

  def initialize(project:, content:, format:, desired:, changes:, removals:, actor:)
    @project = project
    @content = content
    @format = format
    @changes = changes
    @removals = removals
    @warnings = desired.warnings
    @severity = ChangeClassifier.aggregate(changes)
    @digest = RemovalConfirmation.digest_for(content)
    @base_digest = RemovalConfirmation.digest_for(project.manifest_content.to_s)
    @expires_at = EXPIRY.from_now
    @jti = SecureRandom.uuid
    @token = self.class.verifier.generate(payload(actor), expires_in: EXPIRY)
  end

  def removal_names
    removals.map { |removal| removal[:service_name].to_s }.sort
  end

  def removal_token
    return if removals.empty?

    RemovalConfirmation.issue(project: project, digest: digest, removals: removal_names)
  end

  def as_json
    {
      id: token,
      project_id: project.id.to_s,
      format: format,
      digest: digest,
      base_digest: base_digest,
      expires_at: expires_at.iso8601,
      changes: changes.map(&:to_h),
      total_changes: changes.length,
      severity: severity,
      by_severity: ChangeClassifier.group_by_severity(changes).transform_values(&:count),
      warnings: warnings,
      removals: removals,
      requires_removal_confirmation: removals.any?,
      removal_token: removal_token
    }
  end

  private

  def payload(actor)
    {
      "project_id" => project.id,
      "content" => content,
      "format" => format,
      "digest" => digest,
      "base_digest" => base_digest,
      "removals" => removal_names,
      "api_token_id" => actor&.id,
      "jti" => jti
    }
  end
end

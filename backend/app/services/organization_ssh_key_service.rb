require "tmpdir"
require "fileutils"
require "shellwords"
require "base64"
require "openssl"

class OrganizationSshKeyService
  KEY_TYPE = "ed25519".freeze

  class << self
    def generate(organization)
      existing = OrganizationSshKey.find_by(organization: organization)
      return existing if existing.present?

      key_data = generate_key_pair(organization.slug)
      OrganizationSshKey.create!(
        organization: organization,
        private_key: key_data[:private_key],
        public_key: key_data[:public_key],
        fingerprint: key_data[:fingerprint]
      )
    end

    def ensure_key!(organization)
      find_or_generate(organization)
    end

    private

    def find_or_generate(organization)
      OrganizationSshKey.find_by(organization: organization) || generate(organization)
    end

    def generate_key_pair(comment)
      dir = Dir.mktmpdir("raildock_org_ssh")
      key_path = File.join(dir, "org_key")

      begin
        cmd = "ssh-keygen -t #{KEY_TYPE} -f #{Shellwords.escape(key_path)} -N '' -C #{Shellwords.escape(comment)}"
        output, status = Open3.capture2e(cmd)

        unless status.success?
          Rails.logger.error "Organization SSH key generation failed: #{output}"
          raise "Failed to generate organization SSH key: #{output}"
        end

        private_key = File.read(key_path)
        public_key = File.read("#{key_path}.pub")
        fingerprint = extract_fingerprint(public_key)

        {
          private_key: private_key,
          public_key: public_key,
          fingerprint: fingerprint
        }
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    def extract_fingerprint(public_key)
      Tempfile.create([ "pubkey", ".pub" ]) do |f|
        f.write(public_key)
        f.flush
        output, status = Open3.capture2("ssh-keygen -lf #{f.path}")
        if status.success?
          output.split[1]
        else
          parts = public_key.split
          "SHA256:" + Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(Base64.strict_decode64(parts[1])))
        end
      end
    end
  end
end

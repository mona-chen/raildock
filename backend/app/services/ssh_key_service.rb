require 'tmpdir'
require 'fileutils'
require 'shellwords'

class SshKeyService
  KEY_TYPE = 'ed25519'.freeze
  KEY_BITS = 256

  class << self
    def generate(name: nil)
      dir = Dir.mktmpdir('raildock_ssh')
      key_path = File.join(dir, 'deploy_key')
      comment = name ? "raildock-deploy-#{name}" : "raildock-deploy"

      begin
        # Generate ED25519 key pair
        cmd = "ssh-keygen -t #{KEY_TYPE} -f #{Shellwords.escape(key_path)} -N '' -C #{Shellwords.escape(comment)}"
        output, status = Open3.capture2e(cmd)

        unless status.success?
          Rails.logger.error "SSH key generation failed: #{output}"
          raise "Failed to generate SSH key: #{output}"
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

    private

    def extract_fingerprint(public_key)
      # ssh-keygen -lf can extract fingerprint from public key
      Tempfile.create(['pubkey', '.pub']) do |f|
        f.write(public_key)
        f.flush
        output, status = Open3.capture2("ssh-keygen -lf #{f.path}")
        if status.success?
          # Output format: 256 SHA256:xxxxxx comment (ED25519)
          output.split[1]
        else
          # Fallback: SHA256 of the key body
          parts = public_key.split
          Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(Base64.strict_decode64(parts[1])))
        end
      end
    end
  end
end

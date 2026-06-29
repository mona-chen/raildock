require "net/ssh"
require "tempfile"

class SshKeyValidator
  def self.validate(key)
    new(key).validate
  end

  def initialize(key)
    @key = key.to_s
  end

  def validate
    return { valid: false, error: "SSH key is blank" } if @key.blank?

    Tempfile.create([ "ssh_key", "" ]) do |file|
      file.write(@key)
      file.flush

      begin
        Net::SSH::KeyFactory.load_private_key(file.path, nil, false)
        { valid: true }
      rescue Net::SSH::Exception => e
        { valid: false, error: "Invalid SSH key format: #{e.message}" }
      rescue OpenSSL::PKey::PKeyError => e
        { valid: false, error: "Invalid SSH key format: #{e.message}" }
      rescue => e
        { valid: false, error: "Could not parse SSH key: #{e.message}" }
      end
    end
  end
end

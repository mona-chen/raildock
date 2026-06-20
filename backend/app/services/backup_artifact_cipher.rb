class BackupArtifactCipher
  MAGIC = "RAILDOCK-BACKUP-V1\0".b.freeze
  IV_BYTES = 12
  TAG_BYTES = 16

  def encrypt(source_path, destination_path, key_hex)
    cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    cipher.key = key(key_hex)
    iv = cipher.random_iv

    File.open(destination_path, "wb", 0o600) do |output|
      output.write(MAGIC)
      output.write(iv)
      File.open(source_path, "rb") do |input|
        while (chunk = input.read(1.megabyte))
          output.write(cipher.update(chunk))
        end
      end
      output.write(cipher.final)
      output.write(cipher.auth_tag(TAG_BYTES))
    end
  end

  def decrypt(source_path, destination_path, key_hex)
    File.open(source_path, "rb") do |input|
      raise "Unsupported or corrupt RailDock backup" unless input.read(MAGIC.bytesize) == MAGIC

      iv = input.read(IV_BYTES)
      payload_bytes = input.size - MAGIC.bytesize - IV_BYTES - TAG_BYTES
      raise "Encrypted backup is truncated" if iv&.bytesize != IV_BYTES || payload_bytes.negative?

      input.seek(-TAG_BYTES, IO::SEEK_END)
      tag = input.read(TAG_BYTES)
      input.seek(MAGIC.bytesize + IV_BYTES, IO::SEEK_SET)

      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key(key_hex)
      cipher.iv = iv
      cipher.auth_tag = tag

      File.open(destination_path, "wb", 0o600) do |output|
        remaining = payload_bytes
        while remaining.positive?
          chunk = input.read([ remaining, 1.megabyte ].min)
          output.write(cipher.update(chunk))
          remaining -= chunk.bytesize
        end
        output.write(cipher.final)
      end
    end
  rescue OpenSSL::Cipher::CipherError
    File.delete(destination_path) if File.exist?(destination_path)
    raise "Encrypted backup authentication failed"
  end

  private
    def key(value)
      decoded = [ value.to_s ].pack("H*")
      raise "Backup encryption key must be 256 bits" unless decoded.bytesize == 32

      decoded
    end
end

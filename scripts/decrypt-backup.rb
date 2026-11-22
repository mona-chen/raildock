#!/usr/bin/env ruby
# frozen_string_literal: true

# Decrypts a RailDock backup artifact downloaded from an S3-compatible
# destination, using that destination's recovery key. Needs only Ruby and its
# bundled OpenSSL — no RailDock install, database or gems.
#
#   RAILDOCK_RECOVERY_KEY=<64 hex chars> ruby scripts/decrypt-backup.rb artifact.backup artifact.out
#
# Without RAILDOCK_RECOVERY_KEY the key is read from the terminal without echo,
# so it does not end up in shell history.
#
# Format (BackupArtifactCipher, "RAILDOCK-BACKUP-V1"): one AES-256-GCM stream
#
#   "RAILDOCK-BACKUP-V1\0" (19 bytes) | IV (12 bytes) | ciphertext | auth tag (16 bytes)
#
# No associated data. The tag covers the whole file, so the output is written to
# a temporary file and only renamed into place once the tag verifies: a wrong
# key or a corrupted download never leaves a plausible-looking partial file.
require "openssl"

module RaildockBackupDecryptor
  MAGIC = "RAILDOCK-BACKUP-V1\0".b.freeze
  IV_BYTES = 12
  TAG_BYTES = 16
  CHUNK_BYTES = 1024 * 1024

  class Error < StandardError; end

  module_function

  def decrypt_file(source_path, destination_path, key_hex)
    key = [ key_hex.to_s.strip ].pack("H*")
    raise Error, "recovery key must be 64 hexadecimal characters" unless key_hex.to_s.strip.match?(/\A\h{64}\z/)

    partial = "#{destination_path}.partial"
    File.open(source_path, "rb") do |input|
      raise Error, "not a RailDock backup artifact (missing RAILDOCK-BACKUP-V1 header)" unless input.read(MAGIC.bytesize) == MAGIC

      iv = input.read(IV_BYTES)
      payload_bytes = input.size - MAGIC.bytesize - IV_BYTES - TAG_BYTES
      raise Error, "artifact is truncated" if iv.nil? || iv.bytesize != IV_BYTES || payload_bytes.negative?

      input.seek(-TAG_BYTES, IO::SEEK_END)
      tag = input.read(TAG_BYTES)
      input.seek(MAGIC.bytesize + IV_BYTES, IO::SEEK_SET)

      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key
      cipher.iv = iv
      cipher.auth_tag = tag
      cipher.auth_data = ""

      File.open(partial, "wb", 0o600) do |output|
        remaining = payload_bytes
        while remaining.positive?
          chunk = input.read([ remaining, CHUNK_BYTES ].min)
          raise Error, "artifact is truncated" if chunk.nil?

          output.write(cipher.update(chunk))
          remaining -= chunk.bytesize
        end
        output.write(cipher.final)
      end
    end
    File.rename(partial, destination_path)
    destination_path
  rescue OpenSSL::Cipher::CipherError
    raise Error, "authentication failed: wrong recovery key, or the artifact is corrupt or incomplete"
  ensure
    File.delete(partial) if partial && File.exist?(partial)
  end

  def read_key
    return ENV["RAILDOCK_RECOVERY_KEY"] if ENV["RAILDOCK_RECOVERY_KEY"].to_s.strip != ""

    require "io/console"
    $stderr.print "Recovery key: "
    key = $stdin.noecho(&:gets).to_s
    $stderr.puts
    key
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 2 || %w[-h --help].include?(ARGV.first)
    warn "usage: RAILDOCK_RECOVERY_KEY=<hex> ruby #{File.basename(__FILE__)} ENCRYPTED_ARTIFACT OUTPUT_FILE"
    exit 64
  end

  source, destination = ARGV
  if File.exist?(destination)
    warn "#{destination} already exists; refusing to overwrite it"
    exit 1
  end

  begin
    RaildockBackupDecryptor.decrypt_file(source, destination, RaildockBackupDecryptor.read_key)
    warn "Decrypted #{source} -> #{destination}"
  rescue RaildockBackupDecryptor::Error, SystemCallError => error
    warn "decrypt-backup: #{error.message}"
    exit 1
  end
end

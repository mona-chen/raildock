require "rails_helper"

RSpec.describe BackupArtifactCipher do
  it "round trips binary artifacts with authenticated encryption" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source")
      encrypted = File.join(dir, "encrypted")
      restored = File.join(dir, "restored")
      File.binwrite(source, SecureRandom.random_bytes(2.megabytes))

      described_class.new.encrypt(source, encrypted, "ab" * 32)
      described_class.new.decrypt(encrypted, restored, "ab" * 32)

      expect(File.binread(restored)).to eq(File.binread(source))
      expect(File.binread(encrypted)).not_to include(File.binread(source, 32))
    end
  end

  it "rejects tampered ciphertext" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source")
      encrypted = File.join(dir, "encrypted")
      restored = File.join(dir, "restored")
      File.binwrite(source, "critical backup")
      described_class.new.encrypt(source, encrypted, "cd" * 32)
      bytes = File.binread(encrypted)
      bytes.setbyte(described_class::MAGIC.bytesize + described_class::IV_BYTES + 1, bytes.getbyte(described_class::MAGIC.bytesize + described_class::IV_BYTES + 1) ^ 0xff)
      File.binwrite(encrypted, bytes)

      expect { described_class.new.decrypt(encrypted, restored, "cd" * 32) }.to raise_error("Encrypted backup authentication failed")
      expect(File).not_to exist(restored)
    end
  end
end

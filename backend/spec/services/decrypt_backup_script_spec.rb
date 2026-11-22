require "rails_helper"

# scripts/decrypt-backup.rb is the documented offline path for decrypting an
# artifact with only the recovery key. It must keep reading what
# BackupArtifactCipher writes.
RSpec.describe "scripts/decrypt-backup.rb" do
  script = [
    Rails.root.join("..", "scripts", "decrypt-backup.rb"),
    Rails.root.join("scripts", "decrypt-backup.rb")
  ].find(&:exist?)

  before do
    skip "repository scripts/ directory is not available in this container" unless script
    load script.to_s
  end

  let(:key) { SecureRandom.hex(32) }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def encrypt(plaintext)
    source = File.join(@dir, "plain")
    File.binwrite(source, plaintext)
    encrypted = File.join(@dir, "artifact.backup")
    BackupArtifactCipher.new.encrypt(source, encrypted, key)
    encrypted
  end

  it "round-trips an artifact larger than one chunk" do
    plaintext = Random.bytes((2.5 * 1024 * 1024).to_i)
    output = File.join(@dir, "restored")

    RaildockBackupDecryptor.decrypt_file(encrypt(plaintext), output, key)

    expect(File.binread(output)).to eq(plaintext)
  end

  it "refuses the wrong key without leaving output behind" do
    output = File.join(@dir, "restored")

    expect {
      RaildockBackupDecryptor.decrypt_file(encrypt("pg_dump"), output, SecureRandom.hex(32))
    }.to raise_error(RaildockBackupDecryptor::Error, /authentication failed/)
    expect(Dir.children(@dir)).not_to include("restored", "restored.partial")
  end

  it "rejects a file that is not a RailDock artifact" do
    source = File.join(@dir, "plain.sql")
    File.binwrite(source, "SELECT 1;")

    expect {
      RaildockBackupDecryptor.decrypt_file(source, File.join(@dir, "out"), key)
    }.to raise_error(RaildockBackupDecryptor::Error, /not a RailDock backup/)
  end
end

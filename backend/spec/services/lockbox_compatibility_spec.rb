require "rails_helper"

# Lockbox 2.3.0 fixes insecure hybrid cryptography (GHSA-586r-mm5q-xhg2).
# RailDock never uses hybrid mode: Server, OrganizationSshKey and DokkuEngine
# build a plain AES-256-GCM box, so existing rows must stay readable after the
# upgrade. Public synthetic key and ciphertext; never installation credentials.
# The fixture below decrypts under both 2.2.0 and 2.3.0 with this key.
RSpec.describe "Lockbox encrypted data compatibility" do
  it "decrypts AES-GCM ciphertext written before the 2.3.0 upgrade" do
    box = Lockbox.new(key: [ "11" * 32 ].pack("H*"), encode: true)
    ciphertext = "4xKFw+tAJCxjCFukmYWlp7H8ZPNw0EZ0KpQV9TWMA5KlmSO9oGGErpJLGQdPFkWBneLHyKN489zBF8Ji"
    expect(box.decrypt(ciphertext)).to eq("compatibility-probe-not-a-secret")
    expect(box.decrypt(box.encrypt("new-value"))).to eq("new-value")
  end
end

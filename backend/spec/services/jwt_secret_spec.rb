require "rails_helper"

RSpec.describe JwtSecret do
  describe ".value" do
    it "prefers an explicit JWT_SECRET_KEY" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("JWT_SECRET_KEY").and_return("explicit-secret")

      expect(described_class.value).to eq("explicit-secret")
    end

    # docker-compose passes `JWT_SECRET_KEY:` with no value in development, so
    # the variable exists but is empty. Treating that as a real key made login
    # raise `JWT::DecodeError: HMAC key cannot be empty` while every other
    # decode path fell back to secret_key_base.
    it "treats a blank JWT_SECRET_KEY as absent" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("JWT_SECRET_KEY").and_return("")

      expect(described_class.value).to be_present
    end

    it "signs and verifies with the same key when the variable is blank" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("JWT_SECRET_KEY").and_return("")

      token = JWT.encode({ user_id: 1 }, described_class.value)
      expect(JWT.decode(token, described_class.value, true, { algorithm: "HS256" }).first["user_id"]).to eq(1)
    end
  end
end

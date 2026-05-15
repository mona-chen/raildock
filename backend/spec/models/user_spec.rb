require 'rails_helper'

RSpec.describe User, type: :model do
  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:email) }

    context "email format" do
      it "is valid with a proper email address" do
        user = build(:user, email: "user@example.com")
        expect(user).to be_valid
      end

      it "is invalid without a proper email address" do
        user = build(:user, email: "not-an-email")
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include("is invalid")
      end

      it "is invalid with an empty email" do
        user = build(:user, email: "")
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include("can't be blank")
      end
    end

    context "password" do
      it "is invalid without a password" do
        user = build(:user, password: nil, password_confirmation: nil)
        expect(user).not_to be_valid
      end

      it "is invalid when password and confirmation do not match" do
        user = build(:user, password: "secret123", password_confirmation: "different")
        expect(user).not_to be_valid
      end
    end
  end

  describe "secure password" do
    it "has a password_digest after creation" do
      user = create(:user, password: "securepass123", password_confirmation: "securepass123")
      expect(user.password_digest).to be_present
      expect(user.authenticate("securepass123")).to eq(user)
      expect(user.authenticate("wrongpass")).to be_falsey
    end
  end

  describe "#generate_jwt" do
    let(:user) { create(:user) }

    it "returns a JWT token" do
      token = user.generate_jwt
      expect(token).to be_a(String)
      expect(token.split(".").length).to eq(3)
    end

    it "encodes the user_id in the token" do
      token = user.generate_jwt
      decoded = JWT.decode(token, user.jwt_secret_key, true, algorithm: "HS256")
      expect(decoded.first["user_id"]).to eq(user.id)
    end

    it "sets an expiration 30 days from now" do
      token = user.generate_jwt
      decoded = JWT.decode(token, user.jwt_secret_key, true, algorithm: "HS256")
      expect(decoded.first["exp"]).to be_within(5).of(30.days.from_now.to_i)
    end
  end
end

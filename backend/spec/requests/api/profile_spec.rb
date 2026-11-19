require "rails_helper"

RSpec.describe "Api::ProfileController", type: :request do
  let(:user) { create(:user, password: "password123", password_confirmation: "password123") }

  describe "PATCH /api/profile" do
    it "requires authentication" do
      patch "/api/profile", params: { user: { name: "New Name" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "updates the display name without a password" do
      patch "/api/profile",
        params: { user: { name: "Ada Lovelace" } },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("Ada Lovelace")
      expect(response.parsed_body["organizations"]).to be_an(Array)
      expect(user.reload.name).to eq("Ada Lovelace")
    end

    it "requires the current password to change the email" do
      patch "/api/profile",
        params: { user: { email: "ada@example.com" } },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("current_password_invalid")
      expect(user.reload.email).not_to eq("ada@example.com")
    end

    it "changes the email with the current password" do
      patch "/api/profile",
        params: {
          user: { email: "ada@example.com" },
          current_password: "password123"
        },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.email).to eq("ada@example.com")
    end

    it "rejects a wrong current password" do
      patch "/api/profile",
        params: {
          user: { email: "ada@example.com" },
          current_password: "not-the-password"
        },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("current_password_invalid")
    end

    it "changes the password with a matching confirmation" do
      patch "/api/profile",
        params: {
          user: { password: "new-password-456" },
          password_confirmation: "new-password-456",
          current_password: "password123"
        },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("new-password-456")).to be_truthy
      expect(user.authenticate("password123")).to be(false)
    end

    it "rejects a password confirmation mismatch" do
      patch "/api/profile",
        params: {
          user: { password: "new-password-456" },
          password_confirmation: "different",
          current_password: "password123"
        },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("password_confirmation_mismatch")
    end

    it "reports model validation errors without changing anything" do
      patch "/api/profile",
        params: { user: { email: "not-an-email" }, current_password: "password123" },
        headers: auth_headers(user),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("validation_failed")
      expect(user.reload.email).not_to eq("not-an-email")
    end

    it "refuses to let an API token change the account profile" do
      organization = create(:organization, owner: user)
      create(:organization_membership, user: user, organization: organization, role: :owner)
      token = ApiToken.issue!(organization: organization, user: user, name: "agent", scopes: [ "read" ])

      patch "/api/profile",
        params: { user: { name: "Token Changed" } },
        headers: {
          "Authorization" => "Bearer #{token.plaintext}",
          "X-Organization-ID" => organization.id.to_s
        },
        as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("token_not_allowed")
      expect(user.reload.name).not_to eq("Token Changed")
    end
  end
end

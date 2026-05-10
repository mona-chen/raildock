require "rails_helper"

RSpec.describe "Api::UsersController", type: :request do
  describe "GET /api/setup" do
    context "when no users exist" do
      it "returns required: true" do
        get "/api/setup"

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["required"]).to be true
      end
    end

    context "when users exist" do
      before { create(:user) }

      it "returns required: false" do
        get "/api/setup"

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["required"]).to be false
      end
    end
  end

  describe "POST /api/users" do
    context "when no users exist (first user creation)" do
      let(:valid_params) do
        {
          user: {
            name: "Admin User",
            email: "admin@example.com",
            password: "securepassword"
          }
        }
      end

      it "creates the first user and returns a token" do
        post "/api/users", params: valid_params

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["token"]).to be_present
        expect(json["user"]["email"]).to eq("admin@example.com")
        expect(User.count).to eq(1)
      end

      it "returns 422 with invalid data" do
        post "/api/users", params: { user: { name: "", email: "bad", password: "short" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to be_present
      end
    end

    context "when a user already exists" do
      before { create(:user) }

      it "returns 422" do
        post "/api/users", params: {
          user: { name: "Another", email: "another@example.com", password: "password123" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to eq("First user already created")
      end
    end
  end
end

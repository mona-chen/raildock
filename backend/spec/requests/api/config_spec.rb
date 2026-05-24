require "rails_helper"

RSpec.describe "Api::ConfigController", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/config" do
    it "returns github_app config when authenticated" do
      get "/api/config", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key("github_app")
      expect(json["github_app"]).to have_key("enabled")
      expect(json["github_app"]).to have_key("app_slug")
    end

    it "returns 401 when unauthenticated" do
      get "/api/config"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

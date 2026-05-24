require "rails_helper"

RSpec.describe "Api::Admin::SettingsController", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:user) { create(:user, admin: false) }

  describe "GET /api/admin/settings" do
    it "returns settings for admin" do
      SystemSetting.create!(key: "github_app_slug", value: "my-app")
      get "/api/admin/settings", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.first["key"]).to eq("github_app_slug")
    end

    it "returns 403 for non-admin" do
      get "/api/admin/settings", headers: auth_headers(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/admin/settings" do
    it "updates settings for admin" do
      patch "/api/admin/settings",
            params: { github_app_slug: "new-app", github_app_id: "123" },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(SystemSetting.github_app_slug).to eq("new-app")
      expect(SystemSetting.github_app_id).to eq("123")
    end

    it "returns 403 for non-admin" do
      patch "/api/admin/settings",
            params: { github_app_slug: "new-app" },
            headers: auth_headers(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/admin/settings/test-github-app" do
    context "when slug is configured" do
      before do
        SystemSetting.create!(key: "github_app_slug", value: "raildock")
      end

      it "returns validation result" do
        post "/api/admin/settings/test-github-app", headers: auth_headers(admin)
        expect(response).to have_http_status(:unprocessable_entity) # raildock app doesn't exist
        json = JSON.parse(response.body)
        expect(json).to have_key("valid")
      end
    end

    it "returns 400 when slug is missing" do
      post "/api/admin/settings/test-github-app", headers: auth_headers(admin)
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 403 for non-admin" do
      post "/api/admin/settings/test-github-app", headers: auth_headers(user)
      expect(response).to have_http_status(:forbidden)
    end
  end
end

require "rails_helper"

RSpec.describe "Api::Admin::GithubAppManifestsController", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:user) { create(:user, admin: false) }

  describe "GET /api/admin/github-app-manifest" do
    it "returns manifest for admin" do
      get "/api/admin/github-app-manifest", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key("manifest")
      expect(json).to have_key("form_url")
      expect(json["manifest"]["name"]).to eq("RailDock")
      expect(json["manifest"]["default_permissions"]).to be_a(Hash)
    end

    it "returns 403 for non-admin" do
      get "/api/admin/github-app-manifest", headers: auth_headers(user)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 for unauthenticated" do
      get "/api/admin/github-app-manifest"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/admin/github-app-manifest/callback" do
    context "without code" do
      it "redirects with error" do
        get "/api/admin/github-app-manifest/callback"
        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(%r{github_app_manifest=error})
      end
    end

    context "with invalid state" do
      it "redirects with error" do
        get "/api/admin/github-app-manifest/callback", params: { code: "abc", state: "invalid" }
        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(%r{github_app_manifest=error})
      end
    end
  end

  describe "GET /api/admin/github-app-manifest/setup" do
    it "redirects to frontend" do
      get "/api/admin/github-app-manifest/setup"
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(%r{tab=git-sources})
    end
  end
end

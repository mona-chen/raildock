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

    it "uses the configured public URL for GitHub callbacks" do
      with_env(RAILDOCK_PUBLIC_URL: "http://152.53.163.11:8888", FRONTEND_URL: "http://localhost:8888") do
        get "/api/admin/github-app-manifest", headers: auth_headers(admin)
      end

      expect(response).to have_http_status(:ok)
      manifest = JSON.parse(response.body).fetch("manifest")
      expect(manifest["url"]).to eq("http://152.53.163.11:8888")
      expect(manifest["redirect_url"]).to eq("http://152.53.163.11:8888/api/admin/github-app-manifest/callback")
      expect(manifest["setup_url"]).to eq("http://152.53.163.11:8888/api/admin/github-app-manifest/setup")
      expect(manifest.dig("hook_attributes", "url")).to eq("http://152.53.163.11:8888/api/github-apps/webhook")
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
        with_env(RAILDOCK_PUBLIC_URL: "http://152.53.163.11:8888", FRONTEND_URL: "http://localhost:8888") do
          get "/api/admin/github-app-manifest/callback"
        end

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(%r{\Ahttp://152\.53\.163\.11:8888/#/dashboard/settings\?tab=git-sources&github_app_manifest=error})
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

  describe "DELETE /api/admin/github-app" do
    it "clears RailDock credentials without claiming to delete the GitHub registration" do
      SystemSetting.set!("github_app_id", "123")
      SystemSetting.set!("github_app_slug", "raildock-test")
      create(:git_source, provider: "github", user: admin, installation_id: "456")

      delete "/api/admin/github-app", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to include("disconnected from RailDock")
      expect(SystemSetting.github_app_id).to be_nil
      expect(SystemSetting.github_app_slug).to be_nil
      expect(GitSource.where(provider: "github").pluck(:connected)).to contain_exactly(false)
    end
  end

  def with_env(values)
    previous = {}
    values.each_key { |key| previous[key] = ENV[key.to_s] }
    values.each { |key, value| ENV[key.to_s] = value }

    yield
  ensure
    previous&.each do |key, value|
      value.nil? ? ENV.delete(key.to_s) : ENV[key.to_s] = value
    end
  end
end

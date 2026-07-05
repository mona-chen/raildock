require 'rails_helper'

RSpec.describe "Plugins API", type: :request do
  let(:user) { create(:user, admin: false) }
  let(:admin_user) { create(:user, admin: true) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_user.generate_jwt}" } }

  before { PluginRegistry.seed! }

  describe "GET /api/modules" do
    it "returns built-in plugins with subtypes" do
      get "/api/modules", headers: auth_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)

      database_plugin = json.find { |p| p["slug"] == "core-databases" }
      expect(database_plugin).to be_present
      expect(database_plugin["service_subtypes"]).to be_an(Array)

      postgres = database_plugin["service_subtypes"].find { |s| s["subtype"] == "postgres" }
      expect(postgres).to be_present
      expect(postgres["capabilities"]).to include("create", "backup")
    end

    it "requires authentication" do
      get "/api/modules"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/modules/:slug/enable" do
    let!(:plugin) { create(:plugin, slug: "ext", status: "disabled") }

    it "allows admins to enable a plugin" do
      post "/api/modules/ext/enable", headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(plugin.reload.status).to eq("enabled")
    end

    it "rejects non-admins" do
      post "/api/modules/ext/enable", headers: auth_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects enabling built-in plugins" do
      post "/api/modules/core-databases/enable", headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/modules/:slug/disable" do
    let!(:plugin) { create(:plugin, slug: "ext", status: "enabled") }

    it "allows admins to disable a plugin" do
      post "/api/modules/ext/disable", headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(plugin.reload.status).to eq("disabled")
    end

    it "rejects non-admins" do
      post "/api/modules/ext/disable", headers: auth_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects disabling built-in plugins" do
      post "/api/modules/core-databases/disable", headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/modules/install" do
    let(:manifest_url) { "https://example.com/plugin.yml" }

    it "queues an install job for admins" do
      expect {
        post "/api/modules/install", params: { source_url: manifest_url }, headers: admin_headers
      }.to have_enqueued_job(InstallPluginJob)

      expect(response).to have_http_status(:accepted)
    end

    it "rejects install without source_url" do
      post "/api/modules/install", headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects non-admins" do
      post "/api/modules/install", params: { source_url: manifest_url }, headers: auth_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/modules/:slug" do
    let!(:plugin) { create(:plugin, slug: "ext") }

    it "queues an uninstall job for admins" do
      expect {
        delete "/api/modules/ext/uninstall", headers: admin_headers
      }.to have_enqueued_job(UninstallPluginJob)

      expect(response).to have_http_status(:accepted)
    end

    it "rejects uninstalling built-in plugins" do
      delete "/api/modules/core-databases/uninstall", headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects non-admins" do
      delete "/api/modules/ext/uninstall", headers: auth_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/modules/:slug/settings" do
    let!(:plugin) do
      create(:plugin, slug: "ext", config_schema: {
        "endpoint" => { type: "string", required: true, label: "Endpoint" }
      })
    end
    let!(:setting) { PluginSetting.create!(plugin: plugin, key: "endpoint", value: "https://a.com") }

    it "returns plugin settings for admins" do
      get "/api/modules/ext/settings", headers: admin_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["settings"]["endpoint"]).to eq("https://a.com")
    end

    it "rejects non-admins" do
      get "/api/modules/ext/settings", headers: auth_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/modules/:slug/settings" do
    let!(:plugin) do
      create(:plugin, slug: "ext", config_schema: {
        "endpoint" => { type: "string", required: true, label: "Endpoint" },
        "count" => { type: "integer", required: false, label: "Count" }
      })
    end

    it "persists valid settings for admins" do
      patch "/api/modules/ext/settings", params: { settings: { endpoint: "https://b.com", count: 5 } }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(plugin.plugin_settings.find_by(key: "endpoint").value).to eq("https://b.com")
      expect(plugin.plugin_settings.find_by(key: "count").value).to eq("5")
    end

    it "rejects invalid settings" do
      patch "/api/modules/ext/settings", params: { settings: { endpoint: "" } }, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects non-admins" do
      patch "/api/modules/ext/settings", params: { settings: { endpoint: "x" } }, headers: auth_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end

require 'rails_helper'

RSpec.describe "Plugins API", type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }

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
end

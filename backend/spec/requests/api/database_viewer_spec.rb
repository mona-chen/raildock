require "rails_helper"

RSpec.describe "Api::DatabaseViewerController", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let!(:service) { create(:service, :database, project: project, subtype: "postgres", dokku_app_name: "proj-pg") }

  before do
    allow_any_instance_of(DokkuEngine).to receive(:datastore_query) do |_engine, _service, sql|
      if sql.include?("information_schema.tables")
        { success: true, output: %([{"name":"users","schema":"public"}]) }
      elsif sql.include?("information_schema.columns")
        { success: true, output: %([{"name":"id","type":"integer"}]) }
      else
        { success: true, output: %([{"id":1}]) }
      end
    end
  end

  describe "GET /api/services/:id/data" do
    it "returns 401 when unauthenticated" do
      get "/api/services/#{service.id}/data"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the table list" do
      get "/api/services/#{service.id}/data", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["type"]).to eq("postgres")
      expect(json["tables"]).to eq([ { "name" => "users", "schema" => "public" } ])
    end

    it "returns 422 for unsupported datastores" do
      redis = create(:service, project: project, service_type: :cache, subtype: "redis")
      get "/api/services/#{redis.id}/data", headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["success"]).to be false
    end
  end

  describe "GET /api/services/:id/data/:table" do
    it "returns rows for a table" do
      get "/api/services/#{service.id}/data/users", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["table"]).to eq("users")
      expect(json["columns"]).to eq([ { "name" => "id", "type" => "integer" } ])
      expect(json["rows"]).to eq([ { "id" => 1 } ])
    end

    it "passes limit and offset" do
      get "/api/services/#{service.id}/data/users?limit=25&offset=50", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["limit"]).to eq(25)
      expect(json["offset"]).to eq(50)
    end
  end
end

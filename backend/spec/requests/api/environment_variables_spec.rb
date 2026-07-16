require 'rails_helper'

RSpec.describe "Environment Variables API", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }

  before do
    allow_any_instance_of(DokkuEngine).to receive(:config_replace_all)
      .and_return({ success: true, output: "" })
    allow_any_instance_of(DokkuEngine).to receive(:config_export_json)
      .and_return({ success: true, output: "{}" })
    allow(RestartJob).to receive(:perform_later)
  end

  describe "POST /api/services/:service_id/env-vars" do
    it "creates an environment variable" do
      post "/api/services/#{service.id}/env-vars",
        params: { key: "API_KEY", value: "secret123" },
        headers: auth_headers
      expect(response).to have_http_status(:created)
      expect(service.environment_variables.count).to eq(1)
    end

    it "returns 422 with invalid data" do
      post "/api/services/#{service.id}/env-vars",
        params: { key: "" },
        headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/services/:service_id/env-vars/:key" do
    let!(:env_var) { create(:environment_variable, service: service, key: "OLD_KEY") }

    it "destroys the environment variable" do
      delete "/api/services/#{service.id}/env-vars/OLD_KEY", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(service.environment_variables.count).to eq(0)
    end
  end

  describe "PUT /api/services/:service_id/env-vars" do
    let!(:existing) { create(:environment_variable, service: service, key: "EXISTING", value: "old") }

    it "upserts all vars in one request" do
      put "/api/services/#{service.id}/env-vars",
        params: { vars: [
          { key: "EXISTING", value: "new" },
          { key: "ADDED", value: "v2" }
        ] },
        headers: auth_headers,
        as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["updated"]).to eq(2)
      expect(existing.reload.value).to eq("new")
      expect(service.environment_variables.find_by(key: "ADDED").value).to eq("v2")
    end

    it "syncs to Dokku once and schedules a single restart" do
      expect_any_instance_of(DokkuEngine).to receive(:config_replace_all).once
        .and_return({ success: true, output: "" })
      expect(RestartJob).to receive(:perform_later).once

      put "/api/services/#{service.id}/env-vars",
        params: { vars: [
          { key: "A", value: "1" },
          { key: "B", value: "2" },
          { key: "C", value: "3" }
        ] },
        headers: auth_headers,
        as: :json

      expect(response).to have_http_status(:ok)
    end

    it "returns 422 when vars is empty" do
      put "/api/services/#{service.id}/env-vars",
        params: { vars: [] },
        headers: auth_headers,
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "skips entries without a key" do
      put "/api/services/#{service.id}/env-vars",
        params: { vars: [ { key: "", value: "x" }, { key: "GOOD", value: "y" } ] },
        headers: auth_headers,
        as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["updated"]).to eq(1)
      expect(service.environment_variables.pluck(:key)).to include("GOOD")
    end
  end
end

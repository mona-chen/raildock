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
end

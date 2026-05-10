require 'rails_helper'

RSpec.describe "Deployments API", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }

  before do
    create_list(:deployment, 3, service: service)
  end

  describe "GET /api/services/:service_id/deployments" do
    it "returns deployments for the service" do
      get "/api/services/#{service.id}/deployments", headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(3)
    end

    it "returns 401 without auth" do
      get "/api/services/#{service.id}/deployments"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

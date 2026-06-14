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

  describe "POST /api/deployments/:id/cancel" do
    it "cancels an active deployment" do
      deployment = create(:deployment, service: service, status: :pending)

      post "/api/deployments/#{deployment.id}/cancel", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(deployment.reload).to be_cancelled
    end
  end

  describe "POST /api/projects/:id/cancel_deployments" do
    it "cancels every active deployment in the project only" do
      pending = create(:deployment, service: service, status: :pending)
      building = create(:deployment, service: service, status: :building)
      completed = create(:deployment, service: service, status: :succeeded)
      other = create(:deployment, status: :pending)

      post "/api/projects/#{project.id}/cancel_deployments", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["cancelled"]).to eq(2)
      expect([ pending.reload.status, building.reload.status ]).to all(eq("cancelled"))
      expect(completed.reload).to be_succeeded
      expect(other.reload).to be_pending
    end
  end
end

require 'rails_helper'

RSpec.describe "Activity Events API", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }

  before do
    create_list(:activity_event, 5, project: project, service_name: service.name)
  end

  describe "GET /api/projects/:project_id/activity-events" do
    it "returns activity events for the project" do
      get "/api/projects/#{project.id}/activity-events", headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(5)
      expect(json.first).to include("action", "message", "service_name")
    end

    it "returns 401 without auth" do
      get "/api/projects/#{project.id}/activity-events"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns empty array for non-existent project" do
      get "/api/projects/99999/activity-events", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end
end

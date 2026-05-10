require 'rails_helper'

RSpec.describe "Storage Mounts API", type: :request do
  let(:user) { create(:user) }
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}" } }

  describe "POST /api/services/:service_id/storage" do
    it "creates a storage mount" do
      post "/api/services/#{service.id}/storage",
        params: { host_path: "/var/data", container_path: "/app/data" },
        headers: auth_headers
      expect(response).to have_http_status(:created)
      expect(service.storage_mounts.count).to eq(1)
    end

    it "returns 422 with invalid data" do
      post "/api/services/#{service.id}/storage",
        params: { host_path: "" },
        headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/services/:service_id/storage/*host_path" do
    let!(:mount) { create(:storage_mount, service: service, host_path: "/var/data") }

    it "destroys the storage mount" do
      delete "/api/services/#{service.id}/storage/%2Fvar%2Fdata", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(service.storage_mounts.count).to eq(0)
    end
  end
end

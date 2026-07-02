require 'rails_helper'

RSpec.describe "Storage Mounts API", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, server: server, organization: organization) }
  let(:service) { create(:service, project: project) }
  let(:auth_headers) { { "Authorization" => "Bearer #{user.generate_jwt}", "X-Organization-ID" => organization.id.to_s } }

  before do
    allow_any_instance_of(DokkuEngine).to receive(:storage_mount).and_return({ success: true, output: "" })
    allow_any_instance_of(DokkuEngine).to receive(:storage_unmount).and_return({ success: true, output: "" })
    allow_any_instance_of(DokkuEngine).to receive(:config_set).and_return({ success: true, output: "" })
    allow_any_instance_of(DokkuEngine).to receive(:config_unset).and_return({ success: true, output: "" })
  end

  describe "POST /api/services/:service_id/storage" do
    it "creates a storage mount" do
      post "/api/services/#{service.id}/storage",
        params: { host_path: "/var/data", container_path: "/app/data" },
        headers: auth_headers
      expect(response).to have_http_status(:created)
      expect(service.storage_mounts.count).to eq(1)
      mount = service.storage_mounts.first
      expect(mount.kind).to eq("bind")
    end

    it "auto-generates a volume name when kind is volume and host_path is omitted" do
      post "/api/services/#{service.id}/storage",
        params: { container_path: "/app/data", kind: "volume" },
        headers: auth_headers
      expect(response).to have_http_status(:created)
      mount = service.storage_mounts.first
      expect(mount.kind).to eq("volume")
      expect(mount.host_path).to eq("#{service.dokku_app_name}-app-data")
    end

    it "syncs RAILDOCK_STORAGE_* env vars after creating a mount" do
      expect_any_instance_of(StorageMountEnvSync).to receive(:sync!).once
      post "/api/services/#{service.id}/storage",
        params: { container_path: "/app/data", kind: "volume" },
        headers: auth_headers
      expect(response).to have_http_status(:created)
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

  describe "GET /api/services/:service_id/storage/:id/browse" do
    let!(:mount) { create(:storage_mount, :volume, service: service, host_path: "uploads-data", container_path: "/app/uploads") }

    it "returns directory entries" do
      expect_any_instance_of(HostEngine).to receive(:volume_list_directory)
        .with("uploads-data", "/")
        .and_return({ success: true, entries: [ { type: "file", name: "hello.txt", size: 12 } ] })

      get "/api/services/#{service.id}/storage/#{mount.id}/browse", headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["entries"]).to eq([ { "type" => "file", "name" => "hello.txt", "size" => 12 } ])
      expect(json["path"]).to eq("/")
    end
  end
end

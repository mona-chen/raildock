require "rails_helper"

RSpec.describe StorageMountEnvSync, type: :service do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server) }
  let(:service) { create(:service, project: project) }
  let(:engine) { instance_double(DokkuEngine, config_set: { success: true }, config_unset: { success: true }) }

  before do
    allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
  end

  describe "#sync!" do
    it "sets RAILDOCK_STORAGE_* env vars for a single mount" do
      service.storage_mounts.create!(host_path: "uploads-data", container_path: "/app/uploads", kind: "volume")

      expect(engine).to receive(:config_set).with(service.dokku_app_name, "RAILDOCK_STORAGE_HOST", "uploads-data")
      expect(engine).to receive(:config_set).with(service.dokku_app_name, "RAILDOCK_STORAGE_CONTAINER_PATH", "/app/uploads")
      expect(engine).to receive(:config_set).with(service.dokku_app_name, "RAILDOCK_STORAGE_COUNT", "1")

      described_class.new(service, engine).sync!

      expect(service.environment_variables.pluck(:key)).to include(
        "RAILDOCK_STORAGE_HOST",
        "RAILDOCK_STORAGE_CONTAINER_PATH",
        "RAILDOCK_STORAGE_COUNT"
      )
    end

    it "sets indexed env vars for multiple mounts" do
      service.storage_mounts.create!(host_path: "data-a", container_path: "/app/a", kind: "volume")
      service.storage_mounts.create!(host_path: "data-b", container_path: "/app/b", kind: "volume")

      expect(engine).to receive(:config_set).with(service.dokku_app_name, "RAILDOCK_STORAGE_0_HOST", "data-a")
      expect(engine).to receive(:config_set).with(service.dokku_app_name, "RAILDOCK_STORAGE_1_HOST", "data-b")
      expect(engine).to receive(:config_set).with(service.dokku_app_name, "RAILDOCK_STORAGE_COUNT", "2")

      described_class.new(service, engine).sync!
    end

    it "removes stale env vars when mounts are deleted" do
      mount = service.storage_mounts.create!(host_path: "old-data", container_path: "/app/old", kind: "volume")
      described_class.new(service, engine).sync!
      expect(service.environment_variables.count).to eq(5) # 2 indexed + 2 single-mount aliases + count

      mount.destroy!
      %w[
        RAILDOCK_STORAGE_HOST
        RAILDOCK_STORAGE_CONTAINER_PATH
        RAILDOCK_STORAGE_COUNT
        RAILDOCK_STORAGE_0_HOST
        RAILDOCK_STORAGE_0_CONTAINER_PATH
      ].each do |key|
        expect(engine).to receive(:config_unset).with(service.dokku_app_name, key)
      end

      described_class.new(service, engine).sync!
      expect(service.environment_variables.count).to eq(0)
    end
  end
end

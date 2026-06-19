require "rails_helper"

RSpec.describe RestartJob do
  let(:project) { create(:project) }
  let(:service) { create(:service, project: project, subtype: "web") }
  let(:server) { project.server }
  let(:engine) { instance_double(DokkuEngine) }
  let(:host_engine) { instance_double(HostEngine) }
  let(:network_manager) { instance_double(ProjectNetworkManager) }

  before do
    allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
    allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
    allow(ProjectNetworkManager).to receive(:new).with(project, engine).and_return(network_manager)
    allow(engine).to receive(:with_session).and_yield
    allow(host_engine).to receive(:with_session).and_yield
    allow(DeploymentsChannel).to receive(:broadcast_to)
    allow(network_manager).to receive(:connect_service)
    allow(network_manager).to receive(:ensure_linked_aliases)
    allow(network_manager).to receive(:inject_internal_hostnames)
  end

  describe "#perform" do
    it "creates a Deployment record of kind 'restart'" do
      allow(engine).to receive(:ps_restart).and_return({ success: true, output: "ok" })
      allow(host_engine).to receive(:wait_for_container).and_return(nil)

      expect {
        described_class.perform_now(service.id)
      }.to change { service.deployments.where(kind: "restart").count }.by(1)

      deployment = service.deployments.where(kind: "restart").last
      expect(deployment.status).to eq("succeeded")
      expect(deployment.completed_at).to be_present
      expect(deployment.deploy_log).to include("ps:restart")
    end

    it "marks the deployment failed when the container never starts" do
      allow(engine).to receive(:ps_restart).and_return({ success: false, output: "boom" })
      allow(host_engine).to receive(:wait_for_container).and_return(nil)

      described_class.perform_now(service.id)

      deployment = service.deployments.where(kind: "restart").last
      expect(deployment.status).to eq("failed")
      expect(service.reload.status).to eq("error")
    end

    it "broadcasts status transitions via DeploymentsChannel" do
      allow(engine).to receive(:ps_restart).and_return({ success: true, output: "ok" })
      allow(host_engine).to receive(:wait_for_container).and_return(nil)

      expect(DeploymentsChannel).to receive(:broadcast_to).with(
        service,
        hash_including(kind: "restart", status: "building", message: "Restart started")
      ).ordered
      expect(DeploymentsChannel).to receive(:broadcast_to).with(
        service,
        hash_including(kind: "restart", status: "succeeded", message: "Restart completed")
      ).ordered

      described_class.perform_now(service.id)
    end

    it "records log lines on the deployment as the restart progresses" do
      allow(engine).to receive(:ps_restart).and_return({ success: true, output: "ok" })
      allow(host_engine).to receive(:wait_for_container).and_return(nil)

      described_class.perform_now(service.id)

      deployment = service.deployments.where(kind: "restart").last
      expect(deployment.deploy_log).to include("Restarting #{service.dokku_app_name}")
      expect(deployment.deploy_log).to include("ps:restart")
      expect(deployment.deploy_log).to include("Restoring network aliases")
    end

    it "is idempotent — a duplicate idempotency key reuses the same record" do
      allow(engine).to receive(:ps_restart).and_return({ success: true, output: "ok" })
      allow(host_engine).to receive(:wait_for_container).and_return(nil)

      key = "restart:test"
      expect {
        described_class.perform_now(service.id, idempotency_key: key)
        described_class.perform_now(service.id, idempotency_key: key)
      }.to change { service.deployments.where(kind: "restart", idempotency_key: key).count }.by(1)
    end

    it "treats a 'reports failure but container running' as success and notes it" do
      allow(engine).to receive(:ps_restart).and_return({ success: false, output: "permission denied" })
      allow(host_engine).to receive(:wait_for_container).and_return("container-id-123")
      allow(host_engine).to receive(:container_running?).with("container-id-123").and_return(true)

      described_class.perform_now(service.id)

      deployment = service.deployments.where(kind: "restart").last
      expect(deployment.status).to eq("succeeded")
      expect(deployment.deploy_log).to include("container-id-123")
      expect(service.reload.status).to eq("running")
    end

    it "uses the database-specific restart path for database services" do
      db_service = create(:service, :database, project: project)
      allow(engine).to receive(:run).with("postgres:restart #{db_service.dokku_app_name}").and_return({ success: true, output: "ok" })
      allow(host_engine).to receive(:wait_for_container).and_return(nil)

      described_class.perform_now(db_service.id)

      deployment = db_service.deployments.where(kind: "restart").last
      expect(deployment.status).to eq("succeeded")
      expect(deployment.deploy_log).to include("postgres:restart")
    end

    # Belt-and-suspenders: the database-path uses `engine.run` which is what
    # triggered the previous "unexpected message" failures. Allow anything
    # so this test stays focused on the postgres branch.
  end
end

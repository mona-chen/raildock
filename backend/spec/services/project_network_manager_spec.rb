require "rails_helper"

RSpec.describe ProjectNetworkManager do
  let(:server) { create(:server) }
  let(:project) { create(:project, server: server, network_name: "rd-test-1") }
  let(:service) { create(:service, project: project, name: "web", service_type: "app") }
  let(:engine) { instance_double(DokkuEngine) }
  let(:host_engine) { instance_double(HostEngine) }
  let(:manager) { described_class.new(project, engine) }

  before do
    allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
    allow(host_engine).to receive(:docker_network_create).and_return({ success: true, output: "" })
    allow(host_engine).to receive(:docker_network_connect).and_return({ success: true, output: "" })
    allow(host_engine).to receive(:docker_network_disconnect).and_return({ success: true, output: "" })
    allow(host_engine).to receive(:container_running?).and_return(true)
    allow(host_engine).to receive(:dokku_container_name).and_return("app-container")
    allow(engine).to receive(:network_list).and_return({ success: true, output: "rd-test-1\nbridge\nhost\nnone" })
    allow(engine).to receive(:network_create).and_return({ success: true, output: "" })
    allow(engine).to receive(:run).and_return({ success: true, output: "" })
  end

  describe "#configure_attach_networks" do
    context "managed proxy mode (external_proxy? is false)" do
      before do
        allow(server).to receive(:external_proxy?).and_return(false)
        allow(server).to receive(:external_proxy_network).and_return(nil)
      end

      it "returns { success: true }" do
        result = manager.configure_attach_networks(service)
        expect(result).to eq({ success: true })
      end

      it "sets attach-post-create to the project network" do
        manager.configure_attach_networks(service)
        expect(engine).to have_received(:run)
          .with("network:set #{service.dokku_app_name} attach-post-create rd-test-1")
      end

      it "does not set attach-post-deploy" do
        manager.configure_attach_networks(service)
        expect(engine).not_to have_received(:run)
          .with(/attach-post-deploy/)
      end

      it "returns failure when network:set attach-post-create fails" do
        allow(engine).to receive(:run).and_return({ success: true, output: "" })
        allow(engine).to receive(:run)
          .with("network:set #{service.dokku_app_name} attach-post-create rd-test-1")
          .and_return({ success: false, output: "error" })

        result = manager.configure_attach_networks(service)
        expect(result[:success]).to be(false)
      end
    end

    context "external proxy mode" do
      before do
        allow(server).to receive(:external_proxy?).and_return(true)
        allow(server).to receive(:external_proxy_network).and_return("traefik-net")
        allow(engine).to receive(:run).and_return({ success: true, output: "" })
      end

      it "sets both attach-post-create and attach-post-deploy" do
        result = manager.configure_attach_networks(service)

        expect(result).to eq({ success: true })
        expect(engine).to have_received(:run)
          .with("network:set #{service.dokku_app_name} attach-post-create rd-test-1")
        expect(engine).to have_received(:run)
          .with("network:set #{service.dokku_app_name} attach-post-deploy traefik-net")
      end

      it "skips attach-post-deploy for database services" do
        db_service = create(:service, project: project, name: "db", service_type: "database")
        allow(engine).to receive(:run).and_return({ success: true, output: "" })

        result = manager.configure_attach_networks(db_service)

        expect(result).to eq({ success: true })
        expect(engine).to have_received(:run)
          .with("network:set #{db_service.dokku_app_name} attach-post-create rd-test-1")
        expect(engine).not_to have_received(:run)
          .with(/attach-post-deploy/)
      end
    end
  end
end

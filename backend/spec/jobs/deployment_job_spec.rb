require "rails_helper"

RSpec.describe DeploymentJob, type: :job do
  let!(:server) { create(:server) }
  let!(:project) { create(:project, server: server) }
  let!(:service) do
    create(
      :service,
      project: project,
      branch: "main",
      config: config,
      status: :stopped,
      git_repo: "https://github.com/example/repo.git"
    )
  end
  let!(:deployment) do
    create(:deployment, service: service, status: :pending, branch: "feature")
  end

  let(:config) do
    {
      "nginx" => {
        "clientMaxBodySize" => "50m",
        "readTimeout" => "60s",
        "keepaliveTimeout" => "75s"
      },
      "proxy" => { "enabled" => true, "proxyType" => "nginx" },
      "dockerOptions" => [
        { "phase" => "deploy", "option" => "--restart=on-failure" }
      ],
      "resourceLimits" => [
        { "processType" => "web", "memory" => "512", "cpu" => "1", "nvidiaGpu" => "1" }
      ]
    }
  end

  let(:engine) { instance_double(DokkuEngine) }
  let(:network_manager) { instance_double(ProjectNetworkManager, connect_service: true, ensure_linked_aliases: true, inject_internal_hostnames: true) }

  before do
    create_list(:environment_variable, 2, service: service)
    create_list(:domain, 2, service: service)
    create_list(:storage_mount, 2, service: service)
    create(:process_type, service: service, name: "web", quantity: 2)
    create(:process_type, service: service, name: "worker", quantity: 1)

    allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
    allow(ProjectNetworkManager).to receive(:new).with(project, engine).and_return(network_manager)
    allow(DeploymentsChannel).to receive(:broadcast_to)

    allow(engine).to receive(:app_exists?).and_return(true)
    allow(engine).to receive(:app_create).and_return({ success: true, output: "" })
    allow(engine).to receive(:config_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:domain_add).and_return({ success: true, output: "" })
    allow(engine).to receive(:storage_mount).and_return({ success: true, output: "" })
    allow(engine).to receive(:nginx_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:proxy_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:proxy_enable).and_return({ success: true, output: "" })
    allow(engine).to receive(:proxy_disable).and_return({ success: true, output: "" })
    allow(engine).to receive(:docker_option_add).and_return({ success: true, output: "" })
    allow(engine).to receive(:resource_limit).and_return({ success: true, output: "" })
    allow(engine).to receive(:ports_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:git_set_deploy_branch).and_return({ success: true, output: "" })
    allow(engine).to receive(:run).and_return({ success: true, output: "synced" })
    allow(engine).to receive(:run_streaming).and_yield("deployed").and_return({ success: true, output: "deployed" })
    allow(engine).to receive(:ps_restart).and_return({ success: true, output: "" })
    allow(engine).to receive(:ps_scale).and_return({ success: true, output: "" })
  end

  describe "#perform" do
    context "happy path" do
      it "marks deployment as succeeded, service as running, and broadcasts status" do
        expect {
          DeploymentJob.perform_now(service.id, deployment.id)
        }.to change { deployment.reload.status }.from("pending").to("succeeded")
          .and change { service.reload.status }.to("running")
          .and change(ActivityEvent, :count).by(1)

        expect(deployment.reload.deploy_log).to eq("synceddeployed")
        expect(deployment.completed_at).to be_present

        event = ActivityEvent.last
        expect(event.action).to eq("deployed")
        expect(event.service_name).to eq(service.name)
      end

      it "invokes every dokku command with the correct parameters" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(engine).to have_received(:app_exists?).with(service.dokku_app_name)
        expect(engine).not_to have_received(:app_create)

        service.environment_variables.each do |ev|
          expect(engine).to have_received(:config_set).with(service.dokku_app_name, ev.key, ev.value)
        end

        service.domains.each do |domain|
          expect(engine).to have_received(:domain_add).with(service.dokku_app_name, domain.hostname)
        end

        service.storage_mounts.each do |mount|
          expect(engine).to have_received(:storage_mount).with(service.dokku_app_name, mount.host_path, mount.container_path)
        end

        expect(engine).to have_received(:nginx_set).with(service.dokku_app_name, "client-max-body-size", "50m")
        expect(engine).to have_received(:nginx_set).with(service.dokku_app_name, "proxy-read-timeout", "60s")
        expect(engine).to have_received(:nginx_set).with(service.dokku_app_name, "proxy-send-timeout", "75s")
        expect(engine).to have_received(:proxy_set).with(service.dokku_app_name, "nginx")
        expect(engine).to have_received(:proxy_enable).with(service.dokku_app_name)
        expect(engine).to have_received(:docker_option_add).with(service.dokku_app_name, "deploy", "--restart=on-failure")
        expect(engine).to have_received(:resource_limit).with(
          service.dokku_app_name, "web", memory: "512", cpu: "1", nvidia_gpu: "1"
        )
        expect(engine).to have_received(:git_set_deploy_branch).with(service.dokku_app_name, "main")
        expect(engine).to have_received(:run).with("git:sync #{service.dokku_app_name} #{service.git_repo} feature")
        expect(engine).to have_received(:run_streaming).with("ps:rebuild #{service.dokku_app_name}")

        service.process_types.each do |pt|
          expect(engine).to have_received(:ps_scale).with(service.dokku_app_name, pt.name, pt.quantity)
        end
      end

      it "broadcasts deploying and succeeded events" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(deployment_id: deployment.id, status: "deploying", message: "Deployment started")
        ).once
        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(deployment_id: deployment.id, status: "deploying", log_chunk: "deployed")
        ).once
        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(deployment_id: deployment.id, status: "succeeded")
        ).once
      end
    end

    context "when the app does not exist" do
      before { allow(engine).to receive(:app_exists?).and_return(false) }

      it "creates the app and continues deployment" do
        DeploymentJob.perform_now(service.id, deployment.id)
        expect(engine).to have_received(:app_create).with(service.dokku_app_name)
        expect(deployment.reload.status).to eq("succeeded")
      end
    end

    context "when app creation fails" do
      before do
        allow(engine).to receive(:app_exists?).and_return(false)
        allow(engine).to receive(:app_create).and_return({ success: false, output: "name already taken" })
      end

      it "marks deployment and service as failed and broadcasts the error" do
        expect {
          DeploymentJob.perform_now(service.id, deployment.id)
        }.to change { deployment.reload.status }.to("failed")
          .and change { service.reload.status }.to("error")
          .and change(ActivityEvent, :count).by(1)

        expect(deployment.deploy_log).to match(/name already taken/)
        expect(ActivityEvent.last.action).to eq("created")

        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(status: "failed", message: "App creation failed")
        )
      end
    end

    context "when git sync fails" do
      before do
        allow(engine).to receive(:run).and_return({ success: false, output: "git sync failed" })
      end

      it "marks deployment and service as failed" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(deployment.reload.status).to eq("failed")
        expect(service.reload.status).to eq("error")
        expect(deployment.deploy_log).to match(/git sync failed/)

        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(status: "failed", message: "Git sync failed")
        )
      end
    end

    context "when ps:rebuild fails" do
      before do
        allow(engine).to receive(:run_streaming).and_yield("build error").and_return({ success: false, output: "build error" })
      end

      it "marks deployment and service as failed" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(deployment.reload.status).to eq("failed")
        expect(service.reload.status).to eq("error")
        expect(deployment.deploy_log).to match(/build error/)

        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(status: "failed", message: "Deploy failed")
        )
      end
    end

    context "when scaling fails" do
      before do
        allow(engine).to receive(:ps_scale).and_return({ success: false, output: "scale failed" })
      end

      it "still marks deployment as succeeded (scaling errors are not checked)" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(deployment.reload.status).to eq("succeeded")
        expect(service.reload.status).to eq("running")
      end
    end

    context "when an unexpected exception is raised" do
      before do
        allow(engine).to receive(:app_exists?).and_raise(StandardError.new("network timeout"))
      end

      it "marks deployment and service as failed and broadcasts the exception" do
        expect {
          DeploymentJob.perform_now(service.id, deployment.id)
        }.to change { deployment.reload.status }.to("failed")
          .and change { service.reload.status }.to("error")
          .and change(ActivityEvent, :count).by(1)

        expect(deployment.deploy_log).to match(/network timeout/)
        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(status: "failed", message: /network timeout/)
        )
      end
    end

    context "when the project has no server" do
      let!(:server) { create(:server) }
      let!(:project) { create(:project, server: server) }
      let!(:serverless_service) { create(:service, project: project, status: :stopped) }
      let!(:serverless_deployment) { create(:deployment, service: serverless_service, status: :pending) }

      it "marks deployment as failed immediately" do
        allow_any_instance_of(Project).to receive(:server).and_return(nil)
        DeploymentJob.perform_now(serverless_service.id, serverless_deployment.id)
        expect(serverless_deployment.reload.status).to eq("failed")
        expect(serverless_service.reload.status).to eq("error")
      end
    end

    context "when the server has no SSH key" do
      let!(:no_ssh_server) { create(:server, ssh_key: "") }
      let!(:no_ssh_project) { create(:project, server: no_ssh_server) }
      let!(:no_ssh_service) { create(:service, project: no_ssh_project) }
      let!(:no_ssh_deployment) { create(:deployment, service: no_ssh_service, status: :pending) }

      it "marks deployment as failed immediately" do
        DeploymentJob.perform_now(no_ssh_service.id, no_ssh_deployment.id)
        expect(no_ssh_deployment.reload.status).to eq("failed")
        expect(no_ssh_service.reload.status).to eq("error")
      end
    end

    context "when proxy is disabled in config" do
      let(:config) { { "proxy" => { "enabled" => false } } }

      it "disables the proxy instead of enabling it" do
        DeploymentJob.perform_now(service.id, deployment.id)
        expect(engine).to have_received(:proxy_disable).with(service.dokku_app_name)
        expect(engine).not_to have_received(:proxy_enable)
      end
    end
  end
end

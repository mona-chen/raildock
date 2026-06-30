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
    create(:deployment, service: service, status: :pending, branch: "feature", commit_sha: nil)
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
  let(:host_engine) { instance_double(HostEngine) }
  let(:network_manager) do
    instance_double(
      ProjectNetworkManager,
      configure_attach_networks: { success: true, output: "" },
      connect_service: { success: true, output: "" },
      ensure_linked_aliases: { success: true, output: "" },
      inject_internal_hostnames: { success: true, output: "" }
    )
  end

  before do
    create_list(:environment_variable, 2, service: service)
    create_list(:domain, 2, service: service)
    create(:storage_mount, service: service, host_path: "/var/lib/dokku/data/storage/mount-a")
    create(:storage_mount, service: service, host_path: "/var/lib/dokku/data/storage/mount-b")
    create(:process_type, service: service, name: "web", quantity: 2)
    create(:process_type, service: service, name: "worker", quantity: 1)

    allow(DokkuEngine).to receive(:new).with(server).and_return(engine)
    allow(HostEngine).to receive(:new).with(server).and_return(host_engine)
    allow(ProjectNetworkManager).to receive(:new).with(project, engine).and_return(network_manager)
    allow(DeploymentsChannel).to receive(:broadcast_to)

    allow(engine).to receive(:with_session).and_yield
    allow(host_engine).to receive(:with_session).and_yield
    allow(host_engine).to receive(:builder_available?).and_return(true)
    allow(host_engine).to receive(:dokku_container_name).and_return(nil)
    allow(engine).to receive(:config_export_json).and_return({ success: true, output: "{}" })
    allow(engine).to receive(:app_exists?).and_return(true)
    allow(engine).to receive(:app_create).and_return({ success: true, output: "" })
    allow(DokkuEngine).to receive(:new).and_return(engine)
    allow(engine).to receive(:config_replace_all).and_return({ success: true, output: "" })
    allow(engine).to receive(:domain_add).and_return({ success: true, output: "" })
    allow(engine).to receive(:domain_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:storage_mount).and_return({ success: true, output: "" })
    allow(engine).to receive(:nginx_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:proxy_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:proxy_enable).and_return({ success: true, output: "" })
    allow(engine).to receive(:proxy_disable).and_return({ success: true, output: "" })
    allow(engine).to receive(:docker_option_add).and_return({ success: true, output: "" })
    allow(engine).to receive(:resource_limit).and_return({ success: true, output: "" })
    allow(engine).to receive(:ports_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:ports_clear).and_return({ success: true, output: "" })
    allow(engine).to receive(:builder_set).and_return({ success: true, output: "" })
    allow(engine).to receive(:builder_dockerfile_set_path).and_return({ success: true, output: "" })
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

      it "keeps deploying when a realtime log broadcast fails" do
        allow(DeploymentsChannel).to receive(:broadcast_to) do |_target, payload|
          raise "cable unavailable" if payload[:log_chunk]
        end

        DeploymentJob.perform_now(service.id, deployment.id)

        expect(deployment.reload.status).to eq("succeeded")
        expect(deployment.deploy_log).to eq("synceddeployed")
      end

      it "invokes every dokku command with the correct parameters" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(engine).to have_received(:app_exists?).with(service.dokku_app_name)
        expect(engine).not_to have_received(:app_create)

        # Env sync now happens via batched config:clear + config:set.
        expect(engine).to have_received(:config_replace_all)
          .with(service.dokku_app_name, hash_including(service.environment_variables.first.key => service.environment_variables.first.value))

        expect(engine).to have_received(:domain_set).with(
          service.dokku_app_name,
          *service.domains.map(&:hostname)
        )

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
        expect(engine).to have_received(:git_set_deploy_branch).with(service.dokku_app_name, "feature")
        expect(engine).to have_received(:run).with("git:sync #{service.dokku_app_name} #{service.git_repo} feature")
        expect(engine).to have_received(:run_streaming).with(
          "ps:rebuild #{service.dokku_app_name}",
          cancelled: kind_of(Proc)
        )

        service.process_types.each do |pt|
          expect(engine).to have_received(:ps_scale).with(service.dokku_app_name, pt.name, pt.quantity)
        end
      end

      it "uses the requested commit SHA as the git sync reference" do
        deployment.update!(commit_sha: "abc1234")

        DeploymentJob.perform_now(service.id, deployment.id)

        expect(engine).to have_received(:run).with(
          "git:sync #{service.dokku_app_name} #{service.git_repo} abc1234"
        )
      end

      it "keeps the service deploying when another deployment is pending" do
        create(:deployment, service: service, status: :pending, branch: "main")

        DeploymentJob.perform_now(service.id, deployment.id)

        expect(service.reload.status).to eq("deploying")
      end

      it "broadcasts deploying and succeeded events" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(deployment_id: deployment.id, status: "building", message: "Build started")
        ).once
        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(deployment_id: deployment.id, status: "building", log_chunk: "deployed")
        ).once
        expect(DeploymentsChannel).to have_received(:broadcast_to).with(
          service,
          hash_including(deployment_id: deployment.id, status: "deploying", message: "Release configuration started")
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
        expect(ActivityEvent.last.action).to eq("warning")

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

    context "when the service uses a GitHub App repository" do
      let!(:owner) { create(:user) }
      let!(:project) { create(:project, server: server, user: owner) }

      before do
        service.update!(git_repo: "https://github.com/acme/private-app.git")
        create(
          :git_source,
          user: owner,
          provider: "github",
          access_token: nil,
          installation_id: "12345",
          auth_method: :oauth_app,
          metadata: {
            "repos" => [
              { "full_name" => "acme/private-app", "clone_url" => "https://github.com/acme/private-app.git" }
            ]
          }
        )
        allow(GithubAppService).to receive(:installation_token).with("12345").and_return("install-token")
      end

      it "uses an installation-token clone URL for git sync" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(engine).to have_received(:run).with("git:sync #{service.dokku_app_name} https://x-access-token:install-token@github.com/acme/private-app.git feature")
      end
    end

    context "when a root directory is configured" do
      before do
        service.update!(root_directory: "apps/web")
        allow(host_engine).to receive(:run).and_return({ success: true, output: "" })
        allow(host_engine).to receive(:run).with(/git rev-parse HEAD/).and_return({ success: true, output: "temprepohead\n" })
      end

      it "deploys from a subdirectory-only git repository" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(host_engine).to have_received(:run).with(/git clone --depth 1 -b feature .*\/var\/cache\/raildock\/repos\/#{service.dokku_app_name}/)
        expect(host_engine).to have_received(:run).with(/cp -a .*\/apps\/web\/\. .*\/tmp\/raildock-deploy-#{service.dokku_app_name}-#{deployment.id}/)
        expect(engine).to have_received(:run).with(/git:sync --skip-deploy-branch #{service.dokku_app_name} file:\/\/\/tmp\/raildock-deploy-#{service.dokku_app_name}-#{deployment.id} \S+/)
        expect(engine).to have_received(:run_streaming).with(
          "ps:rebuild #{service.dokku_app_name}",
          cancelled: kind_of(Proc)
        )
      end

      it "sets GIT_REV from the source repository after the build" do
        allow(host_engine).to receive(:run).with(/cd \/var\/cache\/raildock\/repos\/#{service.dokku_app_name} && git rev-parse HEAD/).and_return({ success: true, output: "abc123def456\n" })

        DeploymentJob.perform_now(service.id, deployment.id)

        expect(engine).to have_received(:run).with("config:set --no-restart #{service.dokku_app_name} GIT_REV=abc123def456")
      end

      it "checks out the requested commit SHA before preparing the deploy repo" do
        deployment.update!(commit_sha: "a" * 40)

        DeploymentJob.perform_now(service.id, deployment.id)

        expect(host_engine).to have_received(:run).with(/git clone --depth 1 -b feature/)
        expect(host_engine).to have_received(:run).with(/git fetch --depth 1 origin #{"a" * 40}/)
      end
    end

    context "when ps:rebuild fails" do
      before do
        allow(engine).to receive(:run_streaming).and_yield("build output").and_return(
          { success: false, output: "build output", error: "Remote build session ended unexpectedly" }
        )
      end

      it "marks deployment and service as failed" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(deployment.reload.status).to eq("failed")
        expect(service.reload.status).to eq("error")
        expect(deployment.deploy_log).to include("build output", "Remote build session ended unexpectedly")

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

      it "marks deployment as failed" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(deployment.reload.status).to eq("failed")
        expect(service.reload.status).to eq("error")
        expect(deployment.deploy_log).to include("Scaling failed")
      end
    end

    context "when environment sync fails" do
      before do
        allow(engine).to receive(:config_replace_all)
          .and_return({ success: false, output: "", error: "sync failed" })
      end

      it "marks deployment as failed before building" do
        DeploymentJob.perform_now(service.id, deployment.id)

        expect(deployment.reload.status).to eq("failed")
        expect(service.reload.status).to eq("error")
        expect(engine).not_to have_received(:run_streaming)
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

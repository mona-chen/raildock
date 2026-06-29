require "rails_helper"

RSpec.describe DokkuEngine, type: :service do
  let(:server) do
    create(:server, host: "192.168.1.10")
  end

  subject(:engine) { described_class.new(server) }

  # Helpers to mock Net::SSH completely

  def mock_ssh_channel(output: "", exit_code: 0)
    channel = double("ssh_channel")
    exit_status_data = double("exit_status_data")
    allow(exit_status_data).to receive(:read_long).and_return(exit_code)

    # Fire callbacks immediately when they are registered so output / exit_code
    # are populated before ssh.loop returns.
    allow(channel).to receive(:on_data) { |&block| block.call(channel, output) }
    allow(channel).to receive(:on_extended_data) { |&block| block.call(channel, 1, "") }
    allow(channel).to receive(:on_request).with("exit-status") do |&block|
      block.call(channel, exit_status_data) unless exit_code.nil?
    end
    allow(channel).to receive(:wait)

    ssh = double("ssh_session")
    allow(ssh).to receive(:open_channel).and_yield(channel).and_return(channel)
    allow(ssh).to receive(:loop)
    allow(ssh).to receive(:closed?).and_return(false)
    allow(ssh).to receive(:close)
    allow(ssh).to receive(:host_keys).and_return([])

    allow(Net::SSH).to receive(:start)
      .with(server.host, "dokku", hash_including(key_data: [ server.ssh_key ], non_interactive: true))
      .and_return(ssh)

    channel
  end

  describe "#run" do
    context "when the server has no SSH key" do
      let(:server) { create(:server, ssh_key: "") }

      it "returns an error without connecting" do
        expect(Net::SSH).not_to receive(:start)
        result = engine.run("version")
        expect(result[:success]).to be false
        expect(result[:output]).to eq("No SSH key configured")
      end
    end

    context "when the SSH session executes successfully" do
      it "returns success and captures stdout" do
        channel = mock_ssh_channel(output: "dokku version 0.35.13", exit_code: 0)
        expect(channel).to receive(:exec).with("version").and_yield(channel, true)

        result = engine.run("version")
        expect(result[:success]).to be true
        expect(result[:output]).to eq("dokku version 0.35.13")
      end
    end

    context "when the command exits with a non-zero status" do
      it "returns failure and captures output" do
        channel = mock_ssh_channel(output: "Error: app does not exist", exit_code: 1)
        expect(channel).to receive(:exec).with("apps:exists myapp").and_yield(channel, true)

        result = engine.run("apps:exists myapp")
        expect(result[:success]).to be false
        expect(result[:output]).to eq("Error: app does not exist")
      end
    end

    context "when the channel fails to execute the command" do
      it "returns failure immediately" do
        channel = mock_ssh_channel
        expect(channel).to receive(:exec).with("version").and_yield(channel, false)

        result = engine.run("version")
        expect(result[:success]).to be false
        expect(result[:output]).to eq("Failed to execute command")
      end
    end

    context "when authentication fails" do
      it "returns an authentication failure message" do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::AuthenticationFailed.new("dokku@192.168.1.10")
        )

        result = engine.run("version")
        expect(result[:success]).to be false
        expect(result[:output]).to match(/SSH error/)
      end
    end

    context "when a generic SSH error occurs" do
      it "returns an SSH error message" do
        allow(Net::SSH).to receive(:start).and_raise(StandardError.new("connection refused"))

        result = engine.run("version")
        expect(result[:success]).to be false
        expect(result[:output]).to match(/SSH error/)
      end
    end
  end

  describe "#validate_connection" do
    it "parses dokku and docker versions on success" do
      allow(engine).to receive(:run).with("version").and_return(
        { success: true, output: "dokku version 0.35.13" }
      )
      allow(engine).to receive(:run).with("docker --version").and_return(
        { success: true, output: "Docker version 26.1.0" }
      )

      result = engine.validate_connection
      expect(result[:success]).to be true
      expect(result[:dokku_version]).to eq("0.35.13")
      expect(result[:docker_version]).to eq("26.1.0")
    end

    it "propagates failure from run" do
      allow(engine).to receive(:run).with("version").and_return(
        { success: false, output: "connection refused" }
      )

      result = engine.validate_connection
      expect(result[:success]).to be false
      expect(result[:output]).to eq("connection refused")
    end
  end

  describe "#run_streaming" do
    it "reports an interrupted remote session when no exit status arrives" do
      channel = mock_ssh_channel(output: "still building", exit_code: nil)
      expect(channel).to receive(:exec).with("ps:rebuild myapp").and_yield(channel, true)

      result = engine.run_streaming("ps:rebuild myapp")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ended before Dokku reported an exit status")
    end
  end

  describe "app lifecycle methods" do
    it "#app_create generates the correct command" do
      expect(engine).to receive(:run).with("apps:create myapp").and_return({ success: true, output: "" })
      expect(engine.app_create("myapp")[:success]).to be true
    end

    it "#app_destroy generates the correct command" do
      expect(engine).to receive(:run).with("apps:destroy myapp --force").and_return({ success: true, output: "" })
      expect(engine.app_destroy("myapp")[:success]).to be true
    end

    it "#builder_set generates the correct command" do
      expect(engine).to receive(:run).with("builder:set myapp selected nixpacks").and_return({ success: true, output: "" })
      expect(engine.builder_set("myapp", "nixpacks")[:success]).to be true
    end

    it "#app_exists? returns true when run succeeds" do
      allow(engine).to receive(:run).with("apps:exists myapp").and_return({ success: true, output: "" })
      expect(engine.app_exists?("myapp")).to be true
    end

    it "#app_exists? returns false when run fails" do
      allow(engine).to receive(:run).with("apps:exists myapp").and_return({ success: false, output: "" })
      expect(engine.app_exists?("myapp")).to be false
    end

    it "#apps_list generates the correct command" do
      expect(engine).to receive(:run).with("apps:list").and_return({ success: true, output: "myapp" })
      expect(engine.apps_list[:output]).to eq("myapp")
    end
  end

  describe "process management methods" do
    it "#ps_scale generates the correct command" do
      expect(engine).to receive(:run).with("ps:scale myapp web=3").and_return({ success: true, output: "" })
      engine.ps_scale("myapp", "web", 3)
    end

    it "#ps_restart generates the correct command" do
      expect(engine).to receive(:run).with("ps:restart myapp").and_return({ success: true, output: "" })
      engine.ps_restart("myapp")
    end

    it "#ps_stop generates the correct command" do
      expect(engine).to receive(:run).with("ps:stop myapp").and_return({ success: true, output: "" })
      engine.ps_stop("myapp")
    end

    it "#ps_start generates the correct command" do
      expect(engine).to receive(:run).with("ps:start myapp").and_return({ success: true, output: "" })
      engine.ps_start("myapp")
    end
  end

  describe "configuration methods" do
    it "#config_set generates the correct command" do
      expect(engine).to receive(:run).with("config:set --no-restart myapp KEY=value").and_return({ success: true, output: "" })
      engine.config_set("myapp", "KEY", "value")
    end

    it "#config_set escapes single quotes in values" do
      expect(engine).to receive(:run).with("config:set --no-restart myapp KEY=it\\'s").and_return({ success: true, output: "" })
      engine.config_set("myapp", "KEY", "it's")
    end

    it "#config_unset generates the correct command" do
      expect(engine).to receive(:run).with("config:unset --no-restart myapp KEY").and_return({ success: true, output: "" })
      engine.config_unset("myapp", "KEY")
    end

    it "#config_get generates the correct command" do
      expect(engine).to receive(:run).with("config:get myapp KEY").and_return({ success: true, output: "value" })
      expect(engine.config_get("myapp", "KEY")[:output]).to eq("value")
    end

    it "#config_export generates the correct command" do
      expect(engine).to receive(:run).with("config:export myapp").and_return({ success: true, output: "" })
      engine.config_export("myapp")
    end
  end

  describe "domain methods" do
    it "#domain_add generates the correct command" do
      expect(engine).to receive(:run).with("domains:add myapp example.com").and_return({ success: true, output: "" })
      engine.domain_add("myapp", "example.com")
    end

    it "#domain_remove generates the correct command" do
      expect(engine).to receive(:run).with("domains:remove myapp example.com").and_return({ success: true, output: "" })
      engine.domain_remove("myapp", "example.com")
    end

    it "#domain_clear generates the correct command" do
      expect(engine).to receive(:run).with("domains:clear myapp").and_return({ success: true, output: "" })
      engine.domain_clear("myapp")
    end

    it "#domain_set generates the correct command with multiple hostnames" do
      expect(engine).to receive(:run).with("domains:set myapp example.com www.example.com").and_return({ success: true, output: "" })
      engine.domain_set("myapp", "example.com", "www.example.com")
    end
  end

  describe "storage methods" do
    it "#storage_mount generates the correct command with container-dir" do
      expect(engine).to receive(:run).with("storage:mount myapp /host --container-dir /container").and_return({ success: true, output: "" })
      engine.storage_mount("myapp", "/host", "/container")
    end

    it "#storage_mount generates the correct command with process-type" do
      expect(engine).to receive(:run).with("storage:mount myapp /host --container-dir /container --process-type web").and_return({ success: true, output: "" })
      engine.storage_mount("myapp", "/host", "/container", process_type: "web")
    end

    it "#storage_mount treats an existing identical mount as success" do
      allow(engine).to receive(:run).with("storage:create app-data").and_return({ success: true, output: "" })
      allow(engine).to receive(:run).with("storage:mount myapp app-data --container-dir /data").and_return(
        { success: false, output: 'storage entry "app-data" is already mounted at "/data"' }
      )

      expect(engine.storage_mount("myapp", "app-data", "/data")).to eq(
        success: true,
        output: "mount already exists"
      )
    end

    it "#storage_mount preserves unrelated Dokku failures" do
      failure = { success: false, output: "permission denied" }
      expect(engine).to receive(:run).with("storage:mount myapp /host --container-dir /container").and_return(failure)

      expect(engine.storage_mount("myapp", "/host", "/container")).to eq(failure)
    end

    it "#storage_unmount generates the correct command" do
      expect(engine).to receive(:run).with("storage:unmount myapp /host --container-dir /container").and_return({ success: true, output: "" })
      engine.storage_unmount("myapp", "/host", container_path: "/container")
    end

    it "#storage_list generates the correct command" do
      expect(engine).to receive(:run).with("storage:list myapp").and_return({ success: true, output: "" })
      engine.storage_list("myapp")
    end
  end

  describe "ports methods" do
    it "#ports_add generates the correct command" do
      expect(engine).to receive(:run).with("ports:add myapp http:80:8080").and_return({ success: true, output: "" })
      engine.ports_add("myapp", "http", 80, 8080)
    end

    it "#ports_remove generates the correct command" do
      expect(engine).to receive(:run).with("ports:remove myapp http:80:8080").and_return({ success: true, output: "" })
      engine.ports_remove("myapp", "http", 80, 8080)
    end

    it "#ports_clear generates the correct command" do
      expect(engine).to receive(:run).with("ports:clear myapp").and_return({ success: true, output: "" })
      engine.ports_clear("myapp")
    end

    it "#ports_set generates the correct command" do
      expect(engine).to receive(:run).with("ports:set myapp http:80:8080").and_return({ success: true, output: "" })
      engine.ports_set("myapp", "http", 80, 8080)
    end

    it "#ports_list generates the correct command" do
      expect(engine).to receive(:run).with("ports:list myapp").and_return({ success: true, output: "" })
      engine.ports_list("myapp")
    end
  end

  describe "proxy methods" do
    it "#proxy_enable generates the correct command" do
      expect(engine).to receive(:run).with("proxy:enable myapp").and_return({ success: true, output: "" })
      engine.proxy_enable("myapp")
    end

    it "#proxy_disable generates the correct command" do
      expect(engine).to receive(:run).with("proxy:disable myapp").and_return({ success: true, output: "" })
      engine.proxy_disable("myapp")
    end

    it "#proxy_set generates the correct command" do
      expect(engine).to receive(:run).with("proxy:set myapp nginx").and_return({ success: true, output: "" })
      engine.proxy_set("myapp", "nginx")
    end
  end

  describe "health check methods" do
    it "#checks_enable generates the correct command" do
      expect(engine).to receive(:run).with("checks:enable myapp").and_return({ success: true, output: "" })
      engine.checks_enable("myapp")
    end

    it "#checks_disable generates the correct command" do
      expect(engine).to receive(:run).with("checks:disable myapp").and_return({ success: true, output: "" })
      engine.checks_disable("myapp")
    end

    it "#checks_skip generates the correct command with process types" do
      expect(engine).to receive(:run).with("checks:skip myapp web worker").and_return({ success: true, output: "" })
      engine.checks_skip("myapp", "web", "worker")
    end
  end

  describe "docker option methods" do
    it "#docker_option_add generates the correct command" do
      expect(engine).to receive(:run).with("docker-options:add myapp deploy --restart\\=on-failure").and_return({ success: true, output: "" })
      engine.docker_option_add("myapp", "deploy", "--restart=on-failure")
    end

    it "#docker_option_remove generates the correct command" do
      expect(engine).to receive(:run).with("docker-options:remove myapp deploy --restart\\=on-failure").and_return({ success: true, output: "" })
      engine.docker_option_remove("myapp", "deploy", "--restart=on-failure")
    end

    it "#docker_option_add scopes an option to a process" do
      expect(engine).to receive(:run).with("docker-options:add --process web myapp deploy --label\\ traefik.enable\\=true").and_return({ success: true, output: "" })
      engine.docker_option_add("myapp", "deploy", "--label traefik.enable=true", process: "web")
    end
  end

  describe "resource limit methods" do
    it "#resource_limit builds a command with all options" do
      expect(engine).to receive(:run).with("resource:limit myapp --process-type web --memory 512 --cpu 1 --nvidia-gpu 1").and_return({ success: true, output: "" })
      engine.resource_limit("myapp", "web", memory: "512", cpu: "1", nvidia_gpu: "1")
    end

    it "#resource_limit omits missing options" do
      expect(engine).to receive(:run).with("resource:limit myapp --process-type web --memory 256").and_return({ success: true, output: "" })
      engine.resource_limit("myapp", "web", memory: "256")
    end

    it "#resource_reserve builds a command with all options" do
      expect(engine).to receive(:run).with("resource:reserve myapp --process-type web --memory 512 --cpu 1").and_return({ success: true, output: "" })
      engine.resource_reserve("myapp", "web", memory: "512", cpu: "1")
    end

    it "#resource_reserve omits missing options" do
      expect(engine).to receive(:run).with("resource:reserve myapp --process-type web --cpu 2").and_return({ success: true, output: "" })
      engine.resource_reserve("myapp", "web", cpu: "2")
    end
  end

  describe "SSL / Let's Encrypt methods" do
    it "#letsencrypt_enable sets email and enables" do
      expect(engine).to receive(:run).with("letsencrypt:set myapp email admin@example.com").and_return({ success: true, output: "" })
      expect(engine).to receive(:run).with("letsencrypt:enable myapp").and_return({ success: true, output: "" })
      allow(engine).to receive(:run).with("apps:report myapp --traefik-api-enabled").and_return({ success: true, output: "true" })
      engine.letsencrypt_enable("myapp", "admin@example.com")
    end

    it "#letsencrypt_disable generates the correct command" do
      expect(engine).to receive(:run).with("letsencrypt:disable myapp").and_return({ success: true, output: "" })
      engine.letsencrypt_disable("myapp")
    end

    it "#letsencrypt_auto_renew generates the correct command" do
      expect(engine).to receive(:run).with("letsencrypt:auto-renew myapp").and_return({ success: true, output: "" })
      engine.letsencrypt_auto_renew("myapp")
    end
  end

  describe "git deployment methods" do
    it "#deploy generates the correct command with default branch" do
      expect(engine).to receive(:run).with("git:sync myapp https://github.com/example/repo.git main").and_return({ success: true, output: "" })
      engine.deploy("myapp", "https://github.com/example/repo.git")
    end

    it "#deploy generates the correct command with custom branch" do
      expect(engine).to receive(:run).with("git:sync myapp https://github.com/example/repo.git develop").and_return({ success: true, output: "" })
      engine.deploy("myapp", "https://github.com/example/repo.git", branch: "develop")
    end

    it "#git_set_deploy_branch generates the correct command" do
      expect(engine).to receive(:run).with("git:set myapp deploy-branch main").and_return({ success: true, output: "" })
      engine.git_set_deploy_branch("myapp", "main")
    end
  end

  describe "logs method" do
    it "#logs generates the correct command with defaults" do
      expect(engine).to receive(:run).with("logs myapp --num 100").and_return({ success: true, output: "" })
      engine.logs("myapp")
    end

    it "#logs generates the correct command with custom lines and tail" do
      expect(engine).to receive(:run).with("logs myapp --num 500 --tail").and_return({ success: true, output: "" })
      engine.logs("myapp", lines: 500, tail: true)
    end
  end

  describe "datastore plugin methods" do
    %w[postgres redis mysql mongo].each do |plugin|
      it "##{plugin}_create generates the correct command" do
        expect(engine).to receive(:run).with("#{plugin}:create mydb").and_return({ success: true, output: "" })
        engine.public_send(:"#{plugin}_create", "mydb")
      end
    end

    %w[postgres redis mysql].each do |plugin|
      it "##{plugin}_destroy generates the correct command" do
        expect(engine).to receive(:run).with("#{plugin}:destroy mydb --force").and_return({ success: true, output: "" })
        engine.public_send(:"#{plugin}_destroy", "mydb")
      end
    end

    %w[postgres redis mysql mongo].each do |plugin|
      it "##{plugin}_link generates the correct command" do
        expect(engine).to receive(:run).with("#{plugin}:link mydb myapp").and_return({ success: true, output: "" })
        engine.public_send(:"#{plugin}_link", "mydb", "myapp")
      end
    end

    %w[postgres redis mysql mongo].each do |plugin|
      it "##{plugin}_unlink generates the correct command" do
        expect(engine).to receive(:run).with("#{plugin}:unlink mydb myapp").and_return({ success: true, output: "" })
        engine.public_send(:"#{plugin}_unlink", "mydb", "myapp")
      end
    end

    it "#postgres_export generates the correct command" do
      expect(engine).to receive(:run).with("postgres:export mydb").and_return({ success: true, output: "" })
      engine.postgres_export("mydb")
    end

    it "#postgres_import generates the correct command" do
      expect(engine).to receive(:run_with_stdin).with("postgres:import mydb", "dump-data").and_return({ success: true, output: "" })
      engine.postgres_import("mydb", "dump-data")
    end
  end

  describe "cron methods" do
    it "#cron_set generates the correct command" do
      expect(engine).to receive(:run).with("cron:set myapp \\*\\ \\*\\ \\*\\ \\*\\ \\* echo\\ hello").and_return({ success: true, output: "" })
      engine.cron_set("myapp", "* * * * *", "echo hello")
    end

    it "#cron_clear generates the correct command" do
      expect(engine).to receive(:run).with("cron:clear myapp").and_return({ success: true, output: "" })
      engine.cron_clear("myapp")
    end
  end

  describe "metrics / status methods" do
    it "#metrics generates the correct command" do
      expect(engine).to receive(:run).with("ps:report myapp").and_return({ success: true, output: "" })
      engine.metrics("myapp")
    end

    it "#container_status generates the correct command" do
      expect(engine).to receive(:run).with("ps:report myapp --running").and_return({ success: true, output: "" })
      engine.container_status("myapp")
    end

    it "#app_report generates the correct command" do
      expect(engine).to receive(:run).with("apps:report myapp").and_return({ success: true, output: "" })
      engine.app_report("myapp")
    end
  end

  describe "DokkuTerminalSession pre-open failure classification" do
    subject(:session) { DokkuTerminalSession.allocate }

    it "reports a missing shell with the OCI 'no such file' stderr and exit 127" do
      session.instance_variable_set(:@shell, "/bin/zsh")
      session.instance_variable_set(:@error_buffer, "OCI runtime exec failed: exec failed: unable to start container process: exec: \"/bin/zsh\": stat /bin/zsh: no such file or directory\n")
      session.instance_variable_set(:@data_buffer, "")
      session.instance_variable_set(:@exit_status, 127)

      message = session.send(:classify_pre_open_failure)
      expect(message).to include("/bin/zsh")
      expect(message).to include("not available in this container")
    end

    it "reports a non-zero exit before on_open as a generic shell failure" do
      session.instance_variable_set(:@shell, "/bin/sh")
      session.instance_variable_set(:@error_buffer, "")
      session.instance_variable_set(:@data_buffer, "")
      session.instance_variable_set(:@exit_status, 2)

      message = session.send(:classify_pre_open_failure)
      expect(message).to include("status 2")
    end

    it "returns nil for a clean close (exit 0, no error buffer)" do
      session.instance_variable_set(:@shell, "/bin/sh")
      session.instance_variable_set(:@error_buffer, "")
      session.instance_variable_set(:@data_buffer, "")
      session.instance_variable_set(:@exit_status, 0)

      expect(session.send(:classify_pre_open_failure)).to be_nil
    end

    it "detects SSH connection issues from the error buffer" do
      session.instance_variable_set(:@shell, "/bin/sh")
      session.instance_variable_set(:@error_buffer, "ssh: connect to host: Connection refused\n")
      session.instance_variable_set(:@data_buffer, "")
      session.instance_variable_set(:@exit_status, 255)

      message = session.send(:classify_pre_open_failure)
      expect(message).to include("SSH connection lost")
    end

    it "classifies a quick close with OCI text on stdout as a missing shell, even when @opened is true" do
      session.instance_variable_set(:@shell, "/bin/zsh")
      session.instance_variable_set(:@opened, true)
      session.instance_variable_set(:@opened_at, Time.now - 0.2)
      session.instance_variable_set(:@error_buffer, "")
      session.instance_variable_set(:@data_buffer, "-----> Filesystem changes may not persist after container restarts\nOCI runtime exec failed: exec failed: unable to start container process: exec: \"/bin/zsh\": stat /bin/zsh: no such file or directory\n")
      session.instance_variable_set(:@exit_status, 127)

      expect(session.send(:quick_close_with_startup_error?)).to be(true)
      expect(session.send(:classify_pre_open_failure)).to include("/bin/zsh")
    end

    it "ignores a long-lived session that later closes cleanly" do
      session.instance_variable_set(:@shell, "/bin/sh")
      session.instance_variable_set(:@opened, true)
      session.instance_variable_set(:@opened_at, Time.now - 30)
      session.instance_variable_set(:@error_buffer, "")
      session.instance_variable_set(:@data_buffer, "")

      expect(session.send(:quick_close_with_startup_error?)).to be(false)
    end

    it "surfaces the dokku 'service does not exist' message" do
      session.instance_variable_set(:@shell, "/bin/sh")
      session.instance_variable_set(:@opened, true)
      session.instance_variable_set(:@opened_at, Time.now - 0.1)
      session.instance_variable_set(:@error_buffer, "")
      session.instance_variable_set(:@data_buffer, " !     Postgres service alexandrie-postgres-5e5018f0 does not exist\r\n")
      session.instance_variable_set(:@exit_status, 1)

      expect(session.send(:quick_close_with_startup_error?)).to be(true)
      message = session.send(:classify_pre_open_failure)
      expect(message).to include("does not exist")
      expect(message).to include("alexandrie-postgres-5e5018f0")
    end

    it "surfaces the dokku 'app has not been deployed' message" do
      session.instance_variable_set(:@shell, "/bin/sh")
      session.instance_variable_set(:@opened, true)
      session.instance_variable_set(:@opened_at, Time.now - 0.1)
      session.instance_variable_set(:@error_buffer, "")
      session.instance_variable_set(:@data_buffer, " !     App tween-face-verification has not been deployed\r\n")
      session.instance_variable_set(:@exit_status, 1)

      message = session.send(:classify_pre_open_failure)
      expect(message).to include("tween-face-verification")
      expect(message).to include("Deploy tab")
    end
  end
end

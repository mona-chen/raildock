require "net/ssh"

class DokkuEngine
  attr_reader :server

  def initialize(server)
    @server = server
  end

  # ── Core SSH Runner ──────────────────────────

  def run(command)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    output = ""
    exit_code = nil

    Net::SSH.start(server.host, "dokku", key_data: [server.ssh_key], non_interactive: true) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec("#{command}") do |_, success|
          unless success
            return { success: false, output: "Failed to execute command" }
          end

          ch.on_data { |_, data| output += data }
          ch.on_extended_data { |_, type, data| output += data }
          ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
        end
      end
      channel.wait
    end

    { success: exit_code == 0, output: output }
  rescue Net::SSH::AuthenticationFailed => e
    { success: false, output: "Authentication failed: #{e.message}" }
  rescue => e
    { success: false, output: "SSH error: #{e.message}" }
  end

  # Run a command and yield each line of output in real-time
  def run_streaming(command)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    output = ""
    exit_code = nil

    Net::SSH.start(server.host, "dokku", key_data: [server.ssh_key], non_interactive: true) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec("#{command}") do |_, success|
          unless success
            return { success: false, output: "Failed to execute command" }
          end

          ch.on_data do |_, data|
            output += data
            yield(data) if block_given?
          end
          ch.on_extended_data do |_, type, data|
            output += data
            yield(data) if block_given?
          end
          ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
        end
      end
      channel.wait
    end

    { success: exit_code == 0, output: output }
  rescue Net::SSH::AuthenticationFailed => e
    { success: false, output: "Authentication failed: #{e.message}" }
  rescue => e
    { success: false, output: "SSH error: #{e.message}" }
  end

  # ── Server Validation ────────────────────────

  def validate_connection
    result = run("version")
    if result[:success]
      # Parse dokku version from output
      dokku_version = result[:output].match(/dokku version (\S+)/)&.[](1) || "unknown"
      # Also try to get docker version
      docker_result = run("docker --version")
      docker_version = docker_result[:output].match(/Docker version ([\d\.]+)/)&.[](1) || "unknown"
      {
        success: true,
        dokku_version: dokku_version,
        docker_version: docker_version,
        os: "Ubuntu (detected)",
        uptime: "unknown"
      }
    else
      { success: false, output: result[:output] }
    end
  end

  # ── App Lifecycle ────────────────────────────

  def app_create(app_name)
    run("apps:create #{app_name}")
  end

  def app_destroy(app_name)
    run("apps:destroy #{app_name} --force")
  end

  def app_exists?(app_name)
    result = run("apps:exists #{app_name}")
    result[:success]
  end

  def apps_list
    run("apps:list")
  end

  # ── Process Management ───────────────────────

  def ps_scale(app_name, process_type, quantity)
    run("ps:scale #{app_name} #{process_type}=#{quantity}")
  end

  def ps_restart(app_name)
    run("ps:restart #{app_name}")
  end

  def ps_rebuild(app_name)
    run("ps:rebuild #{app_name}")
  end

  def ps_stop(app_name)
    run("ps:stop #{app_name}")
  end

  def ps_start(app_name)
    run("ps:start #{app_name}")
  end

  # ── Configuration / Env Vars ─────────────────

  def config_set(app_name, key, value)
    run("config:set --no-restart #{app_name} #{key}='#{value.gsub("'", "'\\''")}'")
  end

  def config_unset(app_name, key)
    run("config:unset --no-restart #{app_name} #{key}")
  end

  def config_get(app_name, key)
    run("config:get #{app_name} #{key}")
  end

  def config_export(app_name)
    run("config:export #{app_name}")
  end

  # ── Domains ──────────────────────────────────

  def domain_add(app_name, hostname)
    run("domains:add #{app_name} #{hostname}")
  end

  def domain_remove(app_name, hostname)
    run("domains:remove #{app_name} #{hostname}")
  end

  def domain_clear(app_name)
    run("domains:clear #{app_name}")
  end

  def domain_set(app_name, *hostnames)
    run("domains:set #{app_name} #{hostnames.join(" ")}")
  end

  # ── Storage / Volumes ────────────────────────

  def storage_mount(app_name, host_path, container_path)
    run("storage:mount #{app_name} #{host_path}:#{container_path}")
  end

  def storage_unmount(app_name, host_path, container_path)
    run("storage:unmount #{app_name} #{host_path}:#{container_path}")
  end

  # ── Nginx Settings ───────────────────────────

  def nginx_set(app_name, property, value)
    run("nginx:set #{app_name} #{property} #{value}")
  end

  def nginx_show_config(app_name)
    run("nginx:show-config #{app_name}")
  end

  # ── Proxy ────────────────────────────────────

  def proxy_enable(app_name)
    run("proxy:enable #{app_name}")
  end

  def proxy_disable(app_name)
    run("proxy:disable #{app_name}")
  end

  def proxy_ports_set(app_name, scheme, host_port, container_port)
    run("proxy:ports-set #{app_name} #{scheme}:#{host_port}:#{container_port}")
  end

  def proxy_set(app_name, proxy_type)
    run("proxy:set #{app_name} #{proxy_type}")
  end

  # ── Health Checks ────────────────────────────

  def checks_enable(app_name)
    run("checks:enable #{app_name}")
  end

  def checks_disable(app_name)
    run("checks:disable #{app_name}")
  end

  def checks_skip(app_name, *process_types)
    run("checks:skip #{app_name} #{process_types.join(" ")}")
  end

  # ── Docker Options ───────────────────────────

  def docker_option_add(app_name, phase, option)
    run("docker-options:add #{app_name} #{phase} #{option}")
  end

  def docker_option_remove(app_name, phase, option)
    run("docker-options:remove #{app_name} #{phase} #{option}")
  end

  # ── Resource Limits ──────────────────────────

  def resource_limit(app_name, process_type, memory: nil, cpu: nil, nvidia_gpu: nil)
    args = []
    args << "--memory #{memory}" if memory
    args << "--cpu #{cpu}" if cpu
    args << "--nvidia-gpu #{nvidia_gpu}" if nvidia_gpu
    run("resource:limit #{app_name} #{process_type} #{args.join(" ")}")
  end

  def resource_reserve(app_name, process_type, memory: nil, cpu: nil)
    args = []
    args << "--memory #{memory}" if memory
    args << "--cpu #{cpu}" if cpu
    run("resource:reserve #{app_name} #{process_type} #{args.join(" ")}")
  end

  # ── Let's Encrypt / SSL ──────────────────────

  def letsencrypt_enable(app_name, email)
    run("letsencrypt:set #{app_name} email #{email}")
    run("letsencrypt:enable #{app_name}")
  end

  def letsencrypt_disable(app_name)
    run("letsencrypt:disable #{app_name}")
  end

  def letsencrypt_auto_renew(app_name)
    run("letsencrypt:auto-renew #{app_name}")
  end

  # ── Git Deployment ───────────────────────────

  def deploy(app_name, repo_url, branch: "main")
    run("git:sync #{app_name} #{repo_url} #{branch}")
  end

  def deploy_from_image(app_name, image)
    run("git:from-image #{app_name} #{image}")
  end

  def git_set_deploy_branch(app_name, branch)
    run("git:set #{app_name} deploy-branch #{branch}")
  end

  # ── Logs ─────────────────────────────────────

  def logs(app_name, lines: 100, tail: false)
    cmd = "logs #{app_name} --num #{lines}"
    cmd += " --tail" if tail
    run(cmd)
  end

  # ── Datastore Plugins ────────────────────────

  def postgres_create(service_name)
    run("postgres:create #{service_name}")
  end

  def redis_create(service_name)
    run("redis:create #{service_name}")
  end

  def mysql_create(service_name)
    run("mysql:create #{service_name}")
  end

  def mongo_create(service_name)
    run("mongo:create #{service_name}")
  end

  def postgres_destroy(service_name)
    run("postgres:destroy #{service_name} --force")
  end

  def redis_destroy(service_name)
    run("redis:destroy #{service_name} --force")
  end

  def mysql_destroy(service_name)
    run("mysql:destroy #{service_name} --force")
  end

  def postgres_link(service_name, app_name)
    run("postgres:link #{service_name} #{app_name}")
  end

  def redis_link(service_name, app_name)
    run("redis:link #{service_name} #{app_name}")
  end

  def mysql_link(service_name, app_name)
    run("mysql:link #{service_name} #{app_name}")
  end

  def mongo_link(service_name, app_name)
    run("mongo:link #{service_name} #{app_name}")
  end

  def postgres_unlink(service_name, app_name)
    run("postgres:unlink #{service_name} #{app_name}")
  end

  def redis_unlink(service_name, app_name)
    run("redis:unlink #{service_name} #{app_name}")
  end

  def mysql_unlink(service_name, app_name)
    run("mysql:unlink #{service_name} #{app_name}")
  end

  def mongo_unlink(service_name, app_name)
    run("mongo:unlink #{service_name} #{app_name}")
  end

  def postgres_export(service_name, path)
    run("postgres:export #{service_name} > #{path}")
  end

  def postgres_import(service_name, path)
    run("postgres:import #{service_name} < #{path}")
  end

  # ── Cron ─────────────────────────────────────

  def cron_set(app_name, schedule, command)
    run("cron:set #{app_name} #{schedule} #{command}")
  end

  def cron_clear(app_name)
    run("cron:clear #{app_name}")
  end

  # ── Metrics / Status ─────────────────────────

  def metrics(app_name)
    run("ps:report #{app_name}")
  end

  def container_status(app_name)
    run("ps:report #{app_name} --process-status")
  end

  def app_report(app_name)
    run("apps:report #{app_name}")
  end
end

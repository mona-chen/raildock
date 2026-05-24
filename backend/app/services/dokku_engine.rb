require "net/ssh"
require "shellwords"

# SSH connection configuration constants
module DokkuEngineConstants
  SSH_TIMEOUT = 30
  SSH_CONNECTION_TIMEOUT = 10
  SSH_USER = "dokku"
  
  # Regex patterns for parsing Dokku output
  DOKKU_VERSION_REGEX = /dokku version (\S+)/
  DOCKER_VERSION_REGEX = /Docker version ([\d\.]+)/
  DOKKU_APPS_LOCKED_REGEX = /Deploy lock exists|locked/i
end

class DokkuEngine
  attr_reader :server

  # Shared Lockbox instance for encryption/decryption (class-level for efficiency)
  LOCKBOX = Lockbox.new(key: Lockbox.master_key, encode: true)

  def initialize(server)
    @server = server
  end

  # ── Core SSH Runner ──────────────────────────

  def run(command)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    output = ""
    exit_code = nil

    Net::SSH.start(*ssh_connection_options) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(command) do |_, success|
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
  rescue Net::SSH::ConnectionTimeout
    { success: false, output: "SSH connection timed out" }
  rescue Net::SSH::ChannelOpenFailed => e
    { success: false, output: "SSH channel failed: #{e.message}" }
  rescue => e
    { success: false, output: "SSH error: #{e.message}" }
  end

  # Run a command piping data to stdin
  def run_with_stdin(command, stdin_data)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    output = ""
    exit_code = nil

    Net::SSH.start(*ssh_connection_options) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(command) do |_, success|
          unless success
            return { success: false, output: "Failed to execute command" }
          end

          ch.send_data(stdin_data)
          ch.eof!

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
  rescue Net::SSH::ConnectionTimeout
    { success: false, output: "SSH connection timed out" }
  rescue Net::SSH::ChannelOpenFailed => e
    { success: false, output: "SSH channel failed: #{e.message}" }
  rescue => e
    { success: false, output: "SSH error: #{e.message}" }
  end

  # Run a command and yield each line of output in real-time
  def run_streaming(command)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    output = ""
    exit_code = nil

    Net::SSH.start(*ssh_connection_options) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(command) do |_, success|
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
  rescue Net::SSH::ConnectionTimeout
    { success: false, output: "SSH connection timed out" }
  rescue Net::SSH::ChannelOpenFailed => e
    { success: false, output: "SSH channel failed: #{e.message}" }
  rescue => e
    { success: false, output: "SSH error: #{e.message}" }
  end

  # ── Server Validation ────────────────────────

  def validate_connection
    result = run("version")
    if result[:success]
      dokku_version = result[:output].match(DokkuEngineConstants::DOKKU_VERSION_REGEX)&.[](1) || "unknown"
      docker_result = run("docker --version")
      docker_version = docker_result[:output].match(DokkuEngineConstants::DOCKER_VERSION_REGEX)&.[](1) || "unknown"

      # Detect public IP for magic domain support (sslip.io, nip.io, etc.)
      #
      # When the server host is already an IP address, use it directly.
      # Otherwise try to detect via an external service. Note: the dokku SSH
      # user only accepts dokku commands, so we detect from the backend host.
      public_ip = server.host if server.host.to_s.match?(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)

      if public_ip.blank?
        begin
          require "open-uri"
          public_ip = URI.open("https://ifconfig.me/ip", read_timeout: 5).read.strip
        rescue
          public_ip = nil
        end
      end

      {
        success: true,
        dokku_version: dokku_version,
        docker_version: docker_version,
        os: "Ubuntu (detected)",
        uptime: "unknown",
        public_ip: public_ip
      }
    else
      { success: false, output: result[:output] }
    end
  end

  # ── App Lifecycle ────────────────────────────

  def app_create(app_name)
    run("apps:create #{escape(app_name)}")
  end

  def app_destroy(app_name)
    run("apps:destroy #{escape(app_name)} --force")
  end

  def app_exists?(app_name)
    result = run("apps:exists #{escape(app_name)}")
    result[:success]
  end

  def apps_list
    run("apps:list")
  end

  # ── Process Management ───────────────────────

  def ps_scale(app_name, process_type, quantity)
    run("ps:scale #{escape(app_name)} #{escape(process_type)}=#{quantity.to_i}")
  end

  def ps_restart(app_name)
    run("ps:restart #{escape(app_name)}")
  end

  def ps_rebuild(app_name)
    run("ps:rebuild #{escape(app_name)}")
  end

  def ps_stop(app_name)
    run("ps:stop #{escape(app_name)}")
  end

  def ps_start(app_name)
    run("ps:start #{escape(app_name)}")
  end

  # ── Configuration / Env Vars ─────────────────

  def config_set(app_name, key, value)
    run("config:set --no-restart #{escape(app_name)} #{escape(key)}=#{escape(value)}")
  end

  def config_unset(app_name, key)
    run("config:unset --no-restart #{escape(app_name)} #{escape(key)}")
  end

  def config_get(app_name, key)
    run("config:get #{escape(app_name)} #{escape(key)}")
  end

  def config_show(app_name)
    run("config:show --merged #{escape(app_name)}")
  end

  def config_clear(app_name)
    run("config:clear #{escape(app_name)}")
  end

  def config_export(app_name)
    run("config:export #{escape(app_name)}")
  end

  # ── Domains ──────────────────────────────────

  def domain_add(app_name, hostname)
    run("domains:add #{escape(app_name)} #{escape(hostname)}")
  end

  def domain_remove(app_name, hostname)
    run("domains:remove #{escape(app_name)} #{escape(hostname)}")
  end

  def domain_clear(app_name)
    run("domains:clear #{escape(app_name)}")
  end

  def domain_set(app_name, *hostnames)
    run("domains:set #{escape(app_name)} #{hostnames.map { |h| escape(h) }.join(" ")}")
  end

  # ── Storage / Volumes ────────────────────────
  # Dokku storage:mount syntax: storage:mount <app> <host-path-or-name> [--container-dir <path>] [--process-type <type>]
  # The host path can be a named volume or absolute host path.
  # For host paths with colons, use --container-dir to specify the container mount point.
  def storage_mount(app_name, host_path, container_path, process_type: nil)
    cmd = "storage:mount #{escape(app_name)} #{escape(host_path)} --container-dir #{escape(container_path)}"
    cmd += " --process-type #{escape(process_type)}" if process_type
    run(cmd)
  end

  def storage_unmount(app_name, host_path, container_path: nil)
    cmd = "storage:unmount #{escape(app_name)} #{escape(host_path)}"
    cmd += " --container-dir #{escape(container_path)}" if container_path
    run(cmd)
  end

  def storage_list(app_name)
    run("storage:list #{escape(app_name)}")
  end

  # ── One-off Tasks ────────────────────────────

  def run_one_off(app_name, command)
    run("run #{escape(app_name)} #{escape(command)}")
  end

  # ── Container Access ────────────────────────

  def enter_container(app_name, process_type: "web")
    run("enter #{escape(app_name)} #{escape(process_type)} /bin/bash")
  end

  def exec_in_container(app_name, command, process_type: "web")
    run("exec #{escape(app_name)} #{escape(process_type)} #{escape(command)}")
  end

  # ── Traefik Settings ──────────────────────────

  def traefik_set(app_name, property, value)
    run("traefik:set #{escape(app_name)} #{escape(property)} #{escape(value)}")
  end

  def traefik_set_global(property, value)
    run("traefik:set --global #{escape(property)} #{escape(value)}")
  end

  def traefik_show_config(app_name)
    run("traefik:show-config #{escape(app_name)}")
  end

  def traefik_report(app_name = nil)
    if app_name
      run("traefik:report #{escape(app_name)}")
    else
      run("traefik:report")
    end
  end

  def traefik_logs(num: 100, tail: false)
    cmd = "traefik:logs"
    cmd += " --num #{num.to_i}"
    cmd += " --tail" if tail
    run(cmd)
  end

  def traefik_start
    run("traefik:start")
  end

  def traefik_stop
    run("traefik:stop")
  end

  # ── Proxy ────────────────────────────────────
  # Dokku uses separate "ports" plugin for port management, not proxy:ports-*
  def proxy_enable(app_name)
    run("proxy:enable #{escape(app_name)}")
  end

  def proxy_disable(app_name)
    run("proxy:disable #{escape(app_name)}")
  end

  def proxy_set(app_name, proxy_type)
    run("proxy:set #{escape(app_name)} #{escape(proxy_type)}")
  end

  def proxy_report(app_name)
    run("proxy:report #{escape(app_name)}")
  end

  # ── Ports Management ─────────────────────────
  # Dokku uses the ports plugin for port management
  # Syntax: ports:add <app> [<scheme>:<host-port>:<container-port>...]
  def ports_add(app_name, scheme, host_port, container_port)
    run("ports:add #{escape(app_name)} #{escape(scheme)}:#{host_port.to_i}:#{container_port.to_i}")
  end

  def ports_remove(app_name, scheme, host_port, container_port)
    run("ports:remove #{escape(app_name)} #{escape(scheme)}:#{host_port.to_i}:#{container_port.to_i}")
  end

  def ports_clear(app_name)
    run("ports:clear #{escape(app_name)}")
  end

  def ports_set(app_name, scheme, host_port, container_port)
    run("ports:set #{escape(app_name)} #{escape(scheme)}:#{host_port.to_i}:#{container_port.to_i}")
  end

  def ports_list(app_name)
    run("ports:list #{escape(app_name)}")
  end

  # Bulk set standard web port mappings for an app.
  # Maps public 80/443 to the app's internal container port.
  def sync_port_mappings(app_name, target_port)
    run("ports:clear #{escape(app_name)}")
    run("ports:set #{escape(app_name)} http:80:#{target_port.to_i} https:443:#{target_port.to_i}")
  end

  # ── App Locking ──────────────────────────────

  def app_lock(app_name)
    run("apps:lock #{escape(app_name)}")
  end

  def app_unlock(app_name)
    run("apps:unlock #{escape(app_name)}")
  end

  def app_locked?(app_name)
    result = run("apps:locked #{escape(app_name)}")
    result[:output] =~ DokkuEngineConstants::DOKKU_APPS_LOCKED_REGEX
  end

  # ── Maintenance Mode ─────────────────────────
  # NOTE: maintenance plugin is NOT part of core Dokku - requires external plugin
  # Core Dokku provides this via nginx-vhosts plugin or custom maintenance page
  # We implement this as a no-op or document it requires the maintenance plugin
  def maintenance_enable(app_name)
    run("maintenance:on #{escape(app_name)}")
  end

  def maintenance_disable(app_name)
    run("maintenance:off #{escape(app_name)}")
  end

  def maintenance_show(app_name)
    run("maintenance:report #{escape(app_name)}")
  end

  # ── Health Checks ────────────────────────────

  def checks_enable(app_name)
    run("checks:enable #{escape(app_name)}")
  end

  def checks_disable(app_name)
    run("checks:disable #{escape(app_name)}")
  end

  def checks_skip(app_name, *process_types)
    run("checks:skip #{escape(app_name)} #{process_types.map { |pt| escape(pt) }.join(" ")}")
  end

  # ── Docker Options ───────────────────────────

  def docker_option_add(app_name, phase, option)
    run("docker-options:add #{escape(app_name)} #{escape(phase)} #{escape(option)}")
  end

  def docker_option_remove(app_name, phase, option)
    run("docker-options:remove #{escape(app_name)} #{escape(phase)} #{escape(option)}")
  end

  # ── Resource Limits ──────────────────────────
  # Dokku resource commands require --process-type flag before the process type value
  def resource_limit(app_name, process_type, memory: nil, cpu: nil, nvidia_gpu: nil)
    args = ["--process-type #{escape(process_type)}"]
    args << "--memory #{escape(memory)}" if memory
    args << "--cpu #{escape(cpu)}" if cpu
    args << "--nvidia-gpu #{nvidia_gpu.to_i}" if nvidia_gpu
    run("resource:limit #{escape(app_name)} #{args.join(" ")}")
  end

  def resource_reserve(app_name, process_type, memory: nil, cpu: nil)
    args = ["--process-type #{escape(process_type)}"]
    args << "--memory #{escape(memory)}" if memory
    args << "--cpu #{escape(cpu)}" if cpu
    run("resource:reserve #{escape(app_name)} #{args.join(" ")}")
  end

  def resource_report(app_name)
    run("resource:report #{escape(app_name)}")
  end

  def resource_limit_clear(app_name, process_type)
    run("resource:limit:clear #{escape(app_name)} --process-type #{escape(process_type)}")
  end

  def resource_reserve_clear(app_name, process_type)
    run("resource:reserve:clear #{escape(app_name)} --process-type #{escape(process_type)}")
  end

  # ── Let's Encrypt / SSL ──────────────────────
  # NOTE: letsencrypt plugin is NOT part of core Dokku - requires dokku-letsencrypt plugin
  # Core Dokku provides certs:* commands for manual SSL certificate management
  def letsencrypt_enable(app_name, email)
    result = run("apps:report #{escape(app_name)} --traefik-api-enabled")
    if result[:output].include?("true")
      run("letsencrypt:set #{escape(app_name)} email #{escape(email)}")
      run("letsencrypt:enable #{escape(app_name)}")
    else
      { success: false, output: "Let's Encrypt requires traefik proxy. Enable traefik first with proxy:set traefik" }
    end
  end

  def letsencrypt_disable(app_name)
    run("letsencrypt:disable #{escape(app_name)}")
  end

  def letsencrypt_auto_renew(app_name)
    run("letsencrypt:auto-renew #{escape(app_name)}")
  end

  # ── SSL Certificates ─────────────────────────

  def certs_add(app_name, cert_file, key_file)
    run_with_stdin("certs:add #{escape(app_name)}", "#{cert_file}\n#{key_file}")
  end

  def certs_remove(app_name)
    run("certs:remove #{escape(app_name)}")
  end

  def certs_show(app_name)
    run("certs:show #{escape(app_name)}")
  end

  def certs_update(app_name, cert_file, key_file)
    run_with_stdin("certs:update #{escape(app_name)}", "#{cert_file}\n#{key_file}")
  end

  def certs_report(app_name)
    run("certs:report #{escape(app_name)}")
  end

  # ── Network Management ───────────────────────

  def network_create(network_name)
    run("network:create #{escape(network_name)}")
  end

  def network_connect(app_name, network_name)
    run("network:connect #{escape(app_name)} #{escape(network_name)}")
  end

  def network_disconnect(app_name, network_name)
    run("network:disconnect #{escape(app_name)} #{escape(network_name)}")
  end

  def network_list
    run("network:list")
  end

  def network_report(app_name)
    run("network:report #{escape(app_name)}")
  end

  # ── Build Management ────────────────────────

  def builds_list(app_name)
    run("builds:list #{escape(app_name)}")
  end

  def builds_remove(app_name, build_id)
    run("builds:remove #{escape(app_name)} #{escape(build_id)}")
  end

  # ── Git Deployment ───────────────────────────

  def deploy(app_name, repo_url, branch: "main")
    run("git:sync #{escape(app_name)} #{escape(repo_url)} #{escape(branch)}")
  end

  def deploy_from_image(app_name, image)
    run("git:from-image #{escape(app_name)} #{escape(image)}")
  end

  def git_set_deploy_branch(app_name, branch)
    run("git:set #{escape(app_name)} deploy-branch #{escape(branch)}")
  end

  # Note: git:set deploy-key does NOT exist in Dokku. Use git:generate-deploy-key to create
  # a deploy key, then git:public-key to retrieve it. The deploy key is set via the git plugin's
  # deploy-key property which is managed through the plugin's internal mechanisms.
  def git_generate_deploy_key(app_name)
    run("git:generate-deploy-key #{escape(app_name)}")
  end

  def git_public_key(app_name)
    run("git:public-key #{escape(app_name)}")
  end

  def git_remove_deploy_key(app_name)
    run("git:generate-deploy-key #{escape(app_name)} --reset")
  end

  # ── Logs ─────────────────────────────────────

  def logs(app_name, lines: 100, tail: false)
    cmd = "logs #{escape(app_name)} --num #{lines.to_i}"
    cmd += " --tail" if tail
    run(cmd)
  end

  # ── Datastore Plugins ────────────────────────

  def postgres_create(service_name)
    run("postgres:create #{escape(service_name)}")
  end

  def redis_create(service_name)
    run("redis:create #{escape(service_name)}")
  end

  def mysql_create(service_name)
    run("mysql:create #{escape(service_name)}")
  end

  def mongo_create(service_name)
    run("mongo:create #{escape(service_name)}")
  end

  def postgres_destroy(service_name)
    run("postgres:destroy #{escape(service_name)} --force")
  end

  def redis_destroy(service_name)
    run("redis:destroy #{escape(service_name)} --force")
  end

  def mysql_destroy(service_name)
    run("mysql:destroy #{escape(service_name)} --force")
  end

  def mongo_destroy(service_name)
    run("mongo:destroy #{escape(service_name)} --force")
  end

  def postgres_link(service_name, app_name)
    run("postgres:link #{escape(service_name)} #{escape(app_name)}")
  end

  def redis_link(service_name, app_name)
    run("redis:link #{escape(service_name)} #{escape(app_name)}")
  end

  def mysql_link(service_name, app_name)
    run("mysql:link #{escape(service_name)} #{escape(app_name)}")
  end

  def mongo_link(service_name, app_name)
    run("mongo:link #{escape(service_name)} #{escape(app_name)}")
  end

  def postgres_unlink(service_name, app_name)
    run("postgres:unlink #{escape(service_name)} #{escape(app_name)}")
  end

  def redis_unlink(service_name, app_name)
    run("redis:unlink #{escape(service_name)} #{escape(app_name)}")
  end

  def mysql_unlink(service_name, app_name)
    run("mysql:unlink #{escape(service_name)} #{escape(app_name)}")
  end

  def mongo_unlink(service_name, app_name)
    run("mongo:unlink #{escape(service_name)} #{escape(app_name)}")
  end

  # ── Datastore Info ───────────────────────────

  def postgres_info(service_name)
    parse_datastore_info(run("postgres:info #{escape(service_name)}"), "postgres")
  end

  def redis_info(service_name)
    parse_datastore_info(run("redis:info #{escape(service_name)}"), "redis")
  end

  def mysql_info(service_name)
    parse_datastore_info(run("mysql:info #{escape(service_name)}"), "mysql")
  end

  def mongo_info(service_name)
    parse_datastore_info(run("mongo:info #{escape(service_name)}"), "mongo")
  end

  # ── Datastore Logs ───────────────────────────

  def postgres_logs(service_name, lines: 100)
    run("postgres:logs #{escape(service_name)} --num #{lines.to_i}")
  end

  def redis_logs(service_name, lines: 100)
    run("redis:logs #{escape(service_name)} --num #{lines.to_i}")
  end

  def mysql_logs(service_name, lines: 100)
    run("mysql:logs #{escape(service_name)} --num #{lines.to_i}")
  end

  def mongo_logs(service_name, lines: 100)
    run("mongo:logs #{escape(service_name)} --num #{lines.to_i}")
  end

  # ── Datastore Backup / Restore ───────────────

  def postgres_export(service_name)
    run("postgres:export #{escape(service_name)}")
  end

  def redis_export(service_name)
    run("redis:export #{escape(service_name)}")
  end

  def mysql_export(service_name)
    run("mysql:export #{escape(service_name)}")
  end

  def mongo_export(service_name)
    run("mongo:export #{escape(service_name)}")
  end

  def postgres_import(service_name, data)
    run_with_stdin("postgres:import #{escape(service_name)}", data)
  end

  def redis_import(service_name, data)
    run_with_stdin("redis:import #{escape(service_name)}", data)
  end

  def mysql_import(service_name, data)
    run_with_stdin("mysql:import #{escape(service_name)}", data)
  end

  def mongo_import(service_name, data)
    run_with_stdin("mongo:import #{escape(service_name)}", data)
  end

  # ── Cron ─────────────────────────────────────

  def cron_set(app_name, schedule, command)
    run("cron:set #{escape(app_name)} #{escape(schedule)} #{escape(command)}")
  end

  def cron_clear(app_name)
    run("cron:clear #{escape(app_name)}")
  end

  # ── Metrics / Status ─────────────────────────

  def metrics(app_name)
    run("ps:report #{escape(app_name)}")
  end

  def container_status(app_name)
    run("ps:report #{escape(app_name)} --process-status")
  end

  def app_report(app_name)
    run("apps:report #{escape(app_name)}")
  end

  # Open an interactive PTY shell inside a Dokku app container.
  # Returns a DokkuTerminalSession handle that the caller manages.
  def interactive_shell(app_name, process_type: "web", shell: "/bin/sh", database: false)
    return nil if server.ssh_key.blank?
    DokkuTerminalSession.new(server, app_name, process_type: process_type, shell: shell, database: database)
  end

  private

  def escape(value)
    Shellwords.escape(value.to_s)
  end

  # Build SSH connection options with timeouts and security settings
  def ssh_connection_options
    [
      server.host,
      server.ssh_user || DokkuEngineConstants::SSH_USER,
      {
        key_data: [server.ssh_key],
        non_interactive: true,
        timeout: DokkuEngineConstants::SSH_TIMEOUT,
        verify_host_key: :never,
      }
    ]
  end

  # Parse Dokku datastore plugin info output into structured hash.
  # Expected output format:
  #   =====> <name> postgres service information
  #          Dsn:                 postgres://postgres:pass@host:5432/db
  #          Internal ip:         172.17.0.19
  #          Status:              running
  #          Version:             postgres:15.2
  def parse_datastore_info(result, type)
    return { success: false, error: result[:output] } unless result[:success]

    output = result[:output]
    info = { success: true, type: type }

    output.each_line do |line|
      next unless line.include?(":")
      key, value = line.split(":", 2)
      next unless key && value
      key = key.strip.downcase.gsub(/\s+/, "_").to_sym
      value = value.strip
      info[key] = value
    end

    # Extract connection details from DSN if present
    if info[:dsn]
      uri = begin
        URI.parse(info[:dsn])
      rescue
        nil
      end
      if uri
        info[:username] = uri.user
        info[:password] = uri.password
        info[:host] = uri.host
        info[:port] = uri.port
        info[:database] = uri.path.to_s.sub(%r{^/}, "")
        info[:url] = info[:dsn]
      end
    end

    info
  rescue => e
    { success: false, error: "Failed to parse info: #{e.message}" }
  end
end

# Manages a persistent SSH PTY session for interactive terminal access.
# Created by DokkuEngine#interactive_shell.
class DokkuTerminalSession
  attr_reader :app_name, :process_type

  def initialize(server, app_name, process_type: "web", shell: "/bin/sh", database: false)
    @server = server
    @app_name = app_name
    @process_type = process_type
    @shell = shell
    @database = database
    @ssh = nil
    @channel = nil
    @callbacks = {}
    @closed = false
    @close_called = false
    @mutex = Mutex.new
  end

  def open
    return false if @server.ssh_key.blank?

    opts = {
      key_data: [@server.ssh_key],
      non_interactive: true,
      timeout: DokkuEngineConstants::SSH_TIMEOUT,
      verify_host_key: :never,
    }

    @ssh = Net::SSH.start(@server.host, @server.ssh_user || DokkuEngineConstants::SSH_USER, opts)

    @channel = @ssh.open_channel do |ch|
      ch.request_pty(term: "xterm-256color", chars_wide: 80, chars_high: 24) do |_, success|
        unless success
          @callbacks[:on_error]&.call("PTY allocation failed")
          close
          return
        end

        cmd = if @database
          "#{Shellwords.escape(@process_type)}:enter #{Shellwords.escape(@app_name)} #{Shellwords.escape(@shell)}"
        else
          "enter #{Shellwords.escape(@app_name)} #{Shellwords.escape(@process_type)} #{Shellwords.escape(@shell)}"
        end
        ch.exec(cmd) do |_, exec_success|
          unless exec_success
            @callbacks[:on_error]&.call("Failed to execute shell command")
            close
            return
          end

          @callbacks[:on_open]&.call
        end
      end

      ch.on_data do |_, data|
        @callbacks[:on_data]&.call(data)
      end

      ch.on_extended_data do |_, type, data|
        @callbacks[:on_data]&.call(data)
      end

      ch.on_eof do |ch|
        Rails.logger.debug "[DokkuTerminalSession] on_eof received"
      end

      ch.on_close do |_, data|
        Rails.logger.debug "[DokkuTerminalSession] on_close received"
        close
      end

      ch.on_open_failed do |_, reason, description|
        Rails.logger.error "[DokkuTerminalSession] on_open_failed: #{reason} - #{description}"
        @callbacks[:on_error]&.call("Channel open failed: #{description}")
      end

      # NOTE: Do NOT add ch.on_process { @ssh.process(0) } here.
      # @ssh.loop in the background thread already handles event processing.
      # Adding on_process causes infinite recursion (SystemStackError).
    end

    # Start the SSH event loop in a background thread.
    # Use manual polling instead of @ssh.loop to avoid SystemStackError
    # caused by deep recursion inside Net::SSH's event loop.
    @thread = Thread.new do
      begin
        until @closed
          @ssh.process(0.01)
        end
      rescue => e
        @callbacks[:on_error]&.call("SSH loop error: #{e.message}")
      ensure
        safe_on_close
      end
    end

    true
  rescue Net::SSH::Exception => e
    Rails.logger.error "[DokkuTerminalSession] SSH error during open: #{e.message}"
    false
  rescue => e
    Rails.logger.error "[DokkuTerminalSession] Error during open: #{e.message}"
    false
  end

  def on_data(&block)
    @callbacks[:on_data] = block
  end

  def on_open(&block)
    @callbacks[:on_open] = block
  end

  def on_close(&block)
    @callbacks[:on_close] = block
  end

  def on_error(&block)
    @callbacks[:on_error] = block
  end

  def send_data(data)
    @mutex.synchronize do
      return if @closed || @channel.nil?
      @channel.send_data(data)
    end
  end

  def resize(cols:, rows:)
    @mutex.synchronize do
      return if @closed || @channel.nil?
      @channel.send_channel_request("window-change", :long, cols, :long, rows, :long, 0, :long, 0)
    end
  end

  def close
    @mutex.synchronize do
      return if @closed
      @closed = true

      begin
        @channel&.close
      rescue
        nil
      end

      begin
        @ssh&.close
      rescue
        nil
      end

      begin
        @thread&.kill
      rescue
        nil
      end

      @channel = nil
      @ssh = nil
    end

    safe_on_close
  end

  def closed?
    @closed
  end

  private

  def safe_on_close
    @mutex.synchronize do
      return if @close_called
      @close_called = true
    end
    @callbacks[:on_close]&.call
  end
end

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

    with_ssh_retry do
      output = ""
      exit_code = nil

      execute_on_session do |ssh|
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
    end
  end

  # Run a command piping data to stdin
  def run_with_stdin(command, stdin_data)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    with_ssh_retry do
      output = ""
      exit_code = nil

      execute_on_session do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(command) do |_, success|
            unless success
              return { success: false, output: "Failed to execute command" }
            end

            ch.on_data { |_, data| output += data }
            ch.on_extended_data { |_, type, data| output += data }
            ch.on_request("exit-status") { |_, data| exit_code = data.read_long }

            ch.send_data(stdin_data)
            ch.eof!
          end
        end
        channel.wait
      end

      { success: exit_code == 0, output: output }
    end
  end

  def run_to_file(command, path)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    FileUtils.mkdir_p(File.dirname(path))
    error_output = +""
    exit_code = nil

    with_ssh_retry do
      File.open(path, "wb") do |file|
        execute_on_session do |ssh|
          channel = ssh.open_channel do |ch|
            ch.exec(command) do |_, success|
              return { success: false, output: "Failed to execute command" } unless success

              ch.on_data { |_, data| file.write(data) }
              ch.on_extended_data { |_, _, data| error_output << data }
              ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
            end
          end
          channel.wait
        end
      end
    end

    File.delete(path) if exit_code != 0 && File.exist?(path)
    { success: exit_code == 0, output: error_output }
  end

  def run_with_file(command, path)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    output = +""
    exit_code = nil
    with_ssh_retry do
      File.open(path, "rb") do |file|
        execute_on_session do |ssh|
          channel = ssh.open_channel do |ch|
            ch.exec(command) do |_, success|
              return { success: false, output: "Failed to execute command" } unless success

              ch.on_data { |_, data| output << data }
              ch.on_extended_data { |_, _, data| output << data }
              ch.on_request("exit-status") { |_, data| exit_code = data.read_long }

              chunk = nil
              ch.send_data(chunk) while (chunk = file.read(64.kilobytes))
              ch.eof!
            end
          end
          channel.wait
        end
      end
    end
    { success: exit_code == 0, output: output }
  end

  # Run a command and yield each line of output in real-time
  def run_streaming(command, cancelled: nil)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    with_ssh_retry do
      output = ""
      exit_code = nil

      execute_on_session do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(command) do |_, success|
            unless success
              return { success: false, output: "Failed to execute command" }
            end

            ch.on_data do |_, data|
              output += data
              yield(data) if block_given?
              ch.close if cancelled&.call
            end
            ch.on_extended_data do |_, type, data|
              output += data
              yield(data) if block_given?
              ch.close if cancelled&.call
            end
            ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
          end
        end
        channel.wait
      end

      if exit_code.nil? && cancelled&.call != true
        return {
          success: false,
          output: output,
          error: "Remote build session ended before Dokku reported an exit status. Check host memory, SSH, and Docker daemon logs.",
          cancelled: false
        }
      end

      { success: exit_code == 0, output: output, cancelled: cancelled&.call == true }
    end
  end

  # Open a reusable SSH session for the current thread. All run* calls made
  # inside the block reuse this single connection, eliminating the connection
  # storm that causes sshd rate-limiting during one-click deploys.
  def with_session
    open_session
    yield
  ensure
    close_session
  end

  # ── Server Validation ────────────────────────

  def validate_connection
    dokku_result = run(dokku_version_command)
    if dokku_result[:success]
      dokku_version = dokku_result[:output].match(DokkuEngineConstants::DOKKU_VERSION_REGEX)&.[](1) || "unknown"
    else
      # The dokku user accepts bare commands like "version"; other users need
      # "dokku version". If neither works, Dokku is probably not installed yet.
      fallback_result = run(server.ssh_user.to_s == "dokku" ? "dokku version" : "version")
      if fallback_result[:success]
        dokku_result = fallback_result
        dokku_version = dokku_result[:output].match(DokkuEngineConstants::DOKKU_VERSION_REGEX)&.[](1) || "unknown"
      end
    end

    docker_result = run("docker --version")
    docker_version = docker_result[:output].match(DokkuEngineConstants::DOCKER_VERSION_REGEX)&.[](1) || "unknown"

    unless dokku_result&.dig(:success)
      output = dokku_result&.dig(:output).to_s.presence || "Dokku command failed"
      if docker_result[:success]
        output = "#{output}\nDocker is installed but Dokku was not detected. Run the bootstrap script on the host first."
      end
      return { success: false, output: output.strip, docker_version: docker_version }
    end

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
  end

  # ── App Lifecycle ────────────────────────────

  def dokku_version_command
    # The dokku SSH user is restricted to dokku subcommands, so "version" maps
    # to "dokku version". Other users must invoke the dokku binary explicitly.
    server.ssh_user.to_s == "dokku" ? "version" : "dokku version"
  end

  def app_create(app_name)
    run("apps:create #{escape(app_name)}")
  end

  def app_destroy(app_name)
    run("apps:destroy #{escape(app_name)} --force")
  end

  def builder_set(app_name, builder_type)
    run("builder:set #{escape(app_name)} selected #{escape(builder_type)}")
  end

  def builder_dockerfile_set_path(app_name, path)
    run("builder-dockerfile:set #{escape(app_name)} dockerfile-path #{escape(path)}")
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

  def config_export_json(app_name)
    run("config:export --format json #{escape(app_name)}")
  end

  def config_clear(app_name)
    run("config:clear #{escape(app_name)}")
  end

  # Set many env vars in a single SSH call. Use this to sync the entire
  # desired state from RailDock to Dokku atomically (one rewrite of the
  # ENV file, regardless of how many vars are being set).
  #
  # Multi-line values are auto-detected and encoded with --encoded so
  # the host doesn't choke on embedded newlines or special chars. Empty
  def config_set_many(app_name, env_hash)
    args = env_hash.reject { |_, v| v.nil? || v.to_s.empty? }.map do |k, v|
      str = v.to_s
      if str.include?("\n") || str.length > 4096
        encoded = Base64.strict_encode64(str)
        "--encoded #{escape(k)}=#{shell_quote(encoded)}"
      else
        "#{escape(k)}=#{shell_quote(str)}"
      end
    end

    return { success: true, output: "" } if args.empty?

    cmd = "config:set --no-restart #{escape(app_name)} #{args.join(' ')}"
    run(cmd)
  end

  # Sync the host's env to exactly match the desired state. This is the
  # atomic-replace path: clear first, then set all in one batched call.
  # Dokku's godotenv-based read is lenient on partial corruption (more so
  # than bash), so even a file with tail fragments gets replaced cleanly.
  def config_replace_all(app_name, env_hash)
    normalized = env_hash.reject { |key, _| key.blank? }
    return run("config:clear --no-restart #{escape(app_name)}") if normalized.empty?

    payload = JSON.generate(normalized.transform_values(&:to_s))
    result = run_with_stdin(
      "config:import --replace --no-restart --format json #{escape(app_name)} -",
      payload
    )

    return result if result[:success]

    result.merge(error: "Atomic config import failed")
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
    # Named volumes (not starting with /) must exist before mounting.
    # Dokku storage:create is idempotent — it's safe to call on existing entries.
    if !host_path.start_with?("/")
      storage_create(host_path)
    end

    cmd = "storage:mount #{escape(app_name)} #{escape(host_path)} --container-dir #{escape(container_path)}"
    cmd += " --process-type #{escape(process_type)}" if process_type
    result = run(cmd)

    # Both TemplateDeployJob and DeploymentJob sync storage mounts
    # independently, so a duplicate mount is expected on retry — treat
    # "already mounted" as success rather than failing the deploy.
    if !result[:success] && duplicate_mount_error?(result[:output])
      { success: true, output: "mount already exists" }
    else
      result
    end
  end

  def duplicate_mount_error?(output)
    return false if output.blank?
    output.match?(/is already mounted/i)
  end

  def storage_create(name)
    run("storage:create #{escape(name)}")
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

  def proxy_set_global(proxy_type)
    run("proxy:set --global #{escape(proxy_type)}")
  end

  def proxy_report(app_name)
    run("proxy:report #{escape(app_name)}")
  end

  def nginx_set(app_name, property, value)
    run("nginx:set #{escape(app_name)} #{escape(property)} #{escape(value)}")
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

  def ports_set(app_name, *mappings)
    # Bulk-friendly wrapper. Accepts one or more "scheme:host-port:container-port"
    # strings, or a single array of them. Calling ports:set repeatedly with one
    # mapping at a time overwrites previous mappings, so callers should always
    # pass both http and https mappings in one call.
    flattened = mappings.flatten
    return { success: true, output: "" } if flattened.empty?

    run("ports:set #{escape(app_name)} #{flattened.map { |m| escape(m.to_s) }.join(" ")}")
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

  def checks_set(app_name, property, value)
    run("checks:set #{escape(app_name)} #{escape(property)} #{escape(value.to_s)}")
  end

  # ── Docker Options ───────────────────────────

  def docker_option_add(app_name, phase, option, process: nil)
    process_arg = process.present? ? "--process #{escape(process)} " : ""
    run("docker-options:add #{process_arg}#{escape(app_name)} #{escape(phase)} #{escape(option)}")
  end

  def docker_option_remove(app_name, phase, option, process: nil)
    process_arg = process.present? ? "--process #{escape(process)} " : ""
    run("docker-options:remove #{process_arg}#{escape(app_name)} #{escape(phase)} #{escape(option)}")
  end

  # ── Resource Limits ──────────────────────────
  # Dokku resource commands require --process-type flag before the process type value
  def resource_limit(app_name, process_type, memory: nil, cpu: nil, nvidia_gpu: nil)
    args = [ "--process-type #{escape(process_type)}" ]
    args << "--memory #{escape(memory)}" if memory
    args << "--cpu #{escape(cpu)}" if cpu
    args << "--nvidia-gpu #{nvidia_gpu.to_i}" if nvidia_gpu
    run("resource:limit #{escape(app_name)} #{args.join(" ")}")
  end

  def resource_reserve(app_name, process_type, memory: nil, cpu: nil)
    args = [ "--process-type #{escape(process_type)}" ]
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
  #
  # Phase 1 dispatches through the PluginRegistry instead of hard-coding
  # per-subtype commands. Legacy per-subtype methods are kept as thin
  # wrappers for callers that have not been migrated yet.

  # Generic dispatch: create
  def datastore_create(service)
    run_subtype_command(service, :create)
  end

  # Generic dispatch: destroy
  def datastore_destroy(service)
    run_subtype_command(service, :destroy, "--force")
  end

  # Generic dispatch: link to an app
  def datastore_link(service, app_name)
    run_subtype_command(service, :link, escape(app_name))
  end

  # Generic dispatch: unlink from an app
  def datastore_unlink(service, app_name)
    run_subtype_command(service, :unlink, escape(app_name))
  end

  # Generic dispatch: info
  def datastore_info(service)
    st = PluginRegistry.find_subtype(service.subtype)
    return unsupported_subtype(service.subtype) unless st&.has_capability?(:info)

    parse_datastore_info(run("#{st.dokku_command(:info)} #{escape(service.dokku_app_name)}"), service.subtype)
  end

  # Generic dispatch: logs
  def datastore_logs(service, lines: 100)
    # Datastore plugins do not support --num. Without --tail the command
    # prints recent logs and exits, which is what the REST endpoint needs.
    run_subtype_command(service, :logs)
  end

  # Generic dispatch: export to stdout
  def datastore_export(service)
    run_subtype_command(service, :export)
  end

  # Generic dispatch: export to file
  def datastore_export_to(service, path)
    st = PluginRegistry.find_subtype(service.subtype)
    return unsupported_subtype(service.subtype) unless st&.has_capability?(:backup)

    run_to_file("#{st.dokku_command(:export)} #{escape(service.dokku_app_name)}", path)
  end

  # Generic dispatch: import from file
  def datastore_import_from(service, path)
    st = PluginRegistry.find_subtype(service.subtype)
    return unsupported_subtype(service.subtype) unless st&.has_capability?(:restore)

    run_with_file("#{st.dokku_command(:import)} #{escape(service.dokku_app_name)}", path)
  end

  # Generic dispatch: import from stdin
  def datastore_import_stdin(service, data)
    st = PluginRegistry.find_subtype(service.subtype)
    return unsupported_subtype(service.subtype) unless st&.has_capability?(:restore)

    run_with_stdin("#{st.dokku_command(:import)} #{escape(service.dokku_app_name)}", data)
  end

  # Legacy per-subtype helpers for callers that pass a name instead of a Service.
  %w[postgres redis mysql mongo mariadb].each do |subtype|
    define_method("#{subtype}_create") { |service_name| run_legacy_command(subtype, :create, service_name) }
    define_method("#{subtype}_destroy") { |service_name| run_legacy_command(subtype, :destroy, service_name, "--force") }
    define_method("#{subtype}_link") { |service_name, app_name| run_legacy_command(subtype, :link, service_name, escape(app_name)) }
    define_method("#{subtype}_unlink") { |service_name, app_name| run_legacy_command(subtype, :unlink, service_name, escape(app_name)) }
    define_method("#{subtype}_info") { |service_name| legacy_info(subtype, service_name) }
    define_method("#{subtype}_logs") { |service_name, lines: 100| run_legacy_command(subtype, :logs, service_name) }
    define_method("#{subtype}_export") { |service_name| run_legacy_command(subtype, :export, service_name) }
    define_method("#{subtype}_import") { |service_name, data| run_legacy_stdin_import(subtype, service_name, data) }
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
    run("ps:report #{escape(app_name)} --running")
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

  # Shell-escape a value. Exposed so callers that build raw Dokku command
  # strings can reuse the same escaping logic as the engine.
  def escape(value)
    Shellwords.escape(value.to_s)
  end

  # Quote a value for inclusion in a shell command. Plain alphanumeric and
  # common safe punctuation passes through unchanged; anything else gets
  # single- or double-quoted. Public so config_set_many can call it from
  # inside a block (private methods aren't visible across block bindings).
  def shell_quote(value)
    return "''" if value.empty?
    return value if value.match?(/\A[A-Za-z0-9_\-\.\/=:@\+]+\z/) && !value.start_with?("=")

    if value.include?("'")
      %("#{value.gsub("\\\\", "\\\\\\\\").gsub("\"", "\\\\\"").gsub("\n", "\\\\n").gsub("\r", "\\\\r")}")
    else
      "'#{value}'"
    end
  end

  private

  # --- Plugin registry helpers -------------------

  def run_subtype_command(service, action, *args)
    st = PluginRegistry.find_subtype(service.subtype)
    return unsupported_subtype(service.subtype) unless st&.has_capability?(action)

    command = [ st.dokku_command(action), escape(service.dokku_app_name), *args ].compact.join(" ")
    run(command)
  end

  def run_legacy_command(subtype, action, service_name, *args)
    st = PluginRegistry.find_subtype(subtype)
    return unsupported_subtype(subtype) unless st&.has_capability?(action)

    command = [ st.dokku_command(action), escape(service_name), *args ].compact.join(" ")
    run(command)
  end

  def legacy_info(subtype, service_name)
    st = PluginRegistry.find_subtype(subtype)
    return unsupported_subtype(subtype) unless st&.has_capability?(:info)

    parse_datastore_info(run("#{st.dokku_command(:info)} #{escape(service_name)}"), subtype)
  end

  def run_legacy_stdin_import(subtype, service_name, data)
    st = PluginRegistry.find_subtype(subtype)
    return unsupported_subtype(subtype) unless st&.has_capability?(:restore)

    run_with_stdin("#{st.dokku_command(:import)} #{escape(service_name)}", data)
  end

  def unsupported_subtype(subtype)
    { success: false, output: "Unsupported service subtype: #{subtype}" }
  end

  # Retry transient SSH failures. dokku commands are idempotent where it matters,
  # and bursts of connections during one-click deploys can hit sshd rate limits
  # or idle-timeouts on long, quiet builds.
  def with_ssh_retry(max_retries: 3)
    retries = 0
    begin
      yield
    rescue Net::SSH::AuthenticationFailed, Net::SSH::ChannelOpenFailed => e
      # These are not recoverable with a simple retry.
      { success: false, output: "SSH error: #{e.message}" }
    rescue Net::SSH::ConnectionTimeout => e
      if retries < max_retries
        retries += 1
        close_session
        sleep(retries * 2)
        retry
      end
      { success: false, output: "SSH connection timed out" }
    rescue Net::SSH::Exception, Errno::ECONNRESET, Errno::EPIPE, IOError => e
      if retries < max_retries
        retries += 1
        Rails.logger.warn "SSH transient error (#{retries}/#{max_retries}): #{e.message}"
        close_session
        sleep(retries * 2)
        retry
      end
      { success: false, output: "SSH error: #{e.message}" }
    rescue => e
      { success: false, output: "SSH error: #{e.message}" }
    end
  end

  # Run the given block on an SSH session, reusing the thread-local session
  # when one has been opened via #with_session. Otherwise opens a one-off
  # session and closes it immediately after the command finishes.
  def execute_on_session
    session = current_session
    owns_session = session.nil?

    if owns_session
      session = Net::SSH.start(*ssh_connection_options)
      ssh_connection_builder.capture_host_key!(session)
    end

    yield session
  ensure
    session.close if owns_session && session && !session.closed?
    ssh_connection_builder.cleanup if owns_session
  end

  def open_session
    close_session
    retries = 0
    begin
      session = Net::SSH.start(*ssh_connection_options)
      ssh_connection_builder.capture_host_key!(session)
      Thread.current[:dokku_engine_session] = session
    rescue Net::SSH::Exception, Errno::ECONNRESET, Errno::EPIPE, IOError => e
      retries += 1
      raise if retries > 3
      Rails.logger.warn "Dokku SSH transient error during session open (#{retries}/3): #{e.message}"
      sleep(retries * 2)
      retry
    end
  end

  def close_session
    session = Thread.current[:dokku_engine_session]
    return unless session

    begin
      session.close unless session.closed?
    rescue => e
      Rails.logger.warn "Failed to close DokkuEngine SSH session: #{e.message}"
    end
    Thread.current[:dokku_engine_session] = nil
  end

  def current_session
    session = Thread.current[:dokku_engine_session]
    return nil unless session
    return session unless session.closed?

    Thread.current[:dokku_engine_session] = nil
    nil
  end

  # Build SSH connection options with timeouts and security settings
  def ssh_connection_options
    builder = ssh_connection_builder
    [ server.host, server.ssh_user || DokkuEngineConstants::SSH_USER, builder.options ]
  end

  def ssh_connection_builder
    @ssh_connection_builder ||= SshConnectionBuilder.new(server, user: server.ssh_user || DokkuEngineConstants::SSH_USER)
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
    @opened = false
    @opened_at = nil
    @exit_status = nil
    @error_buffer = +""
    @data_buffer = +""
    @mutex = Mutex.new
  end

  attr_reader :shell

  def open
    return false if @server.ssh_key.blank?

    opts = {
      key_data: [ @server.ssh_key ],
      non_interactive: true,
      timeout: DokkuEngineConstants::SSH_TIMEOUT,
      verify_host_key: :never
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

          @opened = true
          @opened_at = Time.now
          @callbacks[:on_open]&.call
        end
      end

      ch.on_data do |_, data|
        @data_buffer << data
        @callbacks[:on_data]&.call(data)
      end

      ch.on_extended_data do |_, type, data|
        @error_buffer << data
        @callbacks[:on_data]&.call(data)
      end

      ch.on_request("exit-status") do |_, data|
        @exit_status = data.read_long
        Rails.logger.debug "[DokkuTerminalSession] exit-status=#{@exit_status}"
      end

      ch.on_eof do |ch|
        Rails.logger.debug "[DokkuTerminalSession] on_eof received"
      end

      ch.on_close do |_, data|
        Rails.logger.debug "[DokkuTerminalSession] on_close received exit=#{@exit_status.inspect} opened=#{@opened}"
        report_pre_open_failure
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
    report_pre_open_failure
    @callbacks[:on_close]&.call
  end

  # When the SSH channel closes before the interactive shell reaches
  # on_open, the user only sees a generic "closed" message and an
  # endlessly-spinning terminal. Surface the actual Dokku/OCI failure
  # so the UI can explain what went wrong and offer a safe fallback.
  #
  # The @opened flag tracks whether the dokku exec request itself was
  # accepted; the OCI "no such file" failure happens *after* exec
  # succeeds, when docker tries to start the requested shell inside
  # the container. So we also classify stderr when the session closes
  # quickly (e.g. within 2s) and never produced a real shell prompt.
  def report_pre_open_failure
    return if @pre_open_error_reported

    if @opened
      # The exec request was accepted but the inner container shell
      # died before any real interactivity happened. Only treat as a
      # pre-open failure if the buffer clearly indicates a startup
      # problem (OCI / missing file / command not found / non-zero
      # exit before the session lived long enough to be useful).
      return unless quick_close_with_startup_error?
    end

    message = classify_pre_open_failure
    return if message.nil?

    @pre_open_error_reported = true
    Rails.logger.warn "[DokkuTerminalSession] pre-open failure for shell=#{@shell}: #{message}"
    @callbacks[:on_error]&.call(message)
  end

  def quick_close_with_startup_error?
    return false if @opened_at.nil?
    elapsed = Time.now - @opened_at
    return false if elapsed > 2.0

    combined = "#{@error_buffer}#{@data_buffer}"
    combined.match?(/OCI runtime exec failed/i) ||
      combined.match?(/no such file or directory/i) ||
      combined.match?(/command not found/i) ||
      combined.match?(/does not exist/i) ||
      combined.match?(/has not been deployed/i) ||
      @exit_status == 127
  end

  def classify_pre_open_failure
    buf = "#{@error_buffer}#{@data_buffer}"
    status = @exit_status

    missing_shell_match = buf.match(/exec:\s*("?)([^\s":]+)\1:\s*stat\s+([^\s:]+):\s*no such file or directory/)
    oci_exec_match = buf.match(/OCI runtime exec failed/i)
    command_not_found = buf.match(/([\w\/-]+):\s*(?:line\s+\d+:\s*)?(command not found|Permission denied)/)

    if missing_shell_match || (status == 127 && oci_exec_match) || (status == 127 && missing_shell_match)
      target = missing_shell_match ? missing_shell_match[2] : @shell
      "Shell #{target} is not available in this container. Try /bin/sh or /bin/bash instead."
    elsif status == 126 || (status && status >= 126) && command_not_found
      "Selected shell failed to start (#{command_not_found[2]}). Try /bin/sh instead."
    elsif buf.match?(/connection (refused|reset|closed)/i)
      "SSH connection lost while opening the shell. Check the server status and retry."
    elsif (m = buf.match(/^ ! \s+(.*service\s+\S+.*(?:does not exist|has not been deployed))/i))
      "Dokku reports: #{m[1].strip}"
    elsif (m = buf.match(/^ ! \s+App\s+(\S+)\s+has not been deployed/))
      "App #{m[1]} has not been deployed yet. Deploy it from the Deploy tab first."
    elsif status && status != 0
      "Shell exited with status #{status} before becoming interactive. Try /bin/sh instead."
    end
  end
end

require "net/ssh"
require "shellwords"

# Runs raw shell/Docker commands on the host server as root.
# Unlike DokkuEngine (which connects as the restricted dokku user),
# HostEngine connects as root and can run docker, iptables, etc.
class HostEngine
  SSH_TIMEOUT = 30
  SSH_CONNECTION_TIMEOUT = 10
  SSH_USER = "root"

  attr_reader :server

  def initialize(server)
    @server = server
  end

  # Run a command on the host as root.
  # Returns { success: bool, output: string }
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

            ch.on_data { |_, data| output += coerce_output(data) }
            ch.on_extended_data { |_, type, data| output += coerce_output(data) }
            ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
          end
        end
        channel.wait
      end

      { success: exit_code == 0, output: output }
    end
  end

  def run_to_file(command, path)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    exit_code = nil
    error_output = +""
    File.open(path, "wb", 0o600) do |file|
      execute_on_session do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(command) do |_, success|
            return { success: false, output: "Failed to execute command" } unless success

            ch.on_data { |_, data| file.write(data) }
            ch.on_extended_data { |_, _, data| error_output << coerce_output(data) }
            ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
          end
        end
        channel.wait
      end
    end
    { success: exit_code == 0, output: error_output }
  rescue => error
    File.delete(path) if File.exist?(path)
    { success: false, output: "SSH error: #{error.message}" }
  end

  def run_with_file(command, path)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    exit_code = nil
    output = +""
    File.open(path, "rb") do |file|
      execute_on_session do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(command) do |_, success|
            return { success: false, output: "Failed to execute command" } unless success

            ch.send_data(chunk) while (chunk = file.read(64.kilobytes))
            ch.eof!
            ch.on_data { |_, data| output << coerce_output(data) }
            ch.on_extended_data { |_, _, data| output << coerce_output(data) }
            ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
          end
        end
        channel.wait
      end
    end
    { success: exit_code == 0, output: output }
  rescue => error
    { success: false, output: "SSH error: #{error.message}" }
  end

  # Run a command on the host as root, yielding each output chunk as it arrives.
  def run_streaming(command, cancelled: nil)
    return { success: false, output: "No SSH key configured" } if server.ssh_key.blank?

    with_ssh_retry do
      output = +""
      exit_code = nil

      execute_on_session do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(command) do |_, success|
            unless success
              return { success: false, output: "Failed to execute command" }
            end

            ch.on_data do |_, data|
              coerced = coerce_output(data)
              output << coerced
              yield(coerced) if block_given?
              ch.close if cancelled&.call
            end
            ch.on_extended_data do |_, _, data|
              coerced = coerce_output(data)
              output << coerced
              yield(coerced) if block_given?
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
          error: "Remote build session ended before the command reported an exit status.",
          cancelled: false
        }
      end

      { success: exit_code == 0, output: output, cancelled: cancelled&.call == true }
    end
  end

  def volume_export_to(host_path, path)
    source = Shellwords.escape(host_path)
    command = if host_path.start_with?("/")
      "tar -C #{source} -czf - ."
    else
      "docker run --rm -v #{source}:/source:ro alpine:3.20 tar -C /source -czf - ."
    end
    run_to_file(command, path)
  end

  def volume_import_from(host_path, path)
    source = Shellwords.escape(host_path)
    command = if host_path.start_with?("/")
      "mkdir -p #{source} && find #{source} -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C #{source} -xzf -"
    else
      restore = Shellwords.escape("find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf -")
      "docker volume create #{source} >/dev/null && docker run --rm -i -v #{source}:/target alpine:3.20 sh -c #{restore}"
    end
    run_with_file(command, path)
  end

  # List the contents of a directory inside a host path or named Docker volume.
  # Returns { success: bool, entries: [{ type: 'file'|'directory'|'other', name: string, size: integer? }] }
  def volume_list_directory(host_path, relative_path = "/")
    target = File.join(host_path, relative_path).gsub("//", "/")
    source = Shellwords.escape(target)

    command = if host_path.start_with?("/")
      "find #{source} -mindepth 1 -maxdepth 1 -printf '%y\\t%s\\t%f\\n' 2>/dev/null"
    else
      docker_path = Shellwords.escape(File.join("/volume", relative_path).gsub("//", "/"))
      "docker run --rm -v #{Shellwords.escape(host_path)}:/volume alpine:3.20 find #{docker_path} -mindepth 1 -maxdepth 1 -printf '%y\\t%s\\t%f\\n' 2>/dev/null"
    end

    result = run(command)
    return result unless result[:success]

    entries = result[:output].split("\n").filter_map do |line|
      parts = line.split("\t", 3)
      next if parts.length < 3

      type = case parts[0]
      when "d" then "directory"
      when "f" then "file"
      else "other"
      end

      { type: type, name: parts[2], size: parts[1].to_i }
    end

    { success: true, entries: entries }
  end

  # Open a reusable SSH session for the current thread. All run calls made
  # inside the block reuse this single connection, eliminating the connection
  # storm that causes sshd to drop connections during template deploys.
  def with_session
    open_session
    yield
  ensure
    close_session
  end

  # ── Docker helpers ──────────────────────────

  def docker_network_create(name, driver: "bridge")
    run("docker network create #{name} --driver #{driver} 2>/dev/null || true")
  end

  def docker_network_connect(container, network, aliases: [])
    alias_flags = aliases.map { |a| "--alias #{Shellwords.escape(a)}" }.join(" ")
    run("docker network connect #{alias_flags} #{Shellwords.escape(network)} #{Shellwords.escape(container)} 2>/dev/null || true")
  end

  def docker_network_disconnect(container, network)
    run("docker network disconnect #{Shellwords.escape(network)} #{Shellwords.escape(container)} 2>/dev/null || true")
  end

  def docker_network_inspect(network)
    run("docker network inspect #{Shellwords.escape(network)} --format '{{json .Containers}}'")
  end

  def docker_network_inventory
    run("docker network inspect $(docker network ls -q) --format '{{json .}}'")
  end

  def docker_container_inventory
    run("docker ps --format '{{json .}}'")
  end

  def docker_inspect(container, format: nil)
    fmt = format ? "--format='#{format}' " : ""
    run("docker inspect #{fmt}#{Shellwords.escape(container)}")
  end

  # Live resource usage for a container via `docker stats --no-stream`.
  # Returns parsed cpu/mem numbers or nil when the container doesn't
  # exist / stats cannot be read. One SSH round-trip.
  #
  # Uses a tab-separated output (no braces/quotes) to avoid shell-escaping
  # the Go template on the remote host:
  #   CPUPerc  MemUsage
  #   52.54%   696.4MiB / 5GiB
  def docker_stats(container)
    result = run(
      "docker stats --no-stream --format " \
      "'{{.CPUPerc}}\t{{.MemUsage}}' " \
      "#{Shellwords.escape(container)}"
    )
    return nil unless result[:success]

    cpu_str, mem_usage = result[:output].to_s.split("\t", 2)
    return nil if cpu_str.blank? || mem_usage.blank?

    cpu = cpu_str.to_s.delete("%").to_f
    used_str, limit_str = mem_usage.split("/", 2).map(&:strip)
    return { cpu: cpu, memory: nil } if used_str.blank? || limit_str.blank?

    used = human_size_to_bytes(used_str)
    limit = human_size_to_bytes(limit_str)
    memory = limit.positive? ? (used * 100.0 / limit).round(1) : nil
    { cpu: cpu, memory: memory, memory_used: used, memory_limit: limit }
  end

  private

  def human_size_to_bytes(size)
    match = size.to_s.match(/([\d.]+)\s*([KMGT]i?B)/i)
    return 0 unless match

    value = match[1].to_f
    multiplier = { "K" => 1024, "M" => 1024**2, "G" => 1024**3, "T" => 1024**4 }
    value * (multiplier[match[2][0].upcase] || 1)
  end

  def builder_capabilities
    result = run(<<~SH.squish)
      for builder in nixpacks railpack pack; do
        if command -v "$builder" >/dev/null 2>&1; then echo "$builder=available"; else echo "$builder=missing"; fi
      done;
      if docker inspect -f '{{.State.Running}}' buildkit 2>/dev/null | grep -q true; then echo 'buildkit=available'; else echo 'buildkit=missing'; fi
    SH
    return {} unless result[:success]

    result[:output].lines.to_h do |line|
      name, status = line.strip.split("=", 2)
      [ name, status == "available" ]
    end
  end

  def builder_available?(builder)
    capabilities = builder_capabilities
    case builder.to_s
    when "nixpacks" then capabilities["nixpacks"] == true
    when "pack" then capabilities["pack"] == true
    when "railpack" then capabilities["railpack"] == true && capabilities["buildkit"] == true
    else true
    end
  end

  # Wait for a container to be running and return its name
  # Returns the container name if found, nil if not found after timeout
  def wait_for_container(app_name, timeout: 60)
    start_time = Time.now
    while Time.now - start_time < timeout
      result = run("docker ps --format '{{.Names}}'")
      if result[:success]
        containers = result[:output].strip.split("\n")
        exact = "#{app_name}.web.1"
        return exact if containers.include?(exact)

        datastore_container_prefixes.each do |prefix|
          exact = "#{prefix}#{app_name}"
          return exact if containers.include?(exact)
        end
      end
      sleep 1
    end
    nil
  end

  # Check if a container is running
  def container_running?(container_name)
    return false if container_name.blank?
    result = run("docker inspect -f '{{.State.Running}}' #{Shellwords.escape(container_name)} 2>/dev/null")
    result[:output]&.strip == "true"
  end

  # Remove exited containers for a given app. Dokku's scheduler-docker-local
  # stops retired containers but never `docker rm`s them, so on a flaky deploy
  # they pile up as `.upcoming-<rand>` Exited containers and the host's Docker
  # DNS keeps resolving them. If a load balancer (Traefik, nginx) round-robins
  # by container name, traffic can land on the dead ones.
  #
  # We only target this app's containers (by name prefix), and only Exited /
  # Created / Dead states — never Running or Restarting.
  def prune_exited_containers_for_app(app_name, prefix: nil)
    name_filter = "#{Shellwords.escape(app_name)}.#{Shellwords.escape(prefix)}" if prefix.present?
    name_filter ||= Shellwords.escape(app_name)
    result = run(
      "docker ps -a --filter name=#{name_filter} " \
      "--filter status=exited --filter status=created --filter status=dead " \
      "--format '{{.ID}}'"
    )
    return { success: true, removed: 0 } unless result[:success]

    ids = result[:output].to_s.strip.split("\n").reject(&:blank?)
    return { success: true, removed: 0 } if ids.empty?

    rm_result = run("docker rm #{ids.join(' ')}")
    { success: rm_result[:success], removed: ids.length, output: rm_result[:output] }
  end

  # Kill stale ".upcoming-<rand>" containers that have been running longer than
  # the threshold. These are leftover from failed deploys where the post-deploy
  # rename step never ran. They consume memory/cpu but serve no traffic —
  # Traefik routes to the primary container (e.g. web.1), not the upcoming one.
  def prune_stale_upcoming_containers(older_than: 1.hour, dry_run: false)
    cutoff_timestamp = (Time.now - older_than).to_i
    result = run(
      "docker ps --filter name=.upcoming- " \
      "--filter status=running " \
      "--filter until=#{cutoff_timestamp} " \
      "--format '{{.ID}}'"
    )
    return { success: true, removed: 0 } unless result[:success]

    ids = result[:output].to_s.strip.split("\n").reject(&:blank?)
    return { success: true, removed: 0 } if ids.empty?
    return { success: true, removed: ids.length } if dry_run

    rm_result = run("docker stop #{ids.join(' ')} && docker rm #{ids.join(' ')}")
    { success: rm_result[:success], removed: ids.length, output: rm_result[:output] }
  rescue => e
    Rails.logger.warn "Stale upcoming container prune failed: #{e.message}"
    { success: false, removed: 0, output: e.message }
  end

  # ── Dokku container helpers ─────────────────
  public

  # Dokku web containers are named <app>.web.1
  # Dokku plugin containers are named dokku.<plugin>.<app>
  def dokku_container_name(app_name)
    # Get all running containers and find exact match
    result = run("docker ps --format '{{.Names}}'")
    return nil unless result[:success]

    containers = result[:output].strip.split("\n")

    # Try exact match for regular app container first
    exact = "#{app_name}.web.1"
    return exact if containers.include?(exact)

    # Try plugin service containers
    datastore_container_prefixes.each do |prefix|
      exact = "#{prefix}#{app_name}"
      return exact if containers.include?(exact)
    end

    nil
  end

  private

  def datastore_container_prefixes
    ServiceSubtype.where.not(dokku_plugin: nil).distinct.pluck(:dokku_plugin).map { |plugin| "dokku.#{plugin}." }
  end

  # Retry transient SSH failures. Host commands (docker ps, network connect, etc.)
  # are idempotent and can fail when dokku commands are hammering sshd in parallel.
  def with_ssh_retry(max_retries: 3)
    retries = 0
    begin
      yield
    rescue Net::SSH::AuthenticationFailed, Net::SSH::ChannelOpenFailed => e
      { success: false, output: "SSH error: #{e.message}" }
    rescue Net::SSH::ConnectionTimeout
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
        Rails.logger.warn "Host SSH transient error (#{retries}/#{max_retries}): #{e.message}"
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
      session = Net::SSH.start(server.public_ip || server.host, SSH_USER, ssh_connection_options)
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
      session = Net::SSH.start(server.public_ip || server.host, SSH_USER, ssh_connection_options)
      ssh_connection_builder.capture_host_key!(session)
      Thread.current[:host_engine_session] = session
    rescue Net::SSH::Exception, Errno::ECONNRESET, Errno::EPIPE, IOError => e
      retries += 1
      raise if retries > 3
      Rails.logger.warn "Host SSH transient error during session open (#{retries}/3): #{e.message}"
      sleep(retries * 2)
      retry
    end
  end

  def ssh_connection_options
    ssh_connection_builder.options
  end

  def ssh_connection_builder
    @ssh_connection_builder ||= SshConnectionBuilder.new(server, user: SSH_USER)
  end

  def close_session
    session = Thread.current[:host_engine_session]
    return unless session

    begin
      session.close unless session.closed?
    rescue => e
      Rails.logger.warn "Failed to close HostEngine SSH session: #{e.message}"
    end
    Thread.current[:host_engine_session] = nil
  end

  # Net::SSH returns output as BINARY. Coerce it to UTF-8 before appending to
  # in-memory strings so Ruby never raises "incompatible character encodings".
  def coerce_output(data)
    data.to_s.dup.force_encoding("UTF-8").scrub
  end

  def current_session
    session = Thread.current[:host_engine_session]
    return nil unless session
    return session unless session.closed?

    Thread.current[:host_engine_session] = nil
    nil
  end
end

require "base64"
require "shellwords"
require "yaml"

class HttpTrafficSetup
  class Error < StandardError; end

  def initialize(server)
    @server = server
    @engine = HostEngine.new(server)
  end

  def discover
    candidates = remote("discover")
    { candidates: candidates.map do |candidate|
      safe = candidate.slice("container", "image", "path", "can_manage", "reason")
      if candidate["can_manage"]
        safe["review_token"] = verifier.generate({ "server_id" => @server.id, "container_id" => candidate["container_id"], "digest" => candidate["digest"] }, expires_in: 15.minutes)
      end
      safe
    end }
  end

  def verify!(token)
    plan = verifier.verified(token)
    raise Error, "Setup review expired. Detect the proxy again." unless plan && plan["server_id"] == @server.id
    plan
  end

  def apply(token)
    reviewed = verify!(token)
    candidate = remote("discover").find { |item| item["container_id"] == reviewed["container_id"] && item["digest"] == reviewed["digest"] && item["can_manage"] }
    raise Error, "Proxy configuration changed. Detect and review it again." unless candidate
    document = YAML.safe_load(Base64.strict_decode64(candidate.fetch("compose_b64")), aliases: true)
    service = document.fetch("services").fetch(candidate.fetch("service"))
    command = service["command"]
    raise Error, "Automatic setup requires a list of Traefik command arguments." unless command.is_a?(Array) && command.all? { |arg| arg.is_a?(String) }
    raise Error, "A static config file requires advanced setup." if command.any? { |arg| arg.downcase.start_with?("--configfile") }
    name = candidate.fetch("container")
    raise Error, "Unsupported proxy container name." unless name.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,100}\z/)
    directory = "/var/log/raildock-http/#{name}"
    # Preserve every non-access-log flag, service, network, router and certificate setting.
    service["command"] = command.reject { |arg| arg.downcase.match?(/\A--accesslog(?:\.|=|\z)/) } + [
      "--accesslog=true", "--accesslog.format=json", "--accesslog.filepath=#{directory}/access.log",
      "--accesslog.bufferingsize=100", "--accesslog.fields.defaultmode=drop", "--accesslog.fields.headers.defaultmode=drop",
      *%w[StartUTC RequestHost DownstreamStatus DownstreamContentSize Duration].map { |field| "--accesslog.fields.names.#{field}=keep" }
    ]
    volumes = service["volumes"] ||= []
    raise Error, "Unsupported proxy volumes." unless volumes.is_a?(Array)
    volumes << "#{directory}:#{directory}" unless volumes.include?("#{directory}:#{directory}")
    candidate["compose_b64"] = Base64.strict_encode64(YAML.dump(document))
    remote("apply", candidate)
  rescue Psych::Exception, KeyError, ArgumentError
    raise Error, "Unsupported Compose configuration. Use advanced setup."
  end

  def refresh_status
    operation = @server.traffic_settings["setup_operation"]
    return unless operation.to_s.match?(/\A[0-9a-f]{24}\z/)
    result = @engine.run("test ! -f /var/lib/dokku/raildock-http/operation-#{operation}/result.json || cat /var/lib/dokku/raildock-http/operation-#{operation}/result.json")
    return unless result[:success] && result[:output].present?
    data = JSON.parse(result[:output])
    complete(data) if data["state"] == "completed"
    if data["state"] == "failed"
      @server.with_lock { @server.update!(traffic_settings: @server.traffic_settings.merge("setup_state" => "failed", "setup_error" => data["error"])) }
    end
  rescue JSON::ParserError
    nil
  end

  def complete(result)
    @server.with_lock do
      return if @server.traffic_settings["setup_state"] == "completed"
      @server.update!(traffic_settings: @server.traffic_settings.merge("enabled" => true, "path" => result.fetch("path"), "format" => "traefik", "retention_days" => @server.traffic_settings.fetch("retention_days", 7), "capture_paths" => false, "setup_state" => "completed", "setup_error" => nil, "managed_logging" => true), traffic_cursor: {})
    end
  end

  private

  def verifier
    Rails.application.message_verifier("http-traffic-setup")
  end

  def remote(action, plan = nil)
    script = Base64.strict_encode64(File.binread(Rails.root.join("lib/raildock/http_setup.py")))
    if plan
      operation = SecureRandom.hex(12)
      path = "/var/lib/dokku/raildock-http/operation-#{operation}"
      @server.with_lock { @server.update!(traffic_settings: @server.traffic_settings.merge("setup_operation" => operation)) }
      payload = Base64.strict_encode64(plan.to_json)
      writer = "import os,base64; p='#{path}'; os.makedirs(p,mode=0o700); open(p+'/setup.py','wb').write(base64.b64decode('#{script}')); open(p+'/plan.json','wb').write(base64.b64decode('#{payload}'))"
      written = @engine.run("umask 077; python3 -c #{Shellwords.escape(writer)}")
      raise Error, "Could not stage proxy setup on the host." unless written[:success]
      # The host owns the operation if the SSH connection or RailDock process exits.
      command = "systemd-run --quiet --wait --pipe --collect --unit=raildock-http-#{operation} --property=RuntimeMaxSec=360 --property=TimeoutStopSec=120 --property=KillMode=mixed python3 #{path}/setup.py apply-file #{path}/plan.json"
    else
      command = "python3 -c #{Shellwords.escape("import base64;exec(base64.b64decode('#{script}'))")} #{action}"
    end
    result = @engine.run(command)
    data = JSON.parse(result[:output]) rescue nil
    raise Error, data.is_a?(Hash) && data["error"].present? ? data["error"] : "Cannot inspect or configure the proxy. Check SSH, Docker and Python 3." unless result[:success] && data && !(data.is_a?(Hash) && data["error"])
    data
  end
end

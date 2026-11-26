require "shellwords"

# Reads a bounded, redacted log tail from the proxy. Managed Traefik uses
# Dokku's plugin command; external Traefik is read through Docker and remains
# outside RailDock's lifecycle.
class TraefikLogs
  MAX_LINES = 500
  MAX_OUTPUT = 120_000

  def initialize(server, host_engine: nil, engine: nil)
    @server = server
    @host_engine = host_engine || HostEngine.new(server)
    @engine = engine || DokkuEngine.new(server)
  end

  def call(lines: 200, container: nil)
    count = [ [ lines.to_i, 20 ].max, MAX_LINES ].min
    selected = nil

    if server.external_proxy?
      containers = TraefikOverview.new(server, host_engine: host_engine, engine: engine).proxy_containers
      selected = containers.find { |candidate| candidate[:name] == container.presence } ||
                 containers.find { |candidate| candidate[:running] } ||
                 containers.first
      return { success: false, error: "No Traefik container was found on this host" } unless selected

      result = host_engine.run("docker logs --tail #{count} #{Shellwords.escape(selected[:name])} 2>&1")
    else
      result = engine.traefik_logs(num: count)
    end

    unless result[:success]
      return { success: false, error: "Could not read Traefik logs", output: LogRedactor.redact(result[:output].to_s).last(MAX_OUTPUT) }
    end

    {
      success: true,
      output: LogRedactor.redact(result[:output].to_s).last(MAX_OUTPUT),
      container: selected&.dig(:name),
      lines: count
    }
  end

  private

  attr_reader :server, :host_engine, :engine
end

# Log payload shared by the v1 controller and the MCP `query_logs` tool.
#
# Live logs are best-effort: when the host is unreachable the caller gets the
# stored deployment logs plus an explicit reason, never an empty list that
# looks like "no traffic".
class AgentLogs
  def initialize(service:, limit: 100)
    @service = service
    @limit = limit
  end

  def payload
    live, error = live_logs
    return live if live

    payload = {
      service_id: service.id.to_s,
      source: "stored",
      truncated: false,
      lines: service.logs.last(limit).map do |entry|
        {
          timestamp: entry[:timestamp]&.iso8601,
          process_type: entry[:process_type],
          message: LogRedactor.redact(entry[:message].to_s)
        }
      end
    }
    payload[:error] = error if error
    payload
  end

  private

  attr_reader :service, :limit

  def live_logs
    server = service.project&.server
    return [ nil, nil ] unless server&.ssh_key.present?

    engine = DokkuEngine.new(server)
    result = if service.subtype_record&.has_capability?(:logs)
      engine.datastore_logs(service)
    else
      engine.logs(service.dokku_app_name, lines: limit)
    end
    return [ nil, LogRedactor.redact(result[:output].to_s) ] unless result[:success]

    output = result[:output].to_s.lines
    [
      {
        service_id: service.id.to_s,
        source: "host",
        truncated: output.size > limit,
        lines: output.last(limit).map do |line|
          {
            timestamp: Time.current.iso8601,
            process_type: service.subtype,
            message: LogRedactor.redact(line).chomp
          }
        end
      },
      nil
    ]
  rescue StandardError => error
    [ nil, LogRedactor.redact(error.message) ]
  end
end

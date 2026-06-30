class SetupProgress
  CACHE_TTL = 1.hour
  MAX_LOGS = 200

  class << self
    def start(setup_id)
      write(setup_id, state: "connecting", logs: [], error: nil, server_id: nil)
    end

    def log(setup_id, line, stream: nil)
      update(setup_id, type: "log", line: line, stream: stream)
    end

    def complete(setup_id, server_id: nil)
      update(setup_id, type: "completed", server_id: server_id)
    end

    def fail(setup_id, error)
      update(setup_id, type: "failed", error: error)
    end

    def update(setup_id, payload)
      current = get(setup_id)

      case payload[:type]
      when "log", "error"
        entry = { line: payload[:line] || payload[:error] || "", stream: payload[:stream], timestamp: Time.current.iso8601 }
        current[:logs] = (current[:logs] || []).last(MAX_LOGS - 1) + [ entry ]
        current[:state] = "live"
      when "failed"
        current[:state] = "failed"
        current[:error] = payload[:error]
      when "completed"
        current[:state] = "completed"
        current[:server_id] = payload[:server_id]&.to_s
      end

      write(setup_id, **current.slice(:state, :logs, :error, :server_id))
    end

    def get(setup_id)
      Rails.cache.read(cache_key(setup_id)) || default_payload(setup_id)
    end

    private

    def write(setup_id, state:, logs:, error:, server_id:)
      payload = default_payload(setup_id).merge(state: state, logs: logs || [], error: error, server_id: server_id)
      Rails.cache.write(cache_key(setup_id), payload, expires_in: CACHE_TTL)
    end

    def default_payload(setup_id)
      { setup_id: setup_id, state: "connecting", logs: [], error: nil, server_id: nil }
    end

    def cache_key(setup_id)
      "server_setup:#{setup_id}"
    end
  end
end

# Per-token request budget.
#
# The counter lives in the shared cache, not the database: it is throwaway,
# must expire quickly and must never turn polling into write load. A cache
# failure disables limiting instead of taking the agent surface down with it.
class AgentRateLimit
  PERIOD = 1.minute
  DEFAULT_LIMIT = 120

  class << self
    # Returns the number of seconds to wait when the token is over budget, or
    # nil when the request is allowed.
    def retry_after(token, now: Time.current)
      return if token.nil?

      count = increment(bucket_for(token, now))
      return if count <= limit

      PERIOD.to_i - (now.to_i % PERIOD.to_i)
    rescue StandardError
      nil
    end

    def limit
      value = ENV["AGENT_RATE_LIMIT_PER_MINUTE"].to_i
      value.positive? ? value : DEFAULT_LIMIT
    end

    private

    def bucket_for(token, now)
      "agent-rate:#{token.id}:#{now.to_i / PERIOD.to_i}"
    end

    def increment(bucket)
      count = Rails.cache.increment(bucket, 1, expires_in: PERIOD * 2)
      return count if count

      Rails.cache.write(bucket, 1, expires_in: PERIOD * 2)
      1
    end
  end
end

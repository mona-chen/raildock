require "net/ssh"

# Refreshes `servers.status` so it reflects whether RailDock can still reach
# each host, instead of whatever it was the last time someone clicked
# "Check connection". Runs on `maintenance`: SSH to a dead host can take the
# full connect timeout, which must not hold a deployment or backup thread.
#
# No database lock is held while SSH runs. Each server row is re-read, the
# probe runs with no transaction open, and only the status columns are written
# back with a single UPDATE — never the host key, which a probe could only
# capture in memory when it is missing.
class ServerHealthCheckJob < ApplicationJob
  queue_as :maintenance

  # One sweep at a time; a slow sweep must not pile up behind the scheduler.
  limits_concurrency to: 1, key: "server_health_check", duration: 30.minutes

  ERROR_LIMIT = 250
  CONNECT_TIMEOUT = 10
  ATTEMPTS = 2

  def perform(server_ids = nil)
    scope = Server.where.not(ssh_key_ciphertext: nil)
    scope = scope.where(id: server_ids) if server_ids.present?

    scope.pluck(:id).each do |server_id|
      check(server_id)
    end
  end

  private

  def check(server_id)
    server = Server.find_by(id: server_id)
    return unless server

    result = probe(server)
    attrs = { status_checked_at: Time.current }
    if result[:success]
      attrs[:status] = "connected"
      attrs[:status_error] = nil
      attrs[:dokku_version] = result[:dokku_version] if result[:dokku_version].present?
    else
      attrs[:status] = "error"
      attrs[:status_error] = result[:error].to_s.truncate(ERROR_LIMIT)
    end

    previous = server.status
    Server.where(id: server_id).update_all(attrs)
    log_transition(server, previous, attrs)
  rescue => e
    Rails.logger.warn "ServerHealthCheckJob: #{server_id} check failed: #{e.class}: #{e.message}"
  end

  # A short, single-purpose probe rather than DokkuEngine#run: that retries a
  # timeout three times with backoff, so one dead host would hold the sweep
  # (and the maintenance worker) for minutes. Two quick attempts are enough to
  # ride out a blip without flapping the status.
  def probe(server)
    attempts = 0
    begin
      attempts += 1
      output = run_version(server)
      version = DokkuEngine.parse_version(output)
      return { success: true, dokku_version: version } if version

      { success: false, error: output.strip.presence || "Dokku did not respond" }
    rescue Net::SSH::AuthenticationFailed, Net::SSH::HostKeyMismatch => e
      { success: false, error: "#{e.class.name.demodulize}: #{e.message}" }
    rescue => e
      retry if attempts < ATTEMPTS
      { success: false, error: "#{e.class.name.demodulize}: #{e.message}" }
    end
  end

  def run_version(server)
    user = server.ssh_user
    builder = SshConnectionBuilder.new(server, user: user)
    command = user.to_s == "dokku" ? "version" : "dokku version"
    Net::SSH.start(server.host, user, builder.options.merge(timeout: CONNECT_TIMEOUT)) do |ssh|
      ssh.exec!(command).to_s.dup.force_encoding("UTF-8").scrub
    end
  ensure
    builder&.cleanup
  end

  def log_transition(server, previous, attrs)
    return if previous.to_s == attrs[:status]

    if attrs[:status] == "error"
      Rails.logger.warn "ServerHealthCheckJob: #{server.name} (#{server.host}) became unreachable: #{attrs[:status_error]}"
    else
      Rails.logger.info "ServerHealthCheckJob: #{server.name} (#{server.host}) is reachable again"
    end
  end
end

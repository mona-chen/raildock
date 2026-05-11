class LogsChannel < ApplicationCable::Channel
  def subscribed
    service = Service.find(params[:service_id])

    # Authorization: verify the user can access this service's project
    reject unless current_user
    if service.project&.organization_id
      unless current_user.organizations.exists?(id: service.project.organization_id)
        reject
        return
      end
    end

    stream_for service
    Rails.logger.info "[ActionCable] LogsChannel subscribed for service #{service.id} (user #{current_user.id})"

    # Start a background thread to tail logs from Dokku
    @thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        tail_logs(service)
      end
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ActionCable] LogsChannel subscription rejected: service #{params[:service_id]} not found"
    reject
  end

  def unsubscribed
    Rails.logger.info "[ActionCable] LogsChannel unsubscribed"
    @thread&.kill
  end

  private

  def tail_logs(service)
    server = service.project&.server
    return unless server&.ssh_key.present?

    log_cmd = if service.service_type == "database"
      case service.subtype
      when "postgres" then "postgres:logs #{service.dokku_app_name} --tail"
      when "redis" then "redis:logs #{service.dokku_app_name} --tail"
      when "mysql" then "mysql:logs #{service.dokku_app_name} --tail"
      when "mongo" then "mongo:logs #{service.dokku_app_name} --tail"
      else "logs #{service.dokku_app_name} -n 0 --tail"
      end
    else
      "logs #{service.dokku_app_name} -n 0 --tail"
    end

    Net::SSH.start(server.host, "dokku", key_data: [server.ssh_key], non_interactive: true) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.exec(log_cmd) do |_, success|
          unless success
            Rails.logger.error "LogsChannel: failed to execute logs command"
            return
          end

          ch.on_data do |_, data|
            data.split("\n").each do |line|
              next if line.strip.empty?
              parsed = parse_log_line(line)
              next if parsed[:message].empty?
              LogsChannel.broadcast_to(service, parsed)
            end
          end

          ch.on_extended_data do |_, type, data|
            data.split("\n").each do |line|
              next if line.strip.empty?
              parsed = parse_log_line(line)
              next if parsed[:message].empty?
              LogsChannel.broadcast_to(service, parsed.merge(process_type: 'stderr'))
            end
          end
        end
      end
      channel.wait
    end
  rescue => e
    Rails.logger.error "LogsChannel error: #{e.message}"
  end

  # Strip ANSI codes from log output
  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, '')
  end

  # Parse Dokku/Docker log lines:
  # Format: "2026-05-09T02:24:27Z app[web.1]: message here"
  # or with ANSI: "\e[36m2026-05-09T02:24:27Z app[web.1]: message\e[0m"
  def parse_log_line(line)
    clean = strip_ansi(line).strip

    # Try to extract timestamp and process type from Docker format
    # Pattern: <ISO timestamp> <process>[<container>]: <message>
    if match = clean.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\s+(\w+)\[(\w+)\.?\d*\]:\s*(.*)$/)
      timestamp, _process, process_type, message = match.captures
      return {
        timestamp: timestamp,
        process_type: process_type || "app",
        message: message.strip
      }
    end

    # Fallback: try "process.type | message" format (older Dokku)
    if match = clean.match(/^(\w+)\.\d+\s*\|\s*(.*)$/)
      process_type, message = match.captures
      return {
        timestamp: Time.current.iso8601,
        process_type: process_type,
        message: message.strip
      }
    end

    # Default fallback
    {
      timestamp: Time.current.iso8601,
      process_type: "app",
      message: clean
    }
  end
end

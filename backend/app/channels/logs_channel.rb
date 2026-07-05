class LogsChannel < ApplicationCable::Channel
  # Thread-safe map to track active log streams per service
  cattr_accessor(:active_log_streams, default: Concurrent::Map.new)
  cattr_accessor(:active_log_threads, default: Concurrent::Map.new)
  cattr_accessor(:active_subscribers, default: Concurrent::Map.new)

  class << self
    def add_subscriber(service_id, subscriber_id)
      subscribers = active_subscribers.compute_if_absent(service_id) { Concurrent::Set.new }
      subscribers.add(subscriber_id)
      subscribers.size == 1
    end

    def remove_subscriber(service_id, subscriber_id)
      subscribers = active_subscribers[service_id]
      return false unless subscribers

      subscribers.delete(subscriber_id)
      return false unless subscribers.empty?

      active_subscribers.delete_pair(service_id, subscribers)
      true
    end
  end

  def subscribed
    service = Service.find(params[:service_id])
    @service = service

    # Authorization: verify the user can access this service's project
    unless project_accessible?(service.project)
      reject
      return
    end

    stream_for service
    Rails.logger.info "[ActionCable] LogsChannel subscribed for service #{service.id} (user #{current_user.id})"

    # Start log tailing with proper cleanup
    first_subscriber = self.class.add_subscriber(service.id, object_id)
    start_log_stream(service) if first_subscriber || !active_log_threads.key?(service.id)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ActionCable] LogsChannel subscription rejected: service #{params[:service_id]} not found"
    reject
  end

  def unsubscribed
    Rails.logger.info "[ActionCable] LogsChannel unsubscribed"
    stop_log_stream if @service && self.class.remove_subscriber(@service.id, object_id)
  end

  private

  def start_log_stream(service)
    # Use a thread-safe queue to signal shutdown
    stop_token = Concurrent::Atom.new(false)

    # Claim the service before starting the thread so simultaneous browser tabs
    # cannot create duplicate SSH tails.
    return if active_log_streams.put_if_absent(service.id, stop_token)

    # Run log tailing in a background executor to avoid blocking ActionCable
    thread = Thread.new do
      tail_logs(service, stop_token)
    end
    active_log_threads[service.id] = thread
  rescue
    active_log_streams.delete_pair(service.id, stop_token)
    raise
  end

  def stop_log_stream
    return unless @service

    stop_log_stream_for(@service)
  end

  def stop_log_stream_for(service)
    if stop_token = active_log_streams.delete(service.id)
      stop_token.reset(true)
    end

    if thread = active_log_threads.delete(service.id)
      thread.kill
    end
  end

  def tail_logs(service, stop_token)
    server = service.project&.server
    return unless server&.ssh_key.present?

    log_cmd = if service.subtype_record&.has_capability?(:logs)
      st = service.subtype_record
      "#{st.dokku_command(:logs)} #{service.dokku_app_name} --tail"
    else
      "logs #{service.dokku_app_name} -n 0 --tail"
    end

    begin
      Net::SSH.start(server.host, "dokku", key_data: [ server.ssh_key ], non_interactive: true, timeout: 10) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(log_cmd) do |_, success|
            unless success
              Rails.logger.error "LogsChannel: failed to execute logs command"
              RealtimeBroadcaster.logs(service, { type: "stream_state", state: "fallback" })
              return
            end

            RealtimeBroadcaster.logs(service, { type: "stream_state", state: "live" })

            ch.on_data do |_, data|
              break if stop_token.value
              data.split("\n").each do |line|
                next if line.strip.empty?
                parsed = parse_log_line(line)
                next if parsed[:message].empty?
                RealtimeBroadcaster.logs(service, parsed)
              end
            end

            ch.on_extended_data do |_, type, data|
              break if stop_token.value
              data.split("\n").each do |line|
                next if line.strip.empty?
                parsed = parse_log_line(line)
                next if parsed[:message].empty?
                RealtimeBroadcaster.logs(service, parsed.merge(process_type: "stderr"))
              end
            end
          end
        end
        channel.wait
      end
    rescue Net::SSH::Exception => e
      Rails.logger.error "LogsChannel SSH error: #{e.message}"
      RealtimeBroadcaster.logs(service, { type: "stream_state", state: "fallback" })
    rescue => e
      Rails.logger.error "LogsChannel error: #{e.message}"
      RealtimeBroadcaster.logs(service, { type: "stream_state", state: "fallback" })
    ensure
      # Only remove this worker's entries. A replacement worker may already be
      # running after a reconnect.
      active_log_streams.delete_pair(service.id, stop_token)
      active_log_threads.delete_pair(service.id, Thread.current)
    end
  end

  # Strip ANSI codes from log output
  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, "")
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

class TerminalChannel < ApplicationCable::Channel
  def subscribed
    @service = Service.find(params[:service_id])

    # Authorization: terminal access is equivalent to command execution.
    reject and return unless current_user
    unless terminal_allowed?(@service)
      reject
      return
    end

    stream_for @service
    Rails.logger.info "[ActionCable] TerminalChannel subscribed for service #{@service.id} (user #{current_user.id})"

    # Confirm the Action Cable subscription immediately. SSH/container startup
    # can legitimately take longer than a websocket handshake and must not
    # block subscription confirmation.
    @open_thread = Thread.new { open_terminal_session }
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ActionCable] TerminalChannel subscription rejected: service #{params[:service_id]} not found"
    reject
  rescue => error
    Rails.logger.error "[ActionCable] TerminalChannel subscription failed: #{error.class}: #{error.message}"
    reject
  end

  def unsubscribed
    Rails.logger.info "[ActionCable] TerminalChannel unsubscribed for service #{@service&.id}"
    close_terminal_session
  end

  # Receive keystrokes from browser and forward to SSH channel
  def input(data)
    return unless @session && !@session.closed?
    @session.send_data(data["data"])
  rescue => e
    Rails.logger.error "[TerminalChannel] input error: #{e.message}"
  end

  # Receive resize events from browser
  def resize(data)
    return unless @session && !@session.closed?
    @session.resize(cols: data["cols"].to_i, rows: data["rows"].to_i)
  rescue => e
    Rails.logger.error "[TerminalChannel] resize error: #{e.message}"
  end

  private

  def terminal_allowed?(service)
    project = service.project
    return false unless project
    return true if current_user.admin?

    if project.organization_id.nil?
      return project.user_id == current_user.id
    end

    project_accessible?(project, roles: %i[owner admin])
  end

  def open_terminal_session
    server = @service.project&.server
    unless server&.ssh_key.present?
      transmit({ type: "error", data: "No server configured for this project" })
      return
    end

    engine = DokkuEngine.new(server)
    requested_shell = @requested_shell || params["shell"].presence || "/bin/sh"
    @session = engine.interactive_shell(
      @service.dokku_app_name,
      process_type: @service.service_type == "database" ? @service.subtype : "web",
      shell: requested_shell,
      database: @service.service_type == "database"
    )

    unless @session
      transmit({ type: "error", data: "Failed to open terminal session" })
      return
    end

    @session.on_open do
      transmit({ type: "connected" })
    end

    @session.on_data do |data|
      # Base64-encode binary data to safely transmit through JSON
      transmit({ type: "data", data: Base64.strict_encode64(data) })
    end

    @session.on_close do
      transmit({ type: "closed" })
    end

    @session.on_error do |message|
      transmit({ type: "error", data: message, shell: @session.shell })
      # If the user's selected shell is missing in the container, retry
      # once with /bin/sh so the user gets a working session instead of
      # an endless spinner.
      if @fallback_attempted.nil? && @session.shell != "/bin/sh" && shell_missing_error?(message)
        @fallback_attempted = true
        Rails.logger.info "[TerminalChannel] retrying with /bin/sh after shell error: #{message}"
        retry_with_shell("/bin/sh")
      end
    end

    unless @session.open
      # Error callback may have already fired from within open(); only
      # send a generic fallback if the session never signalled an error.
      transmit({ type: "error", data: "Failed to establish SSH connection" })
    end
  rescue => e
    Rails.logger.error "[TerminalChannel] open_terminal_session error: #{e.message}"
    transmit({ type: "error", data: "Failed to open terminal: #{e.message}" })
  end

  def shell_missing_error?(message)
    message.to_s.match?(/not available in this container|stat .* no such file|Shell exited with status/)
  end

  def retry_with_shell(shell)
    close_terminal_session
    @requested_shell = shell
    open_terminal_session
  rescue => e
    Rails.logger.error "[TerminalChannel] retry_with_shell error: #{e.message}"
  end

  def close_terminal_session
    @open_thread&.kill if @open_thread != Thread.current
    @open_thread = nil
    return unless @session
    @session.close
    @session = nil
  rescue => e
    Rails.logger.error "[TerminalChannel] close_terminal_session error: #{e.message}"
  end
end

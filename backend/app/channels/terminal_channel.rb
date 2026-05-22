class TerminalChannel < ApplicationCable::Channel
  def subscribed
    @service = Service.find(params[:service_id])

    # Authorization
    reject unless current_user
    if @service.project&.organization_id
      unless current_user.organizations.exists?(id: @service.project.organization_id)
        reject
        return
      end
    end

    stream_for @service
    Rails.logger.info "[ActionCable] TerminalChannel subscribed for service #{@service.id} (user #{current_user.id})"

    # Open interactive PTY session
    open_terminal_session
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ActionCable] TerminalChannel subscription rejected: service #{params[:service_id]} not found"
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

  def open_terminal_session
    server = @service.project&.server
    unless server&.ssh_key.present?
      transmit({ type: "error", data: "No server configured for this project" })
      return
    end

    engine = DokkuEngine.new(server)
    shell = params["shell"].presence || "/bin/sh"
    @session = engine.interactive_shell(
      @service.dokku_app_name,
      process_type: @service.service_type == "database" ? @service.subtype : "web",
      shell: shell,
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
      transmit({ type: "error", data: message })
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

  def close_terminal_session
    return unless @session
    @session.close
    @session = nil
  rescue => e
    Rails.logger.error "[TerminalChannel] close_terminal_session error: #{e.message}"
  end
end

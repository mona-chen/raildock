# frozen_string_literal: true

# ActionCable's Connection::Base#handle_channel_command raises
# ActionCable::Connection::Subscriptions::Find::NoSubscriptionError
# (a RuntimeError) when the client sends a `message` for a subscription
# the server no longer has — typically after a reconnect race where the
# browser still references a subscription that the server already cleaned
# up. The unhandled exception tears down the connection's event loop and
# every subsequent /cable upgrade silently closes with a close frame
# until the process is restarted.
#
# Rescue and log instead so a single stale frame can never poison the
# whole cable broker.
Rails.application.config.after_initialize do
  ActionCable::Connection::Base.class_eval do
    def handle_channel_command(payload)
      run_callbacks :command do
        subscriptions.execute_command(payload)
      end
    rescue => error
      Rails.logger.warn(
        "[ActionCable] dropping bad channel command " \
        "payload=#{payload.inspect} " \
        "error=#{error.class}: #{error.message}"
      )
    end
  end
end

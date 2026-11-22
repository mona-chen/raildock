class ServerSetupChannel < ApplicationCable::Channel
  def subscribed
    setup_id = params[:setup_id].to_s
    # The stream carries host details and bootstrap output, so only members of
    # the organization that started the setup may follow it.
    reject and return unless Server.setup_accessible_by?(setup_id, current_user)

    stream_from "server_setup:#{setup_id}"
    Rails.logger.info "[ActionCable] ServerSetupChannel subscribed for setup #{setup_id} (user #{current_user&.id})"
  end

  def unsubscribed
    Rails.logger.info "[ActionCable] ServerSetupChannel unsubscribed"
  end
end

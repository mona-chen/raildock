class ServerSetupChannel < ApplicationCable::Channel
  def subscribed
    setup_id = params[:setup_id]
    reject and return if setup_id.blank?

    stream_from "server_setup:#{setup_id}"
    Rails.logger.info "[ActionCable] ServerSetupChannel subscribed for setup #{setup_id} (user #{current_user&.id})"
  end

  def unsubscribed
    Rails.logger.info "[ActionCable] ServerSetupChannel unsubscribed"
  end
end

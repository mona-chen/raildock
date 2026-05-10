class DeploymentsChannel < ApplicationCable::Channel
  def subscribed
    service = Service.find(params[:service_id])
    stream_for service
    Rails.logger.info "[ActionCable] DeploymentsChannel subscribed for service #{service.id} (user #{current_user.id})"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ActionCable] DeploymentsChannel subscription rejected: service #{params[:service_id]} not found"
    reject
  end

  def unsubscribed
    Rails.logger.info "[ActionCable] DeploymentsChannel unsubscribed"
  end
end

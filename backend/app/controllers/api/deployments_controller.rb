module Api
  class DeploymentsController < BaseController
    before_action :set_service, only: [:index]

    def index
      @deployments = @service.deployments.order(created_at: :desc).limit(20)
      render json: @deployments
    end

    def show
      @deployment = Deployment.find(params[:id])
      render json: @deployment
    end

    private

    def set_service
      @service = Service.find(params[:service_id])
    end
  end
end

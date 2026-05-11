module Api
  class DeploymentsController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!, only: [:index]

    def index
      @deployments = @service.deployments.order(created_at: :desc).limit(20)
      render json: @deployments
    end

    def show
      @deployment = Deployment.find(params[:id])
      authorize_service!(@deployment.service)
      render json: @deployment
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end
  end
end

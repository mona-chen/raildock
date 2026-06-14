module Api
  class DeploymentsController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!, only: [ :index ]

    def index
      @deployments = @service.deployments.order(created_at: :desc).limit(20)
      render json: @deployments
    end

    def show
      @deployment = Deployment.find(params[:id])
      authorize_service!(@deployment.service)
      render json: @deployment
    end

    def cancel
      @deployment = Deployment.find(params[:id])
      authorize_service!(@deployment.service)

      if @deployment.cancel!
        render json: { success: true, deployment_id: @deployment.id, status: "cancelled" }
      else
        render json: { success: false, error: "Deployment is not cancellable (status: #{@deployment.status})" }, status: :unprocessable_entity
      end
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end
  end
end

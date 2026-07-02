module Api
  class BackupDestinationsController < BaseController
    before_action :set_organization
    before_action :require_member!
    before_action :set_destination, only: [ :show, :update, :destroy, :verify ]
    before_action :require_admin!, only: [ :create, :update, :destroy ]

    def index
      destinations = @organization.backup_destinations.order(:name)
      render json: destinations
    end

    def show
      render json: @destination
    end

    def create
      destination = @organization.backup_destinations.build(destination_params)
      BackupDestinationClient.new(destination).verify! if destination.valid?
      destination.save!
      render json: destination.as_json.merge("recovery_key" => destination.encryption_key), status: :created
    rescue => error
      destination&.status = "failed"
      destination&.save(validate: false) if destination&.persisted?
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    def update
      @destination.assign_attributes(destination_params.except(:encryption_key))
      BackupDestinationClient.new(@destination).verify! if @destination.valid?
      @destination.save!
      render json: @destination
    rescue => error
      @destination.update_columns(status: "failed")
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    def destroy
      @destination.destroy!
      head :no_content
    end

    def verify
      BackupDestinationClient.new(@destination).verify!
      render json: @destination.reload
    rescue => error
      @destination.update_columns(status: "failed")
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    private

      def set_organization
        @organization = Organization.find(params[:organization_id])
        authorize_organization_access!(@organization)
      end

      def set_destination
        @destination = @organization.backup_destinations.find(params[:id])
      end

      def require_member!
        return if current_user.organizations.include?(@organization)

        render json: { error: "Forbidden" }, status: :forbidden
      end

      def require_admin!
        membership = @organization.memberships.find_by(user: current_user)
        return if membership&.admin? || membership&.owner?

        render json: { error: "Admin access required" }, status: :forbidden
      end

      def destination_params
        params.permit(
          :name, :provider, :endpoint, :region, :bucket, :path_prefix,
          :access_key_id, :secret_access_key, :encryption_key
        )
      end
  end
end

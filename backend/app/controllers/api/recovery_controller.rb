module Api
  class RecoveryController < BaseController
    include Authorizable

    before_action :set_service

    def show
      render json: {
        destinations: reachable_destinations,
        pitr: @service.postgres_pitr_config,
        drills: RestoreDrill.joins(:backup).where(backups: { service_id: @service.id }).recent.limit(25)
      }
    end

    def create_destination
      authorize_service!(@service, action: :update)
      destination = @service.project.server.backup_destinations.create!(destination_params)
      BackupDestinationClient.new(destination).verify!
      render json: destination.as_json.merge("recovery_key" => destination.encryption_key), status: :created
    rescue => error
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    def verify_destination
      authorize_service!(@service, action: :update)
      destination = destination_scope.find(params[:destination_id])
      BackupDestinationClient.new(destination).verify!
      render json: destination.reload
    rescue => error
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    def destroy_destination
      authorize_service!(@service, action: :delete)
      destination_scope.find(params[:destination_id]).destroy!
      head :no_content
    end

    def snapshot_volume
      authorize_service!(@service, action: :update)
      mount = @service.storage_mounts.find(params[:storage_mount_id])
      destination_ids = Array(params[:backup_destination_ids]).compact_blank.map(&:to_s)
      backup = @service.backups.create!(
        status: "pending",
        backup_kind: "volume",
        metadata: { "trigger" => "manual", "storage_mount_id" => mount.id, "destination_ids" => destination_ids }
      )
      VolumeBackupJob.perform_later(backup.id, mount.id)
      render json: backup, status: :accepted
    end

    def configure_pitr
      authorize_service!(@service, action: :update)
      return render json: { error: "PITR is not available for this service type" }, status: :unprocessable_entity unless @service.subtype_record&.has_capability?(:point_in_time_recovery)

      destination = find_destination(params[:backup_destination_id])
      return render json: { error: "Destination not found" }, status: :not_found unless destination

      config = @service.postgres_pitr_config || @service.build_postgres_pitr_config
      config.assign_attributes(backup_destination: destination, retention_days: params[:retention_days] || 7)
      config.save!
      PostgresPitrConfigurator.new(config).enable!
      PostgresBaseBackupJob.perform_later(config.id)
      render json: config.reload
    end

    def disable_pitr
      authorize_service!(@service, action: :update)
      PostgresPitrConfigurator.new(@service.postgres_pitr_config).disable! if @service.postgres_pitr_config
      render json: @service.postgres_pitr_config
    end

    def create_drill
      authorize_service!(@service, action: :update)
      backup = @service.backups.find(params[:backup_id])
      drill = backup.restore_drills.create!
      RestoreDrillJob.perform_later(drill.id)
      render json: drill, status: :accepted
    end

    private
      def set_service
        @service = Service.find(params[:service_id])
        authorize_service!(@service)
      end

      def destination_scope
        BackupDestination.reachable_from(@service.project.server, organization: @service.project.organization)
      end

      def find_destination(id)
        return nil if id.blank?

        destination_scope.find_by(id: id)
      end

      # Destinations this service can back up to: the server's own, plus every
      # destination owned by the organization that owns the project.
      #
      # The organization must come from the project. A server is shared
      # infrastructure and is frequently not assigned to an organization at
      # all, so reading `server.organization` here hid every
      # organization-scoped destination — the service's Backup tab reported
      # "no destinations configured" moments after one was created in Settings.
      def reachable_destinations
        destination_scope.order(:name).to_a
      end

      def destination_params
        params.permit(:name, :provider, :endpoint, :region, :bucket, :path_prefix, :access_key_id, :secret_access_key, :encryption_key)
      end
  end
end

module Api
  class RecoveryController < BaseController
    include Authorizable

    before_action :set_service

    around_action :serialize_service_write


    def show
      render json: {
        destinations: reachable_destinations,
        pitr: @service.postgres_pitr_config,
        drills: RestoreDrill.joins(:backup).where(backups: { service_id: @service.id }).recent.limit(25),
        pitr_restores: PitrRestore.where(source_service_id: @service.id).includes(:restored_service).recent.limit(10),
        backup_preferences: backup_preferences
      }
    end

    # PATCH /api/services/:id/recovery/preferences
    #
    # Remembers the destinations picked in the backup card so it does not reset
    # to "Local only" on reload. `backup_destination_ids: null` drops the
    # service's own choice and inherits the organization default again, while
    # `[]` is stored as a deliberate "local only" choice.
    def update_preferences
      authorize_service!(@service, action: :update)

      if params[:backup_destination_ids].nil?
        @service.update!(default_backup_destination_ids: nil)
      else
        ids = Array(params[:backup_destination_ids]).compact_blank.map(&:to_s)
        unknown = ids - destination_scope.ids.map(&:to_s)
        return render json: { error: "Invalid backup destination(s): #{unknown.join(', ')}" }, status: :unprocessable_entity if unknown.any?

        @service.update!(default_backup_destination_ids: ids)
      end

      render json: { backup_preferences: backup_preferences }
    end

    def create_destination
      authorize_service!(@service, action: :update)
      # Creation and verification are one unit: a destination that failed its
      # probe must not linger as a "failed" row whose recovery key was never
      # shown to anyone.
      destination = BackupDestination.transaction do
        record = @service.project.server.backup_destinations.create!(destination_params)
        BackupDestinationClient.new(record).verify!
        record
      end
      render json: destination.as_json.merge("recovery_key" => destination.encryption_key), status: :created
    rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
      raise
    rescue => error
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    def verify_destination
      authorize_service!(@service, action: :update)
      destination = destination_scope.find(params[:destination_id])
      BackupDestinationClient.new(destination).verify!
      render json: destination.reload
    rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
      raise
    rescue => error
      render json: { error: "Destination verification failed: #{error.message}" }, status: :unprocessable_entity
    end

    def destroy_destination
      authorize_service!(@service, action: :delete)
      # Only the server's own destinations can be removed from a service.
      # Organization destinations are shared and are managed (with an
      # owner/admin check) from Settings → Backups.
      destination = @service.project.server.backup_destinations.find_by(id: params[:destination_id])
      unless destination
        return render json: { error: "Organization destinations are managed from Settings → Backups" }, status: :forbidden if destination_scope.exists?(id: params[:destination_id])

        raise ActiveRecord::RecordNotFound
      end

      if destination.destroy
        head :no_content
      else
        render json: { error: destination.errors.full_messages.to_sentence.presence || "Destination still owns backups", code: "destination_in_use" }, status: :unprocessable_entity
      end
    end

    def snapshot_volume
      authorize_service!(@service, action: :update)
      mount = @service.storage_mounts.find(params[:storage_mount_id])
      # Omitting the key follows the service's backup default (the same picker
      # the Backups tab uses); `[]` is an explicit local-only snapshot.
      destination_ids = if params.key?(:backup_destination_ids)
        Array(params[:backup_destination_ids]).compact_blank.map(&:to_s)
      else
        @service.resolved_backup_destination_ids
      end
      unknown = destination_ids - destination_scope.ids.map(&:to_s)
      return render json: { error: "Invalid backup destination(s): #{unknown.join(', ')}" }, status: :unprocessable_entity if unknown.any?

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
      # WAL is archived every minute with nobody watching; an unproven
      # destination would silently leave the database without recovery points.
      unless destination.verified?
        return render json: { error: "Verify #{destination.name} before using it for point-in-time recovery", code: "destination_unverified" }, status: :unprocessable_entity
      end

      config = @service.postgres_pitr_config || @service.build_postgres_pitr_config
      retention = params[:retention_days].presence || config.retention_days.presence || 7
      config.assign_attributes(backup_destination: destination, retention_days: retention)
      already_archiving = config.persisted? && config.enabled? && config.status != "error"
      destination_changed = config.backup_destination_id_changed?
      config.save!

      # WAL is archived to a directory inside the container and shipped by a
      # job, so a new window or destination needs no PostgreSQL change.
      # `enable!` restarts the database; only pay that when archiving is not
      # already running.
      PostgresPitrConfigurator.new(config).enable! unless already_archiving
      # A WAL chain is only recoverable from a base backup in the same place,
      # so a new destination starts with one.
      PostgresBaseBackupJob.perform_later(config.id) if !already_archiving || destination_changed
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
      target = begin
        Time.iso8601(params[:target_time]) if params[:target_time].present?
      rescue ArgumentError
        return render json: { error: "Recovery target must be an ISO-8601 timestamp" }, status: :unprocessable_entity
      end
      if target && (!backup.backup_kind_pitr_base? || target <= backup.created_at || target > Time.current)
        return render json: { error: "Choose a recovery target after the physical base backup and before now" }, status: :unprocessable_entity
      end
      drill = backup.restore_drills.create!(target_time: target)
      RestoreDrillJob.perform_later(drill.id)
      render json: drill, status: :accepted
    end

    # POST /api/services/:id/recovery/pitr/restore
    #
    # Recovers this PostgreSQL service to `target_time` into a NEW service in
    # the same project and environment. The live database is never written:
    # recovery happens in an isolated instance and is then loaded into the new
    # service by `PitrRestoreJob` (queue `backups`).
    def restore_pitr
      authorize_service!(@service, action: :update)
      unless @service.subtype_record&.has_capability?(:point_in_time_recovery) && @service.postgres_pitr_config
        return render json: { error: "Point-in-time recovery is not enabled for this service", code: "pitr_disabled" }, status: :unprocessable_entity
      end

      target = begin
        Time.iso8601(params[:target_time].to_s)
      rescue ArgumentError
        return render json: { error: "Recovery target must be an ISO-8601 timestamp", code: "invalid_target" }, status: :unprocessable_entity
      end

      bases = @service.backups.completed.where(backup_kind: "pitr_base").order(:created_at, :id)
      earliest = bases.first&.created_at
      latest_wal = @service.backups.completed.where(backup_kind: "wal").maximum(:created_at)
      if earliest.nil? || latest_wal.nil? || target <= earliest || target > latest_wal || target > Time.current
        return render json: {
          error: "Choose a moment inside the recovery window",
          code: "outside_window",
          window: { from: earliest&.iso8601, to: latest_wal&.iso8601 }
        }, status: :unprocessable_entity
      end
      base = bases.where("created_at < ?", target).last

      name = params[:name].to_s.strip
      return render json: { error: "Name the new service", code: "name_required" }, status: :unprocessable_entity if name.blank?
      if @service.project.services.where(environment_id: @service.environment_id).where("LOWER(name) = ?", name.downcase).exists?
        return render json: { error: "A service named #{name} already exists in this environment", code: "name_taken" }, status: :conflict
      end
      if PitrRestore.where(source_service_id: @service.id, status: %w[pending running]).exists?
        return render json: { error: "A recovery of #{@service.name} is already in progress", code: "restore_in_progress" }, status: :conflict
      end

      restore = PitrRestore.transaction do
        restored = @service.project.services.create!(
          name: name,
          environment: @service.environment,
          service_type: @service.service_type,
          subtype: @service.subtype,
          version: @service.version,
          docker_image: @service.docker_image,
          status: "deploying",
          canvas_x: @service.canvas_x.to_i + 280,
          canvas_y: @service.canvas_y.to_i
        )
        PitrRestore.create!(source_service: @service, restored_service: restored, backup: base,
          project: @service.project, target_time: target, service_name: name)
      end
      PitrRestoreJob.perform_later(restore.id)
      render json: { pitr_restore: restore, service: restore.restored_service }, status: :accepted
    end

    private

    def serialize_service_write
      return yield if request.get? || !@service

      ServiceOperationLock.with(@service) { yield }
    end

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

      # What the destination picker should show: the service's own choice (when
      # it has one), the organization default it would otherwise inherit, and
      # the two combined so a first render never flashes "Local only".
      def backup_preferences
        {
          organization_destination_ids: Array(@service.project&.organization&.default_backup_destination_ids),
          service_destination_ids: @service.default_backup_destination_ids,
          default_destination_ids: @service.resolved_backup_destination_ids
        }
      end

      def destination_params
        params.permit(:name, :provider, :endpoint, :region, :bucket, :path_prefix, :access_key_id, :secret_access_key, :encryption_key)
      end
  end
end

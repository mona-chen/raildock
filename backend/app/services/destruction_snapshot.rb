# frozen_string_literal: true

# Captures a verified, off-host snapshot of a service's data right before an
# irreversible operation (destroy, restore-over-live-data).
#
# Destroying a Dokku datastore (`<plugin>:destroy --force`) or an app with
# mounted volumes is irreversible, and RailDock's own API can trigger it from a
# single request or manifest apply. Before that happens we make sure a
# restorable artifact exists on a *verified* backup destination, so a mistake
# can never be the last copy of production data.
class DestructionSnapshot
  Result = Struct.new(:success, :backup, :error, :destinations, keyword_init: true) do
    def success?
      success
    end
  end

  # trigger: what is about to happen to the data. Recorded on the backup so the
  # UI can tell an "about to be destroyed" safety net apart from a routine
  # scheduled backup. Passed to capture_all as well.
  TRIGGERS = %w[pre_destroy pre_restore].freeze

  def initialize(service, engine: nil, host_engine: nil, destinations: nil, trigger: "pre_destroy")
    @service = service
    @engine = engine
    @host_engine = host_engine
    @destinations = destinations
    @trigger = TRIGGERS.include?(trigger.to_s) ? trigger.to_s : "pre_destroy"
  end

  class << self
    # A service holds data worth snapshotting when it is a datastore or mounts
    # persistent storage. Stateless apps are destroyed without a snapshot.
    def data_bearing?(service)
      return false if service.blank?
      return true if datastore?(service)

      persistent_mounts(service).any?
    end

    def datastore?(service)
      return false if service.blank?

      service.subtype_record&.has_capability?(:backup) ||
        service.subtype_record&.has_capability?(:destroy)
    end

    def persistent_mounts(service)
      service.storage_mounts.reject { |mount| mount.kind_tmpfs? }
    end

    # Snapshots every data-bearing service in a collection (used before a whole
    # project is destroyed). Returns the errors that make the operation unsafe.
    def capture_all(services, engine: nil, host_engine: nil, trigger: "pre_destroy")
      backups = []
      errors = []

      Array(services).select { |service| data_bearing?(service) }.each do |service|
        result = new(service, engine: engine, host_engine: host_engine, trigger: trigger).call
        if result.success?
          backups << result.backup if result.backup
        else
          errors << "#{service.name}: #{result.error}"
        end
      end

      { backups: backups, errors: errors }
    end
  end

  def call
    return Result.new(success: true, backup: nil, error: nil, destinations: []) unless self.class.data_bearing?(@service)

    destinations = verified_destinations
    if destinations.empty?
      return Result.new(
        success: false,
        backup: nil,
        destinations: [],
        error: "no verified backup destination is configured for #{@service.project&.server&.name || 'this server'}"
      )
    end

    backups = []
    errors = []

    if self.class.datastore?(@service)
      begin
        backups << snapshot_database(destinations)
      rescue => error
        errors << "database: #{error.message}"
      end
    end

    self.class.persistent_mounts(@service).each do |mount|
      begin
        backups << snapshot_volume(mount, destinations)
      rescue => error
        errors << "volume #{mount.container_path}: #{error.message}"
      end
    end

    if errors.empty?
      Result.new(success: true, backup: backups.first, error: nil, destinations: destinations)
    else
      Result.new(
        success: false,
        backup: backups.first,
        destinations: destinations,
        error: "pre-destroy snapshot failed (#{errors.join('; ')})"
      )
    end
  end

  private
    def snapshot_database(destinations)
      subtype = @service.subtype_record
      unless subtype&.has_capability?(:backup)
        raise "#{@service.subtype} does not support exports, so its data cannot be snapshotted"
      end

      backup = @service.backups.create!(
        status: "pending",
        backup_kind: "database",
        metadata: {
          "trigger" => @trigger,
          "destination_ids" => destination_ids(destinations),
          "recreation" => recreation_metadata
        }
      )
      export_and_persist!(backup, destinations) do |path|
        engine = @engine || DokkuEngine.new(@service.project.server)
        engine.datastore_export_to(@service, path)
      end
    end

    def snapshot_volume(mount, destinations)
      backup = @service.backups.create!(
        status: "pending",
        backup_kind: "volume",
        metadata: {
          "trigger" => @trigger,
          "storage_mount_id" => mount.id,
          "host_path" => mount.host_path,
          "container_path" => mount.container_path,
          "destination_ids" => destination_ids(destinations),
          "recreation" => recreation_metadata
        }
      )
      export_and_persist!(backup, destinations) do |path|
        host_engine = @host_engine || HostEngine.new(@service.project.server)
        host_engine.volume_export_to(mount.host_path, path)
      end
    end

    def export_and_persist!(backup, destinations)
      path = artifact_path(backup)
      FileUtils.mkdir_p(File.dirname(path))

      result = yield(path)
      unless result[:success]
        raise(result[:output].presence || "export failed")
      end

      BackupArtifactStore.new.persist!(
        backup,
        path,
        destination_ids: destination_ids(destinations),
        storage_name: "#{artifact_prefix}/#{backup.id}-#{backup.backup_kind}.backup.enc"
      )
      backup.reload
      raise "snapshot was not uploaded to a verified destination" unless backup.remote_copy_available?
      unless backup.metadata&.fetch("remote_verified", false)
        raise "snapshot upload could not be verified"
      end

      ActivityEvent.create!(
        project: @service.project,
        service_name: @service.name,
        action: :created,
        message: "Snapshot captured before #{trigger_action} #{@service.name}",
        metadata: { backup_id: backup.id, checksum: backup.metadata["checksum"], trigger: @trigger }
      )

      backup
    rescue => error
      backup.update!(status: "failed", metadata: (backup.metadata || {}).merge("error" => error.message))
      FileUtils.rm_f(path) if defined?(path) && path
      raise
    end

    def artifact_path(backup)
      suffix = backup.backup_kind_volume? ? "tar.gz" : "dump"
      File.join(
        Backup.storage_root,
        artifact_prefix,
        @service.id.to_s,
        "#{backup.id}-#{Time.current.utc.strftime('%Y%m%d%H%M%S')}.#{suffix}"
      )
    end

    def artifact_prefix
      @trigger.tr("_", "-")
    end

    def trigger_action
      case @trigger
      when "pre_restore" then "restoring over"
      else "destroying"
      end
    end

    # Everything needed to rebuild the service shell after it is destroyed.
    # Deliberately excludes environment variables and other secrets — those are
    # stored elsewhere and must never be written into backup metadata.
    def recreation_metadata
      {
        "name" => @service.name,
        "service_type" => @service.service_type,
        "subtype" => @service.subtype,
        "version" => @service.version,
        "docker_image" => @service.docker_image,
        "builder" => @service.builder,
        "start_command" => @service.start_command,
        "exposed" => @service.exposed,
        "port" => @service.port,
        "domains" => @service.domains.map(&:hostname),
        "storage_mounts" => self.class.persistent_mounts(@service).map { |mount| { "host" => mount.host_path, "container" => mount.container_path, "kind" => mount.kind } },
        "process_types" => @service.process_types.map { |process| { "name" => process.name, "quantity" => process.quantity } }
      }.compact
    end

    def destination_ids(destinations)
      destinations.map { |destination| destination.id.to_s }
    end

    def verified_destinations
      return @destinations if @destinations

      scope = BackupDestination.reachable_from(
        @service.project&.server, organization: @service.project&.organization
      )
      scope.where(status: "verified").order(:name).to_a
    end
end

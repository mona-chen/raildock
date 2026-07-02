# frozen_string_literal: true

# Keeps RAILDOCK_STORAGE_* environment variables in sync with a service's
# persistent storage mounts. These variables let apps discover their mount
# paths at runtime without hard-coding host-specific paths.
class StorageMountEnvSync
  SOURCE = "raildock-storage".freeze

  def initialize(service, engine)
    @service = service
    @engine = engine
  end

  def sync!
    return if @service.project&.server&.ssh_key.blank?

    vars = build_vars
    current_records = storage_env_records.index_by(&:key)
    current_keys = current_records.keys

    # Remove variables that are no longer needed.
    (current_keys - vars.keys).each do |key|
      record = current_records[key]
      @engine.config_unset(@service.dokku_app_name, key)
      record.destroy!
    end

    # Set or update the current variables in Dokku and in the database.
    vars.each do |key, value|
      record = current_records[key]
      if record
        record.update!(value: value) if record.value != value
      else
        @service.environment_variables.create!(
          key: key,
          value: value,
          source: SOURCE,
          is_dokku_internal: true
        )
      end
      @engine.config_set(@service.dokku_app_name, key, value)
    end
  end

  private

  def build_vars
    mounts = @service.storage_mounts.order(:created_at).to_a
    vars = {}

    mounts.each_with_index do |mount, index|
      vars["RAILDOCK_STORAGE_#{index}_HOST"] = mount.host_path
      vars["RAILDOCK_STORAGE_#{index}_CONTAINER_PATH"] = mount.container_path
    end

    # Convenience aliases for the common single-mount case.
    if mounts.any?
      vars["RAILDOCK_STORAGE_HOST"] = mounts.first.host_path
      vars["RAILDOCK_STORAGE_CONTAINER_PATH"] = mounts.first.container_path
      vars["RAILDOCK_STORAGE_COUNT"] = mounts.size.to_s
    end

    vars
  end

  def storage_env_records
    @service.environment_variables.where("key LIKE ?", "RAILDOCK_STORAGE_%")
  end
end

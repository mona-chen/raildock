# frozen_string_literal: true

# Copies one service's configuration into another environment.
#
# Extracted from `EnvironmentDuplicator` because environment *sync* needs the
# exact same rules when it adds a service the target is missing — "duplicate
# this environment" and "make this environment match that one" must never drift
# apart in what they consider a copyable setting.
#
# The copy is staged, not deployed: `status` is `stopped`, `last_deployed` is
# cleared, and the Dokku app name and webhook token are generated fresh by the
# model (`Service#generate_dokku_app_name` only fills a nil attribute, so a copy
# that carried the original name would collide on the host).
class ServiceCopier
  def initialize(source_service, environment, summary: nil)
    @source_service = source_service
    @environment = environment
    @summary = summary
  end

  def call
    copy = @environment.services.build(blueprint.attributes)
    copy.project = @environment.project
    copy.status = "stopped"
    copy.last_deployed = nil
    copy.canvas_x = @source_service.canvas_x
    copy.canvas_y = @source_service.canvas_y
    copy.save!

    count(:services, 1)
    copy_variables!(copy)
    copied_mounts = copy_mounts!(copy)
    copy_schedules!(copy, copied_mounts)
    copy_process_types!(copy)
    copy_temporary_domain!(copy)

    copy
  end

  # Links whose *both* ends are copies are recreated between the copies, so a
  # staging database is not linked to a production app. Returns the number of
  # links created.
  def self.link_copies!(copies)
    ids = copies.keys
    return 0 if ids.empty?

    links = ServiceLink.where(from_service_id: ids, to_service_id: ids).pluck(:from_service_id, :to_service_id)
    links.each { |from_id, to_id| ServiceLink.create!(from_service: copies[from_id], to_service: copies[to_id]) }
    links.size
  end

  private
    def blueprint
      @blueprint ||= ServiceBlueprint.new(@source_service)
    end

    def copy_variables!(copy)
      blueprint.variables.each do |variable|
        copy.environment_variables.create!(
          key: variable["key"],
          value: variable["value"],
          source: variable["source"]
        )
        count(:variables, 1)
      end
    end

    # Returns `{ source_mount_id => copied_mount }` so a remapped backup schedule
    # points at the copy's own mount instead of the original's.
    def copy_mounts!(copy)
      @source_service.storage_mounts.each_with_object({}) do |mount, memo|
        count(:bind_mounts, 1) if mount.kind_bind?
        count(:volumes, 1) if mount.kind_volume?

        memo[mount.id] = copy.storage_mounts.create!(
          kind: mount.kind,
          container_path: mount.container_path,
          host_path: copied_host_path(mount, copy)
        )
      end
    end

    # A Docker volume name is derived from the Dokku app name, so copying it
    # verbatim would mount two services on one volume. Bind mounts keep the
    # operator's explicit path (that is the point of a bind mount) and are
    # reported as shared by the caller.
    def copied_host_path(mount, copy)
      return mount.host_path unless mount.kind_volume?

      StorageMount.volume_name_for(copy.dokku_app_name, mount.container_path)
    end

    def copy_schedules!(copy, copied_mounts)
      @source_service.backup_schedules.each do |schedule|
        mount = schedule.storage_mount_id ? copied_mounts[schedule.storage_mount_id] : nil
        next if schedule.volume? && mount.nil?

        copy.backup_schedules.create!(
          backup_kind: schedule.backup_kind,
          frequency: schedule.frequency,
          retention_count: schedule.retention_count,
          enabled: schedule.enabled,
          storage_mount: mount,
          # `schedule_id` is stamped on the *artifacts* a schedule produces; a
          # copy must not inherit it or retention would count the original's.
          metadata: schedule.metadata.to_h.except("schedule_id")
        ).tap(&:update_next_run!)
        count(:schedules, 1)
      end
    end

    def copy_process_types!(copy)
      @source_service.process_types.each do |process_type|
        copy.process_types.create!(
          name: process_type.name,
          quantity: process_type.quantity,
          command: process_type.command
        )
        count(:process_types, 1)
      end
    end

    # A publicly reachable source service should produce a reachable copy, but
    # never on the same hostname. The temporary hostname is derived from the
    # copy's own (fresh) Dokku app name, so it is unique by construction.
    def copy_temporary_domain!(copy)
      return unless @source_service.service_type_app?
      return unless @source_service.domains.any?(&:temporary?)

      domain = TemporaryDomainService.new(copy.project.server).ensure_for(copy)
      count(:temporary_domains, 1) if domain.present?
    end

    def count(key, amount)
      @summary[key] += amount if @summary
    end
end

# frozen_string_literal: true

# Pushes one environment's configuration into another one.
#
# Railway's environment comparison and Coolify's "deploy this resource to
# another environment" both come down to the same operation, and the safe way to
# express it is: **sync only ever adds or updates**. It never destroys.
#
# That is not timidity, it is the invariant RailDock already holds everywhere
# else (see AGENTS.md, "Destructive operations"): a service can own a database,
# a volume and a set of backup artifacts, and the only sanctioned way to remove
# one is the guarded destroy endpoint that snapshots first and demands the
# service name back. A sync that silently deleted a staging service because
# production no longer has it would be a back door around exactly that guard.
# Services that exist only in the target are therefore *reported*, and the
# operator removes them deliberately.
#
# Sync also leaves anything the target has and the source does not (a
# staging-only variable, an extra build setting) untouched — see
# `ServiceBlueprint#differences_from`, which is directional for this reason.
class EnvironmentSync
  Result = Struct.new(:plan, :added, :updated, :removed, :message, keyword_init: true)

  def initialize(source:, target:, actor: nil)
    @source = source
    @target = target
    @actor = actor
  end

  def preview
    EnvironmentDiff.new(source: @source, target: @target).call
  end

  def call
    plan = preview
    added = []
    updated = []

    Environment.transaction do
      plan.added.each { |entry| added << apply_added!(entry) }
      plan.edited.each { |entry| updated << apply_edited!(entry) }
      remap_links!(plan)
    end

    record_activity!(plan, added, updated)
    Result.new(plan: plan, added: added, updated: updated, removed: plan.removed, message: message_for(plan))
  end

  private
    def apply_added!(entry)
      source_service = source_service_for(entry)
      ServiceCopier.new(source_service, @target).call
    end

    def apply_edited!(entry)
      source_service = source_service_for(entry)
      target_service = target_service_for(entry)
      blueprint = ServiceBlueprint.new(source_service)

      target_service.update!(attributes_to_apply(blueprint, target_service))
      sync_variables!(blueprint, target_service)
      sync_mounts!(source_service, target_service)
      sync_schedules!(source_service, target_service)

      target_service
    end

    # `config` / `config_overrides` / `external_networks` are merged rather than
    # replaced so a target-specific setting is never a casualty of a sync.
    def attributes_to_apply(blueprint, target_service)
      attributes = blueprint.attributes.except("name")
      attributes["config"] = (target_service.config || {}).deep_merge(blueprint.attributes["config"] || {})
      attributes["config_overrides"] =
        (target_service.config_overrides || {}).deep_merge(blueprint.attributes["config_overrides"] || {})
      attributes["external_networks"] =
        (Array(target_service.external_networks) | Array(blueprint.attributes["external_networks"]))
      attributes
    end

    def sync_variables!(blueprint, target_service)
      existing = target_service.environment_variables.index_by(&:key)
      blueprint.variables.each do |variable|
        record = existing[variable["key"]]
        if record
          record.update!(value: variable["value"]) if record.value != variable["value"]
        else
          target_service.environment_variables.create!(
            key: variable["key"], value: variable["value"], source: variable["source"]
          )
        end
      end
    end

    def sync_mounts!(source_service, target_service)
      existing = target_service.storage_mounts.index_by(&:container_path)
      ServiceBlueprint.new(source_service).mounts.each do |mount|
        record = existing[mount["containerPath"]]
        if record.nil?
          target_service.storage_mounts.create!(
            kind: mount["kind"],
            container_path: mount["containerPath"],
            host_path: copied_host_path(mount, target_service)
          )
        elsif record.kind != mount["kind"] || (mount["hostPath"] && record.host_path != mount["hostPath"])
          record.update!(kind: mount["kind"], host_path: mount["hostPath"] || record.host_path)
        end
      end
    end

    def sync_schedules!(source_service, target_service)
      mounts = target_service.storage_mounts.index_by(&:container_path)
      existing = target_service.backup_schedules.index_by do |schedule|
        [ schedule.backup_kind, schedule.storage_mount&.container_path, schedule.frequency ]
      end

      ServiceBlueprint.new(source_service).schedules.each do |schedule|
        key = [ schedule["kind"], schedule["containerPath"], schedule["frequency"] ]
        record = existing[key]
        if record
          record.update!(retention_count: schedule["retentionCount"], enabled: schedule["enabled"])
        else
          created = target_service.backup_schedules.create!(
            backup_kind: schedule["kind"],
            frequency: schedule["frequency"],
            retention_count: schedule["retentionCount"],
            enabled: schedule["enabled"],
            storage_mount: mounts[schedule["containerPath"]]
          )
          created.update_next_run!
        end
      end
    end

    # Links are reconciled across every service the two environments now share,
    # not just the ones that were added, so a link introduced on a service that
    # was otherwise already in sync still shows up.
    def remap_links!(_plan)
      target_ids = Service.where(environment_id: @target.id).pluck(:name, :id).to_h
      pairs = Service.where(environment_id: @source.id).pluck(:name, :id).each_with_object({}) do |(name, source_id), memo|
        target_id = target_ids[name]
        memo[source_id] = Service.find(target_id) if target_id
      end

      ServiceCopier.link_copies!(pairs)
    end

    def source_service_for(entry)
      source_service_named(entry.name) or raise ActiveRecord::RecordNotFound, "No service named #{entry.name} in #{@source.name}"
    end

    def target_service_for(entry)
      @target.services.find_by(name: entry.name) or raise ActiveRecord::RecordNotFound, "No service named #{entry.name} in #{@target.name}"
    end

    def source_service_named(name)
      @source.services.find_by(name: name)
    end

    def copied_host_path(mount, target_service)
      return mount["hostPath"] unless mount["kind"] == "volume"

      StorageMount.volume_name_for(target_service.dokku_app_name, mount["containerPath"])
    end

    def record_activity!(plan, added, updated)
      return unless plan.changes?

      ActivityEvent.create!(
        project: @target.project,
        service_name: @target.name,
        action: :rebuilt,
        message: "Synced #{@target.name} from #{@source.name}: " \
                 "#{added.size} added, #{updated.size} updated, #{plan.removed.size} left alone"
      )
    end

    def message_for(plan)
      return "Already in sync with #{@source.name}." unless plan.changes?

      parts = []
      parts << "#{plan.added.size} added" if plan.added.any?
      parts << "#{plan.edited.size} updated" if plan.edited.any?
      parts << "#{plan.removed.size} left alone (sync never deletes)" if plan.removed.any?
      parts.join(", ")
    end
end

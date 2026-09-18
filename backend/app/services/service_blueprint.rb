# frozen_string_literal: true

# A canonical, environment-independent view of a service's configuration.
#
# Duplicating a service into another environment and diffing two environments
# turn out to be the same problem twice: both need an answer to "what is this
# service, ignoring the environment it happens to live in?". `ServiceBlueprint`
# is that answer, so the copy path and the sync path can never disagree about
# what counts as configuration.
#
# Deliberately excluded, and why:
#
# - `dokku_app_name` and `webhook_token` are instance identities. A copy must
#   get its own or it would collide with the original on the Dokku host
#   (`Service#generate_dokku_app_name` only fills a *nil* attribute, so a naive
#   `dup` would carry the original name across).
# - `status` and `last_deployed`: a copy has never been deployed. Railway stages
#   duplicated services for review before anything ships, and so do we.
# - `canvas_x` / `canvas_y`: layout is per-environment state, handled by the
#   duplicator rather than by the shared configuration fingerprint.
# - `deployments`, `backups`, `service_metrics`: history and artifacts, not
#   configuration.
# - `postgres_pitr_config`: WAL archiving reads the original service's container
#   and writes into a destination that already holds its history, so a copy opts
#   in explicitly instead of inheriting it.
# - `process_types`: discovered by the first deploy, so comparing them would
#   report every freshly duplicated service as permanently drifted. The
#   duplicator copies the scaling rows anyway (they carry operator intent);
#   sync simply does not fingerprint them.
#
# Secrets never leave this object as values: `#differences_from` returns labels
# ("environment variable DATABASE_URL"), never the values that differ, because
# these payloads are rendered in the UI.
class ServiceBlueprint
  # Copied verbatim. `locked` is absent on purpose: a service locked against
  # deploys in production should not produce a copy that is also locked, and a
  # fresh environment is exactly where you want to try a deploy.
  ATTRIBUTES = %w[
    name service_type subtype docker_image version builder framework branch
    git_repo root_directory start_command port detected_port exposed
    maintenance_mode restart_policy restart_max_retries config
    config_overrides external_networks auto_deploy
  ].freeze

  LABELS = {
    "service_type" => "service type",
    "subtype" => "subtype",
    "docker_image" => "Docker image",
    "version" => "version",
    "builder" => "builder",
    "framework" => "framework",
    "branch" => "branch",
    "git_repo" => "repository",
    "root_directory" => "root directory",
    "start_command" => "start command",
    "port" => "port",
    "detected_port" => "detected port",
    "exposed" => "public networking",
    "maintenance_mode" => "maintenance mode",
    "restart_policy" => "restart policy",
    "restart_max_retries" => "restart retries",
    "config" => "build settings",
    "config_overrides" => "config overrides",
    "external_networks" => "external networks",
    "auto_deploy" => "auto deploy"
  }.freeze

  # Merged rather than replaced on sync: a target is allowed to carry extra build
  # settings, and blowing them away would be a silent downgrade.
  MERGEABLE_ATTRIBUTES = %w[config config_overrides].freeze

  attr_reader :service

  def initialize(service)
    @service = service
  end

  # Attributes for a new row in another environment. Everything the caller must
  # supply itself (project, environment, identity, layout, status) is absent.
  def attributes
    ATTRIBUTES.each_with_object({}) do |attribute, memo|
      memo[attribute] = service.public_send(attribute)
    end
  end

  # Operator-managed variables only. `StorageMountEnvSync` writes
  # `RAILDOCK_STORAGE_*` rows flagged `is_dokku_internal`, and those are
  # regenerated from the copied mounts on the next deploy.
  # `source` records where a variable came from (a template, a link, the UI) and
  # travels with the copy so provenance survives; it is *not* part of the
  # fingerprint, because a variable typed by hand in one environment and seeded
  # by a template in the other is the same configuration.
  def variables
    service.environment_variables
      .reject(&:is_dokku_internal)
      .map { |variable| { "key" => variable.key, "value" => variable.value, "source" => variable.source } }
      .sort_by { |variable| variable["key"].to_s }
  end

  # Volume *names* are per-service (`<dokku-app>-data`), so two environments can
  # never share one and comparing them would report permanent drift. A volume is
  # therefore identified by the container path it is mounted at; a bind mount
  # carries the operator's explicit host path and so keeps it in the identity.
  def mounts
    service.storage_mounts.map do |mount|
      entry = { "kind" => mount.kind, "containerPath" => mount.container_path }
      entry["hostPath"] = mount.host_path unless mount.kind_volume?
      entry
    end.sort_by { |mount| [ mount["containerPath"].to_s, mount["kind"].to_s ] }
  end

  # Schedules are per-environment because the artifact they produce must be
  # restorable *into* that environment. A volume schedule is keyed by the
  # mount's container path for the same reason mounts are.
  def schedules
    service.backup_schedules.includes(:storage_mount).map do |schedule|
      {
        "kind" => schedule.backup_kind,
        "frequency" => schedule.frequency,
        "retentionCount" => schedule.retention_count,
        "enabled" => schedule.enabled,
        "containerPath" => schedule.storage_mount&.container_path
      }
    end.sort_by { |schedule| [ schedule["kind"].to_s, schedule["containerPath"].to_s, schedule["frequency"].to_s ] }
  end

  # Outgoing links named by the *target service's name* rather than by id, so
  # the same link in two environments compares equal.
  def links
    service.outgoing_links.includes(:to_service).map { |link| link.to_service&.name }.compact.sort
  end

  # What the target is missing or has drifted on, expressed as labels an
  # operator can read. Directional on purpose: sync only ever adds or updates,
  # so something the target has and this environment does not is not drift — a
  # staging-only variable or a staging-only extra build setting is exactly what
  # environments are for.
  def differences_from(other)
    labels = []

    ATTRIBUTES.each do |attribute|
      next if attribute == "name"
      next if attribute_matches?(attribute, other)

      labels << LABELS.fetch(attribute, attribute.tr("_", " "))
    end

    other_variables = other.variables.index_by { |variable| variable["key"] }
    variables.each do |variable|
      target = other_variables[variable["key"]]
      next if target && target["value"] == variable["value"]

      labels << "environment variable #{variable["key"]}"
    end

    other_mounts = other.mounts.index_by { |mount| [ mount["kind"], mount["containerPath"] ] }
    mounts.each do |mount|
      target = other_mounts[[ mount["kind"], mount["containerPath"] ]]
      next if target && target["hostPath"] == mount["hostPath"]

      labels << "mount #{mount["containerPath"]}"
    end

    other_schedules = other.schedules.index_by { |schedule| schedule_key(schedule) }
    schedules.each do |schedule|
      target = other_schedules[schedule_key(schedule)]
      next if target &&
              target["retentionCount"] == schedule["retentionCount"] &&
              target["enabled"] == schedule["enabled"]

      labels << "backup schedule (#{schedule["kind"]})"
    end

    other_links = other.links.to_set
    links.each do |link|
      labels << "link to #{link}" unless other_links.include?(link)
    end

    labels.uniq.sort
  end

  def in_sync_with?(other)
    differences_from(other).empty?
  end

  private
    def schedule_key(schedule)
      [ schedule["kind"], schedule["containerPath"], schedule["frequency"] ]
    end

    def attribute_matches?(attribute, other)
      mine = service.public_send(attribute)
      theirs = other.service.public_send(attribute)

      if MERGEABLE_ATTRIBUTES.include?(attribute)
        subset_of?(mine, theirs)
      else
        deep_sort(mine) == deep_sort(theirs)
      end
    end

    # `config` and `config_overrides` are merged on sync, so only the keys this
    # environment actually sets have to match.
    def subset_of?(mine, theirs)
      return deep_sort(mine) == deep_sort(theirs) unless mine.is_a?(Hash)

      mine.all? do |key, value|
        theirs.is_a?(Hash) && theirs.key?(key) && subset_of?(value, theirs[key])
      end
    end

    # jsonb round-trips through a hash whose key order is not meaningful, so
    # sort recursively before comparing or hashing.
    def deep_sort(value)
      case value
      when Hash then value.sort_by { |key, _| key.to_s }.to_h { |key, nested| [ key.to_s, deep_sort(nested) ] }
      when Array then value.map { |element| deep_sort(element) }
      when BigDecimal then value.to_s
      else value
      end
    end
end

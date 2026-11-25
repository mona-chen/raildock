require "shellwords"

# Syncs service config changes to Dokku immediately.
# Called after a service is updated in the DB.
# Only applies settings that can be changed without a full redeploy.
# Settings requiring redeploy (builder, docker options) are flagged but not auto-applied here.
class ServiceSettingsSync
  class ApplyError < StandardError; end

  # Dokku reports command failures as values. Never let those become a successful
  # HTTP response merely because the SSH transport itself did not raise.
  class CheckedEngine
    def initialize(engine)
      @engine = engine
    end

    def method_missing(name, *args, **kwargs, &block)
      result = @engine.public_send(name, *args, **kwargs, &block)
      if result.is_a?(Hash) && result[:success] == false
        raise ApplyError, "Settings were saved, but Dokku could not apply #{name.to_s.humanize.downcase}. Review the host configuration and retry."
      end
      result
    end

    def respond_to_missing?(name, include_private = false)
      @engine.respond_to?(name, include_private) || super
    end
  end

  def initialize(service, engine)
    @service = service
    @engine = CheckedEngine.new(engine)
    @app_name = service.dokku_app_name
  end

  def sync_config_changes!
    old_config = @service.config_before_last_save || {}
    new_config = @service.config || {}

    sync_proxy(old_config, new_config)
    sync_checks(old_config, new_config)
    sync_cron(old_config, new_config)
    sync_resource_limits(old_config, new_config)
    sync_resource_reservations(old_config, new_config)
    sync_traefik_labels(old_config, new_config)
    sync_letsencrypt(old_config, new_config)
    sync_git_branch
    sync_maintenance_mode
  end

  private

  # ── Proxy ────────────────────────────────────
  def sync_proxy(old_config, new_config)
    old_proxy = old_config["proxy"] || {}
    new_proxy = new_config["proxy"] || {}

    if old_proxy["enabled"] != new_proxy["enabled"]
      if new_proxy["enabled"] == false
        @engine.proxy_disable(@app_name)
      else
        @engine.proxy_enable(@app_name)
      end
    end

    if old_proxy["proxyType"] != new_proxy["proxyType"] && new_proxy["proxyType"].present?
      @engine.proxy_set(@app_name, new_proxy["proxyType"])
    end

    sync_port_mappings(old_proxy["portMappings"] || [], new_proxy["portMappings"] || [])
  end

  def sync_port_mappings(old_mappings, new_mappings)
    old_set = old_mappings.map { |m| [ m["scheme"], m["hostPort"].to_s, m["containerPort"].to_s ] }.to_set
    new_set = new_mappings.map { |m| [ m["scheme"], m["hostPort"].to_s, m["containerPort"].to_s ] }.to_set

    (old_set - new_set).each do |scheme, host_port, container_port|
      @engine.ports_remove(@app_name, scheme, host_port, container_port)
    end

    (new_set - old_set).each do |scheme, host_port, container_port|
      @engine.ports_add(@app_name, scheme, host_port, container_port)
    end
  end

  # ── Checks ───────────────────────────────────
  def sync_checks(old_config, new_config)
    old_checks = old_config["checks"] || {}
    new_checks = new_config["checks"] || {}

    return if old_checks == new_checks

    mode = new_checks["mode"].presence || (new_checks["enabled"] == false ? "skipped" : "enabled")
    case mode
    when "disabled" then @engine.checks_disable(@app_name)
    when "skipped" then @engine.checks_skip(@app_name, *Array(new_checks["skipList"]))
    else @engine.checks_enable(@app_name)
    end

    retire = new_checks["waitToRetire"] || new_checks["wait_to_retire"]
    @engine.checks_set(@app_name, "wait-to-retire", retire) if retire.present?
    ManagedAppJson.new(@service, HostEngine.new(@service.project.server)).apply!
  end

  # ── Cron ─────────────────────────────────────
  def sync_cron(old_config, new_config)
    old_cron = old_config["cron"] || []
    new_cron = new_config["cron"] || []

    return if old_cron == new_cron

    ManagedAppJson.new(@service, HostEngine.new(@service.project.server)).apply!
  end

  # ── Resource Limits ──────────────────────────
  def sync_resource_limits(old_config, new_config)
    old_limits = old_config["resourceLimits"] || []
    new_limits = new_config["resourceLimits"] || []

    return if old_limits == new_limits

    (resource_entries(old_limits) + resource_entries(new_limits)).map { |row| row["processType"] }.uniq.each do |pt_name|
      @engine.resource_limit_clear(@app_name, pt_name)
    end

    resource_entries(new_limits).each do |res|
      @engine.resource_limit(
        @app_name,
        res["processType"],
        memory: res["memory"].presence,
        cpu: res["cpu"].presence,
        memory_swap: res["memorySwap"].presence,
        nvidia_gpu: res["nvidiaGpu"].presence
      )
    end
  end

  # ── Resource Reservations ────────────────────
  def sync_resource_reservations(old_config, new_config)
    old_res = old_config["resourceReservations"] || []
    new_res = new_config["resourceReservations"] || []

    return if old_res == new_res

    (resource_entries(old_res) + resource_entries(new_res)).map { |row| row["processType"] }.uniq.each do |pt_name|
      @engine.resource_reserve_clear(@app_name, pt_name)
    end

    resource_entries(new_res).each do |res|
      @engine.resource_reserve(
        @app_name,
        res["processType"],
        memory: res["memory"].presence,
        cpu: res["cpu"].presence
      )
    end
  end

  # ── Traefik Labels ───────────────────────────
  def sync_traefik_labels(old_config, new_config)
    old_traefik = old_config["traefik"] || {}
    new_traefik = new_config["traefik"] || {}

    old_labels = old_traefik["labels"] || {}
    new_labels = new_traefik["labels"] || {}

    return if old_labels == new_labels

    old_labels.each do |key, _|
      if new_labels[key] != old_labels[key]
        @engine.run("traefik:labels:remove #{escape(@app_name)} #{escape(key)}")
      end
    end

    new_labels.each do |key, value|
      if old_labels[key] != value
        @engine.run("traefik:labels:add #{escape(@app_name)} #{escape(key)} #{escape(value)}")
      end
    end
  end

  # ── Let's Encrypt ────────────────────────────
  def sync_letsencrypt(old_config, new_config)
    old_le = old_config["letsencrypt"] || {}
    new_le = new_config["letsencrypt"] || {}

    if old_le["enabled"] != new_le["enabled"]
      if new_le["enabled"]
        @engine.letsencrypt_enable(@app_name, new_le["email"].presence)
      else
        @engine.letsencrypt_disable(@app_name)
      end
    elsif new_le["enabled"] && old_le["email"] != new_le["email"] && new_le["email"].present?
      @engine.letsencrypt_enable(@app_name, new_le["email"])
    end
  end

  # ── Git Branch ───────────────────────────────
  def sync_git_branch
    return unless @service.saved_change_to_attribute?(:branch)
    @engine.git_set_deploy_branch(@app_name, @service.branch || "main")
  end

  # ── Maintenance Mode ─────────────────────────
  def sync_maintenance_mode
    return unless @service.saved_change_to_attribute?(:maintenance_mode)
    if @service.maintenance_mode
      @engine.maintenance_enable(@app_name)
    else
      @engine.maintenance_disable(@app_name)
    end
  end

  def resource_entries(value)
    if value.is_a?(Hash)
      value.map { |process, settings| settings.stringify_keys.merge("processType" => process) }
    else
      Array(value).map(&:stringify_keys)
    end
  end

  def escape(value)
    Shellwords.escape(value.to_s)
  end
end

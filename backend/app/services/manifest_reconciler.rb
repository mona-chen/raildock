# frozen_string_literal: true

# Compares a manifest's desired state against the actual state of a project's services,
# producing a list of classified changes ready for application.
class ManifestReconciler
  attr_reader :project, :desired, :actual, :changes

  # Represents a single change between desired and actual state
  class Change
    attr_reader :service_name, :field, :change_type, :old_value, :new_value, :severity

    def initialize(service_name:, field:, change_type:, old_value:, new_value:)
      @service_name = service_name
      @field = field
      @change_type = change_type
      @old_value = old_value
      @new_value = new_value
      @severity = ChangeClassifier.classify(field)
    end

    def to_h
      {
        service_name: @service_name,
        field: @field,
        change_type: @change_type,
        old_value: @old_value,
        new_value: @new_value,
        severity: @severity
      }
    end
  end

  def initialize(project, desired_state)
    @project = project
    @desired = desired_state
    @actual = build_actual_state
    @changes = []
  end

  # Compute the full diff between desired and actual state
  def diff
    @changes = []

    # Services to create, update, or destroy
    desired_names = @desired.service_names.to_set
    actual_names = @actual.keys.to_set

    # Services to create
    (desired_names - actual_names).each do |name|
      svc = @desired.find_service(name)
      @changes << Change.new(
        service_name: name,
        field: :service,
        change_type: :added,
        old_value: nil,
        new_value: svc
      )
    end

    # Services to destroy
    (actual_names - desired_names).each do |name|
      svc = @actual[name]
      next if svc[:managed_by] == "ui" # Don't destroy UI-managed services
      @changes << Change.new(
        service_name: name,
        field: :service,
        change_type: :removed,
        old_value: svc,
        new_value: nil
      )
    end

    # Services to update
    (desired_names & actual_names).each do |name|
      diff_service(name, @desired.find_service(name), @actual[name])
    end

    # Links diff
    diff_links

    @changes
  end

  # Apply all computed changes via DokkuEngine
  def apply!(engine = nil)
    raise "No changes computed. Call diff first." if @changes.empty? && @changes != []

    engine ||= build_engine
    return { success: false, error: "No Dokku engine available" } unless engine

    results = []
    grouped = ChangeClassifier.group_by_severity(@changes)

    # Phase 1: Create new services (databases first)
    create_services = @changes.select { |c| c.change_type == :added && c.field == :service }
    create_services.sort_by { |c| c.new_value[:category] == "database" ? 0 : 1 }.each do |change|
      results << apply_create_service(engine, change)
    end

    # Phase 2: Reload changes (parallel-friendly)
    (grouped[:reload] || []).each do |change|
      results << apply_reload_change(engine, change)
    end

    # Phase 3: Restart changes
    (grouped[:restart] || []).each do |change|
      results << apply_restart_change(engine, change)
    end

    # Phase 4: Redeploy changes
    (grouped[:redeploy] || []).each do |change|
      results << apply_redeploy_change(engine, change)
    end

    # Phase 5: Links
    link_changes = @changes.select { |c| c.field == :link }
    link_changes.each do |change|
      results << apply_link_change(engine, change)
    end

    # Phase 6: Destroy services
    destroy_services = @changes.select { |c| c.change_type == :removed && c.field == :service }
    destroy_services.each do |change|
      results << apply_destroy_service(engine, change)
    end

    { success: results.all? { |r| r[:success] }, results: results }
  end

  private

  # ── Build actual state from DB ──────────────────────────────

  def build_actual_state
    state = {}
    @project.services.includes(:environment_variables, :domains, :storage_mounts, :process_types, :outgoing_links).find_each do |svc|
      state[svc.name] = {
        id: svc.id,
        name: svc.name,
        category: svc.service_type,
        subtype: svc.subtype,
        builder: svc.builder,
        managed_by: svc.managed_by,
        git_repo: svc.git_repo,
        branch: svc.branch,
        docker_image: svc.docker_image,
        version: svc.version,
        root_directory: svc.root_directory,
        start_command: svc.start_command,
        exposed: svc.exposed,
        port: svc.port,
        maintenance_mode: svc.maintenance_mode,
        restart_policy: svc.restart_policy,
        restart_max_retries: svc.restart_max_retries,
        auto_deploy: svc.auto_deploy,
        env: svc.environment_variables.map { |ev| [ev.key, ev.value] }.to_h,
        domains: svc.domains.map(&:hostname),
        storage: svc.storage_mounts.map { |sm| { host: sm.host_path, container: sm.container_path } },
        proxy: svc.config&.dig("proxy") || {},
        scaling: svc.process_types.map { |pt| [pt.name, pt.quantity] }.to_h,
        limits: svc.config&.dig("resourceLimits") || {},
        reservations: svc.config&.dig("resourceReservations") || {},
        checks: svc.config&.dig("checks") || {},
        cron: svc.config&.dig("cron") || [],
        docker_options: svc.config&.dig("dockerOptions") || [],
        traefik_labels: svc.config&.dig("traefik") || {},
        letsencrypt: svc.config&.dig("letsencrypt") || {},
        links: svc.linked_services.map(&:name)
      }
    end
    state
  end

  def build_engine
    server = @project.server
    return nil unless server&.ssh_key.present?
    DokkuEngine.new(server)
  end

  # ── Service diff ────────────────────────────────────────────

  def diff_service(name, desired_svc, actual_svc)
    # Skip UI-managed services unless explicitly included
    return if actual_svc[:managed_by] == "ui"

    fields = %i[
      category subtype builder git_repo branch docker_image version
      root_directory start_command exposed port maintenance_mode
      restart_policy restart_max_retries auto_deploy env domains
      storage proxy scaling limits reservations checks cron
      docker_options traefik_labels letsencrypt
    ]

    fields.each do |field|
      old_val = actual_svc[field]
      new_val = desired_svc[field]

      next if values_equal?(old_val, new_val)

      change_type = old_val.nil? ? :added : (new_val.nil? ? :removed : :modified)

      @changes << Change.new(
        service_name: name,
        field: field,
        change_type: change_type,
        old_value: old_val,
        new_value: new_val
      )
    end
  end

  def diff_links
    desired_links = @desired.links.map { |l| [l[:from], l[:to]].sort.join("->") }.to_set
    actual_links = Set.new

    @project.services.includes(:linked_services).find_each do |svc|
      svc.linked_services.each do |linked|
        actual_links << [svc.name, linked.name].sort.join("->")
      end
    end

    # Links to add
    (desired_links - actual_links).each do |link_key|
      from, to = link_key.split("->")
      @changes << Change.new(
        service_name: "#{from}->#{to}",
        field: :link,
        change_type: :added,
        old_value: nil,
        new_value: { from: from, to: to }
      )
    end

    # Links to remove (only for manifest-managed services)
    (actual_links - desired_links).each do |link_key|
      from, to = link_key.split("->")
      from_svc = @project.services.find_by(name: from)
      next unless from_svc&.managed_by_manifest?

      @changes << Change.new(
        service_name: "#{from}->#{to}",
        field: :link,
        change_type: :removed,
        old_value: { from: from, to: to },
        new_value: nil
      )
    end
  end

  def values_equal?(a, b)
    return true if a.nil? && b.nil?
    return false if a.nil? || b.nil?

    if a.is_a?(Hash) && b.is_a?(Hash)
      a.stringify_keys == b.stringify_keys
    elsif a.is_a?(Array) && b.is_a?(Array)
      a.map { |x| x.is_a?(Hash) ? x.stringify_keys : x } ==
        b.map { |x| x.is_a?(Hash) ? x.stringify_keys : x }
    else
      a == b
    end
  end

  # ── Application ─────────────────────────────────────────────

  def apply_create_service(engine, change)
    svc = change.new_value
    app_name = "#{@project.name.parameterize}-#{svc[:name].parameterize}"

    if svc[:category] == "database"
      result = create_database_service(engine, svc, app_name)
    else
      result = create_app_service(engine, svc, app_name)
    end

    # Persist to DB
    if result[:success]
      service = @project.services.create!(
        name: svc[:name],
        service_type: svc[:category],
        subtype: svc[:subtype],
        status: svc[:category] == "database" ? "running" : "stopped",
        builder: svc[:builder],
        git_repo: svc[:source]&.dig(:repo),
        branch: svc[:source]&.dig(:branch),
        docker_image: svc[:docker_image],
        version: svc[:version],
        root_directory: svc[:root_directory],
        start_command: svc[:start_command],
        exposed: svc[:exposed],
        port: svc[:port],
        maintenance_mode: svc[:maintenance] || false,
        dokku_app_name: app_name,
        managed_by: "manifest",
        config: build_config_from_desired(svc)
      )

      # Create env vars
      (svc[:env] || {}).each do |key, value|
        service.environment_variables.create!(key: key, value: value)
      end

      # Create domains
      (svc[:domains] || []).each do |hostname|
        service.domains.create!(hostname: hostname)
      end

      # Create storage mounts
      (svc[:storage] || []).each do |mount|
        service.storage_mounts.create!(host_path: mount[:host], container_path: mount[:container])
      end

      # Create process types for scaling
      (svc[:scaling] || {}).each do |pt_name, qty|
        service.process_types.create!(name: pt_name, quantity: qty, running: 0, command: "")
      end
    end

    result
  rescue => e
    Rails.logger.error "Failed to create service #{svc[:name]}: #{e.message}"
    { success: false, error: e.message, service: svc[:name] }
  end

  def create_database_service(engine, svc, app_name)
    result = case svc[:subtype]
    when "postgres" then engine.postgres_create(app_name)
    when "redis" then engine.redis_create(app_name)
    when "mysql" then engine.mysql_create(app_name)
    when "mongo" then engine.mongo_create(app_name)
    else
      { success: false, error: "Unknown database subtype: #{svc[:subtype]}" }
    end
    result
  end

  def create_app_service(engine, svc, app_name)
    engine.app_create(app_name)
    proxy_type = svc.dig(:proxy, :type) || "traefik"
    engine.proxy_set(app_name, proxy_type)
    { success: true }
  end

  def apply_destroy_service(engine, change)
    svc = change.old_value
    app_name = "#{@project.name.parameterize}-#{svc[:name].parameterize}"

    if svc[:category] == "database"
      case svc[:subtype]
      when "postgres" then engine.postgres_destroy(app_name)
      when "redis" then engine.redis_destroy(app_name)
      when "mysql" then engine.mysql_destroy(app_name)
      when "mongo" then engine.mongo_destroy(app_name)
      end
    else
      engine.app_destroy(app_name)
    end

    # Destroy DB record
    db_svc = @project.services.find_by(name: svc[:name])
    db_svc&.destroy!

    { success: true, service: svc[:name] }
  rescue => e
    Rails.logger.error "Failed to destroy service #{svc[:name]}: #{e.message}"
    { success: false, error: e.message, service: svc[:name] }
  end

  def apply_reload_change(engine, change)
    service = @project.services.find_by(name: change.service_name)
    return { success: false, error: "Service not found" } unless service

    case change.field
    when :env
      apply_env_change(engine, service, change)
    when :domains
      apply_domains_change(engine, service, change)
    when :storage
      apply_storage_change(engine, service, change)
    when :proxy
      apply_proxy_change(engine, service, change)
    when :traefik_labels
      apply_traefik_change(engine, service, change)
    when :letsencrypt
      apply_letsencrypt_change(engine, service, change)
    when :maintenance_mode
      apply_maintenance_change(engine, service, change)
    else
      { success: true, note: "No-op for field #{change.field}" }
    end
  end

  def apply_restart_change(engine, change)
    service = @project.services.find_by(name: change.service_name)
    return { success: false, error: "Service not found" } unless service

    case change.field
    when :scaling
      apply_scaling_change(engine, service, change)
    when :checks
      apply_checks_change(engine, service, change)
    when :cron
      apply_cron_change(engine, service, change)
    when :limits, :reservations
      apply_resource_change(engine, service, change)
    else
      { success: true, note: "No-op for field #{change.field}" }
    end
  end

  def apply_redeploy_change(engine, change)
    service = @project.services.find_by(name: change.service_name)
    return { success: false, error: "Service not found" } unless service

    # Update DB record
    update_service_from_change(service, change)

    # Trigger deployment if it's an app
    if service.service_type_app?
      DeploymentJob.perform_later(service.id, nil)
      { success: true, note: "Deployment queued" }
    else
      { success: true, note: "Updated (no deploy for non-app)" }
    end
  end

  def apply_link_change(engine, change)
    from_svc = @project.services.find_by(name: change.new_value&.dig(:from) || change.old_value&.dig(:from))
    to_svc = @project.services.find_by(name: change.new_value&.dig(:to) || change.old_value&.dig(:to))
    return { success: false, error: "Service not found" } unless from_svc && to_svc

    if change.change_type == :added
      # Create DB link
      ServiceLink.create!(from_service: from_svc, to_service: to_svc)
      # Dokku link
      if to_svc.service_type_database?
        link_result = engine.send("#{to_svc.subtype}_link", to_svc.dokku_app_name, from_svc.dokku_app_name)
        unless link_result[:success]
          Rails.logger.error "Dokku link failed for #{from_svc.name} -> #{to_svc.name}: #{link_result[:output]}"
          return { success: false, error: link_result[:output] }
        end
        # Disable SSL cert validation for internal postgres connections
        if to_svc.subtype == "postgres"
          engine.config_set(from_svc.dokku_app_name, "PGSSLMODE", "disable")
        end
        # Sync injected env vars and rewrite placeholder connection URLs
        rewrite_linked_db_urls(engine, from_svc, to_svc)
      end
      { success: true }
    elsif change.change_type == :removed
      # Remove DB link
      ServiceLink.find_by(from_service: from_svc, to_service: to_svc)&.destroy!
      # Dokku unlink
      if to_svc.service_type_database?
        engine.send("#{to_svc.subtype}_unlink", to_svc.dokku_app_name, from_svc.dokku_app_name) rescue nil
      end
      { success: true }
    end
  rescue => e
    Rails.logger.error "Link change failed: #{e.message}"
    { success: false, error: e.message }
  end

  # ── Field-specific apply helpers ────────────────────────────

  def apply_env_change(engine, service, change)
    desired = change.new_value || {}
    actual = change.old_value || {}

    # Set new / changed
    (desired.keys - actual.keys).each do |key|
      resolved = ManifestParser.resolve_runtime(desired[key], @project, service, service.linked_services)
      engine.config_set(service.dokku_app_name, key, resolved)
      service.environment_variables.find_or_initialize_by(key: key).update!(value: resolved)
    end

    (desired.keys & actual.keys).each do |key|
      next if desired[key] == actual[key]
      resolved = ManifestParser.resolve_runtime(desired[key], @project, service, service.linked_services)
      engine.config_set(service.dokku_app_name, key, resolved)
      service.environment_variables.find_by(key: key)&.update!(value: resolved)
    end

    # Unset removed
    (actual.keys - desired.keys).each do |key|
      engine.run("config:unset #{engine.escape(service.dokku_app_name)} #{engine.escape(key)}")
      service.environment_variables.find_by(key: key)&.destroy!
    end

    { success: true }
  end

  def apply_domains_change(engine, service, change)
    desired = change.new_value || []
    actual = change.old_value || []

    (desired - actual).each do |hostname|
      engine.domain_add(service.dokku_app_name, hostname)
      service.domains.find_or_initialize_by(hostname: hostname).save!
    end

    (actual - desired).each do |hostname|
      engine.run("domains:remove #{engine.escape(service.dokku_app_name)} #{engine.escape(hostname)}")
      service.domains.find_by(hostname: hostname)&.destroy!
    end

    { success: true }
  end

  def apply_storage_change(engine, service, change)
    desired = change.new_value || []
    actual = change.old_value || []

    desired_map = desired.map { |d| [d[:host], d[:container]] }
    actual_map = actual.map { |a| [a[:host], a[:container]] }

    (desired - actual).each do |mount|
      engine.storage_mount(service.dokku_app_name, mount[:host], mount[:container])
      service.storage_mounts.find_or_initialize_by(host_path: mount[:host], container_path: mount[:container]).save!
    end

    (actual - desired).each do |mount|
      engine.run("storage:unmount #{engine.escape(service.dokku_app_name)} #{engine.escape(mount[:container])}")
      service.storage_mounts.find_by(host_path: mount[:host], container_path: mount[:container])&.destroy!
    end

    { success: true }
  end

  def apply_proxy_change(engine, service, change)
    proxy = change.new_value || {}
    if proxy[:enabled] == false
      engine.proxy_disable(service.dokku_app_name)
    else
      engine.proxy_enable(service.dokku_app_name)
      engine.proxy_set(service.dokku_app_name, proxy[:type] || "traefik") if proxy[:type]
    end

    service.config = (service.config || {}).merge("proxy" => proxy.deep_stringify_keys)
    service.save!
    { success: true }
  end

  def apply_traefik_change(engine, service, change)
    labels = change.new_value || {}
    service.config = (service.config || {}).merge("traefik" => labels.deep_stringify_keys)
    service.save!

    # Apply as docker options labels
    labels.each do |key, value|
      engine.docker_option_add(service.dokku_app_name, "deploy", "--label=#{key}=#{value}")
    end
    { success: true }
  end

  def apply_letsencrypt_change(engine, service, change)
    le = change.new_value || {}
    if le[:enabled]
      engine.run("letsencrypt:enable #{engine.escape(service.dokku_app_name)}")
    else
      engine.run("letsencrypt:disable #{engine.escape(service.dokku_app_name)}")
    end

    service.config = (service.config || {}).merge("letsencrypt" => le.deep_stringify_keys)
    service.save!
    { success: true }
  end

  def apply_maintenance_change(engine, service, change)
    if change.new_value
      engine.maintenance_enable(service.dokku_app_name)
    else
      engine.maintenance_disable(service.dokku_app_name)
    end
    service.update!(maintenance_mode: change.new_value)
    { success: true }
  end

  def apply_scaling_change(engine, service, change)
    desired = change.new_value || {}
    desired.each do |process_type, quantity|
      engine.ps_scale(service.dokku_app_name, process_type, quantity)
      pt = service.process_types.find_or_initialize_by(name: process_type)
      pt.update!(quantity: quantity)
    end
    { success: true }
  end

  def apply_checks_change(engine, service, change)
    checks = change.new_value || {}
    service.config = (service.config || {}).merge("checks" => checks.deep_stringify_keys)
    service.save!

    if checks[:enabled] == false
      engine.run("checks:disable #{engine.escape(service.dokku_app_name)}")
    else
      engine.run("checks:enable #{engine.escape(service.dokku_app_name)}")
    end
    { success: true }
  end

  def apply_cron_change(engine, service, change)
    cron = change.new_value || []
    service.config = (service.config || {}).merge("cron" => cron.map(&:deep_stringify_keys))
    service.save!
    # Dokku cron is handled via app.json or docker options; for now we just store in config
    # A full implementation would write app.json to the repo or use the cron plugin
    { success: true, note: "Cron schedules updated in config. Restart may be needed for Dokku to pick them up." }
  end

  def apply_resource_change(engine, service, change)
    limits = change.new_value || {}
    key = change.field == :limits ? "resourceLimits" : "resourceReservations"
    service.config = (service.config || {}).merge(key => limits.deep_stringify_keys)
    service.save!

    limits.each do |process_type, cfg|
      engine.resource_limit(
        service.dokku_app_name,
        process_type,
        memory: cfg[:memory],
        cpu: cfg[:cpu],
        nvidia_gpu: cfg[:nvidia_gpu]
      )
    end
    { success: true }
  end

  def update_service_from_change(service, change)
    case change.field
    when :builder then service.update!(builder: change.new_value)
    when :docker_image then service.update!(docker_image: change.new_value)
    when :git_repo then service.update!(git_repo: change.new_value)
    when :branch then service.update!(branch: change.new_value)
    when :root_directory then service.update!(root_directory: change.new_value)
    when :start_command then service.update!(start_command: change.new_value)
    when :exposed then service.update!(exposed: change.new_value)
    when :port then service.update!(port: change.new_value)
    when :version then service.update!(version: change.new_value)
    when :subtype then service.update!(subtype: change.new_value)
    when :category then service.update!(service_type: change.new_value)
    end
  end

  def build_config_from_desired(svc)
    config = {}
    config["proxy"] = svc[:proxy] if svc[:proxy]
    config["checks"] = svc[:checks] if svc[:checks]
    config["cron"] = svc[:cron] if svc[:cron]
    config["dockerOptions"] = svc[:docker_options] if svc[:docker_options]
    config["resourceLimits"] = svc[:limits] if svc[:limits]
    config["resourceReservations"] = svc[:reservations] if svc[:reservations]
    config["traefik"] = svc[:traefik_labels] if svc[:traefik_labels]
    config["letsencrypt"] = svc[:letsencrypt] if svc[:letsencrypt]
    config
  end

  # After a database link, sync the injected DATABASE_URL / REDIS_URL etc. from
  # Dokku into our DB, then rewrite any env vars on the app that look like
  # connection URLs (e.g. CODER_PG_CONNECTION_URL) to use the real credentials.
  def rewrite_linked_db_urls(engine, app_service, db_service)
    db_url_map = {
      "postgres" => [ "DATABASE_URL", /\Apostgres(?:ql)?:\/\//i ],
      "redis"    => [ "REDIS_URL",    /\Aredis:\/\//i ],
      "mysql"    => [ "MYSQL_URL",    /\Amysql:\/\//i ],
      "mongo"    => [ "MONGO_URL",    /\Amongodb(?:\+srv)?:\/\//i ]
    }.freeze

    mapping = db_url_map[db_service.subtype]
    return unless mapping

    url_var, url_pattern = mapping

    # Fetch current Dokku config for the app
    result = engine.config_show(app_service.dokku_app_name)
    return unless result[:success]

    # Find and store the injected URL
    url_value = nil
    result[:output].each_line do |line|
      next unless line.include?(":")
      key, value = line.split(":", 2)
      next unless key && value
      key = key.strip
      value = value.strip
      if key == url_var
        url_value = value
        break
      end
    end

    return if url_value.blank?

    # Persist the injected URL in our DB
    app_service.environment_variables.find_or_initialize_by(key: url_var).tap do |ev|
      ev.value = url_value
      ev.is_dokku_internal = true
      ev.source = "dokku-link"
      ev.save!
    end

    # Rewrite any other env var whose value looks like a connection URL
    # for this database type to use the actual injected URL
    app_service.environment_variables.where.not(key: url_var).each do |ev|
      next unless ev.value.match?(url_pattern)

      engine.config_set(app_service.dokku_app_name, ev.key, url_value)
      ev.update!(value: url_value)
      Rails.logger.info "Rewrote #{ev.key} on #{app_service.dokku_app_name} to use actual #{db_service.subtype} credentials from #{url_var}"
    end
  end
end

# frozen_string_literal: true

# Shared logic for Dokku service link setup across template deploys,
# manifest reconciliation, and direct deployments.
#
# Consolidates:
# - Syncing Dokku-injected env vars (DATABASE_URL, REDIS_URL, etc.) to DB
# - Overwriting placeholder credentials with real values from the DSN
# - Setting PGSSLMODE for Postgres links
# - Ensuring network aliases on the project network
class ServiceLinkSetup
  DB_URL_MAP = {
    "postgres" => [ "DATABASE_URL", /\Apostgres(?:ql)?:\/\//i ],
    "redis"    => [ "REDIS_URL",    /\Aredis:\/\//i ],
    "mysql"    => [ "DATABASE_URL", /\Amysql:\/\//i ],
    "mariadb"  => [ "DATABASE_URL", /\Amysql:\/\//i ],
    "mongo"    => [ "MONGO_URL",    /\Amongodb(?:\+srv)?:\/\//i ]
  }.freeze

  def initialize(project, engine, host_engine: nil)
    @project = project
    @engine = engine
    @host_engine = host_engine || HostEngine.new(project.server)
  end

  # Full per-link setup: PGSSLMODE, env sync, and credential rewrite.
  def setup!(app_service, db_service)
    if db_service.subtype == "postgres"
      result = @engine.config_set(app_service.dokku_app_name, "PGSSLMODE", "disable")
      return { success: false, error: result[:output] } unless result[:success]
      app_service.environment_variables.find_or_initialize_by(key: "PGSSLMODE").update!(value: "disable")
    end

    sync_result = sync_env_vars(app_service, db_service)
    return sync_result unless sync_result[:success]

    rewrite_from_dsn(app_service, db_service)
  end

  # Read Dokku-injected URL vars from config_show and persist to DB.
  def sync_env_vars(app_service, db_service)
    result = @engine.config_show(app_service.dokku_app_name)
    return { success: false, error: result[:output] } unless result[:success]

    result[:output].each_line do |line|
      line = line.strip
      next unless line.include?("=")
      key, _, value = line.partition("=")
      key = key.strip
      value = value.strip
      next unless key.match?(/^(DATABASE_URL|REDIS_URL|MONGO_URL|MYSQL_URL|DATABASE_PRIVATE_URL|REDIS_PRIVATE_URL|DOKKU_MYSQL|DOKKU_POSTGRES|DOKKU_REDIS|DOKKU_MONGO)/i)
      next if value.blank? || value.start_with?("$")

      existing = app_service.environment_variables.find_by(key: key)
      if existing
        existing.update!(value: value) if existing.value != value
      else
        app_service.environment_variables.create!(key: key, value: value, source: "dokku-link")
      end
    end

    url_var = DB_URL_MAP[db_service.subtype]&.first
    return { success: true } unless url_var

    url_value = find_config_value(result[:output], url_var)
    if url_value.present?
      app_service.environment_variables.find_or_initialize_by(key: url_var).tap do |ev|
        ev.value = url_value
        ev.is_dokku_internal = true
        ev.source = "dokku-link"
        ev.save!
      end
    end

    { success: true }
  end

  # Overwrite placeholder env vars with real values from the Dokku DSN.
  def rewrite_from_dsn(app_service, db_service)
    info_method = "#{db_service.subtype}_info"
    return { success: true } unless @engine.respond_to?(info_method)

    info = @engine.send(info_method, db_service.dokku_app_name)
    return { success: false, error: "Unable to read #{db_service.subtype} connection URL" } unless info[:success] && info[:dsn].present?

    dsn = info[:dsn]
    url_var = DB_URL_MAP[db_service.subtype]&.first
    return { success: true } unless url_var

    set_result = @engine.config_set(app_service.dokku_app_name, url_var, dsn)
    return { success: false, error: set_result[:output] } unless set_result[:success]

    ev = app_service.environment_variables.find_or_initialize_by(key: url_var)
    ev.update!(value: dsn, source: "dokku-link")

    uri = URI.parse(dsn)
    host = uri.host
    user = uri.user
    password = uri.password
    port = uri.port&.to_s
    db_name = uri.path.to_s.delete_prefix("/")
    subtype_up = db_service.subtype.upcase

    app_service.environment_variables.where(value: db_service.name).each do |ev|
      next if ev.key == url_var
      set_result = @engine.config_set(app_service.dokku_app_name, ev.key, host)
      return { success: false, error: set_result[:output] } unless set_result[:success]
      ev.update!(value: host)
    end

    app_service.environment_variables.each do |ev|
      key_up = ev.key.upcase
      next unless key_up.include?("DATABASE") || key_up.include?(subtype_up)

      rewrite_value = if key_up.end_with?("_USER") || key_up.end_with?("_USERNAME")
        user if user.present?
      elsif key_up.end_with?("_PASSWORD") || key_up.end_with?("_PASS")
        password if password.present?
      elsif key_up.end_with?("_PORT")
        port if port.present?
      elsif key_up.end_with?("_DATABASE") || key_up.end_with?("_DB") || (key_up.end_with?("_NAME") && key_up.include?("DATABASE"))
        db_name if db_name.present?
      end

      next if rewrite_value.blank?

      set_result = @engine.config_set(app_service.dokku_app_name, ev.key, rewrite_value)
      return { success: false, error: set_result[:output] } unless set_result[:success]
      ev.update!(value: rewrite_value)
    end

    { success: true }
  end

  # Connect both linked containers to the project network with service name aliases.
  def ensure_network_aliases(app_service, db_service)
    network_manager = ProjectNetworkManager.new(@project, @engine)
    network_manager.ensure_network!

    [ db_service, app_service ].each do |svc|
      container = @host_engine.dokku_container_name(svc.dokku_app_name)
      next unless container.present?
      alias_name = svc.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
      network_manager.connect_container_with_aliases(container, [ alias_name ], wait: false)
    end
  rescue => e
    Rails.logger.warn "Failed to ensure network aliases for #{app_service.name} -> #{db_service.name}: #{e.message}"
  end

  # Safety net: ensure all linked datastore containers are on the project network.
  def ensure_db_network_aliases(linked_dbs)
    return if linked_dbs.empty?

    network_manager = ProjectNetworkManager.new(@project, @engine)
    network_manager.ensure_network!

    linked_dbs.each do |db|
      container = @host_engine.dokku_container_name(db.dokku_app_name)
      next unless container.present?
      alias_name = db.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
      result = network_manager.connect_container_with_aliases(container, [ alias_name ], wait: false)
      Rails.logger.warn "Failed to connect #{container}: #{result[:output]}" unless result[:success]
    end
  rescue => e
    Rails.logger.warn "Failed to ensure datastore network aliases: #{e.message}"
  end

  private

  def find_config_value(config_output, key)
    config_output.each_line do |line|
      separator = line.include?("=") ? "=" : ":"
      next unless line.include?(separator)
      k, v = line.split(separator, 2)
      return v.strip if k&.strip == key
    end
    nil
  end
end

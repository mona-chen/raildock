class PostgresPitrConfigurator
  ARCHIVE_DIRECTORY = "/var/lib/postgresql/data/raildock_wal_archive".freeze

  def initialize(config)
    @config = config
    @service = config.service
    @host = HostEngine.new(@service.project.server)
  end

  def enable!
    container = container_name
    commands = [
      "mkdir -p #{ARCHIVE_DIRECTORY} && chown postgres:postgres #{ARCHIVE_DIRECTORY}",
      %(psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET wal_level = 'replica'"),
      %(psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET archive_mode = 'on'"),
      %(psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET archive_timeout = '60s'"),
      %(psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET archive_command = 'test ! -f #{ARCHIVE_DIRECTORY}/%f && cp %p #{ARCHIVE_DIRECTORY}/%f'")
    ]
    commands.each do |command|
      result = @host.run("docker exec #{Shellwords.escape(container)} sh -lc #{Shellwords.escape(command)}")
      raise result[:output].presence || "Could not configure PostgreSQL WAL archiving" unless result[:success]
    end

    result = DokkuEngine.new(@service.project.server).run("postgres:restart #{Shellwords.escape(@service.dokku_app_name)}")
    raise result[:output].presence || "Could not restart PostgreSQL" unless result[:success]

    @config.update!(enabled: true, status: "active", last_error: nil)
  rescue => error
    @config.update!(status: "error", last_error: error.message)
    raise
  end

  def disable!
    container = container_name
    command = %(psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET archive_mode = 'off'" -c "ALTER SYSTEM RESET archive_command")
    result = @host.run("docker exec #{Shellwords.escape(container)} sh -lc #{Shellwords.escape(command)}")
    raise result[:output].presence || "Could not disable PostgreSQL WAL archiving" unless result[:success]

    restarted = DokkuEngine.new(@service.project.server).run("postgres:restart #{Shellwords.escape(@service.dokku_app_name)}")
    raise restarted[:output].presence || "Could not restart PostgreSQL" unless restarted[:success]

    @config.update!(enabled: false, status: "paused", last_error: nil)
  rescue => error
    @config.update!(status: "error", last_error: error.message)
    raise
  end

  private
    def container_name
      "dokku.postgres.#{@service.dokku_app_name}"
    end
end

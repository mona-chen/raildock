# Restarts a Dokku app and re-establishes network aliases for linked services.
# Used by ProjectsController#restart_all to avoid HTTP timeouts on synchronous
# multi-service restarts.
class RestartJob < ApplicationJob
  queue_as :default

  def perform(service_id)
    service = Service.find(service_id)
    project = service.project
    server = project.server

    return unless server&.ssh_key.present?

    engine = DokkuEngine.new(server)
    restart_success = false

    begin
      # Database plugin services need their own restart command
      if service.service_type_database?
        result = restart_database_service(engine, service)
      else
        result = engine.ps_restart(service.dokku_app_name)
      end

      if result[:success]
        restart_success = true
        service.update!(status: "running")
      else
        # Dokku often returns exit code 1 even when the container was created
        # successfully (e.g. builds dir permission warnings). Treat as success
        # if the container is actually running.
        container = HostEngine.new(server).dokku_container_name(service.dokku_app_name)
        if container.present?
          running = HostEngine.new(server).run("docker inspect -f '{{.State.Running}}' #{container} 2>/dev/null")
          if running[:output]&.strip == "true"
            restart_success = true
            service.update!(status: "running")
            Rails.logger.warn "Restart of #{service.dokku_app_name} reported failure but container is running"
          end
        end
      end

      # Always try to restore network aliases — Dokku restarts create new
      # containers, and aliases are not persisted by attach-post-create.
      begin
        network_manager = ProjectNetworkManager.new(project, engine)
        network_manager.connect_service(service)
        network_manager.ensure_linked_aliases(service)
        network_manager.inject_internal_hostnames(service)
      rescue => e
        Rails.logger.warn "Network alias restore failed for #{service.dokku_app_name}: #{e.message}"
      end

      if restart_success
        ActivityEvent.create!(
          project: project,
          service_name: service.name,
          action: :restarted,
          message: "Restarted #{service.name}"
        )
      else
        Rails.logger.error "Restart failed for #{service.dokku_app_name}: #{result[:output]}"
      end
    rescue => e
      Rails.logger.error "RestartJob exception for #{service.dokku_app_name}: #{e.message}"
    end
  end

  private

  def restart_database_service(engine, service)
    case service.subtype
    when "postgres"
      engine.run("postgres:restart #{service.dokku_app_name}")
    when "redis"
      engine.run("redis:restart #{service.dokku_app_name}")
    when "mysql"
      engine.run("mysql:restart #{service.dokku_app_name}")
    when "mongo"
      engine.run("mongo:restart #{service.dokku_app_name}")
    else
      { success: false, output: "Unknown database subtype: #{service.subtype}" }
    end
  end
end

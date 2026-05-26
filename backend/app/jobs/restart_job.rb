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
    host_engine = HostEngine.new(server)
    restart_success = false

    begin
      # Database plugin services need their own restart command
      if service.service_type_database?
        result = restart_database_service(engine, service)
        # Wait for database container to be ready
        wait_for_container(service.dokku_app_name, host_engine)
      else
        result = engine.ps_restart(service.dokku_app_name)
        # Wait for app container to be running after ps:restart
        wait_for_container(service.dokku_app_name, host_engine)
      end

      if result[:success]
        restart_success = true
        service.update!(status: "running")
      else
        # Dokku often returns exit code 1 even when the container was created
        # successfully (e.g. builds dir permission warnings). Treat as success
        # if the container is actually running.
        container = host_engine.wait_for_container(service.dokku_app_name, timeout: 60)
        if container.present? && host_engine.container_running?(container)
          restart_success = true
          service.update!(status: "running")
          Rails.logger.warn "Restart of #{service.dokku_app_name} reported failure but container is running"
        end
      end

      # Always try to restore network aliases — Dokku restarts create new
      # containers, and aliases are not persisted by attach-post-create.
      # Also restore aliases for ALL linked services (they may have restarted too).
      begin
        network_manager = ProjectNetworkManager.new(project, engine)
        restore_network_aliases(service, network_manager)
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

  def wait_for_container(app_name, host_engine, timeout: 60)
    container = host_engine.wait_for_container(app_name, timeout: timeout)
    unless container
      Rails.logger.warn "Container for #{app_name} not found after #{timeout}s wait"
      return nil
    end
    Rails.logger.info "Found container #{container} for #{app_name}"
    container
  end

  def restore_network_aliases(service, network_manager)
    # Restore aliases for the service itself
    network_manager.connect_service(service)

    # Restore aliases for any linked services (they may have restarted too)
    # and also update aliases for services that link TO this service
    restore_linked_services_aliases(service, network_manager)
    restore_reverse_linked_services_aliases(service, network_manager)

    network_manager.inject_internal_hostnames(service)
  end

  # When service A links to service B (A depends on B),
  # we need to ensure B's aliases are set so A can reach B
  def restore_linked_services_aliases(service, network_manager)
    return if service.linked_services.blank?

    service.linked_services.each do |linked|
      network_manager.ensure_linked_aliases(linked)
    end
  end

  # When service A links to service B, and we're restarting A,
  # we need to ensure A's aliases are set so B (or others) can reach A
  # Also, when service B (a linked target) restarts, we need to update
  # all services that link TO B to re-establish their aliases
  def restore_reverse_linked_services_aliases(service, network_manager)
    # Find all services that link TO this service (this service is the target)
    # For example, if autobase-api links to autobase-db, and we're restarting
    # autobase-db, we need to re-establish autobase-api's aliases
    linking_services = Service.where.not(id: service.id).select do |s|
      s.linked_services.any? { |linked| linked.id == service.id }
    end

    linking_services.each do |linking_service|
      # Re-establish this service's network aliases
      container = HostEngine.new(linking_service.project.server).dokku_container_name(linking_service.dokku_app_name)
      if container.present?
        alias_name = linking_service.name.to_s.downcase.gsub(/[^a-z0-9-]/, '-')
        network_manager.connect_container_with_aliases(container, [alias_name])
      end
    end
  end

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

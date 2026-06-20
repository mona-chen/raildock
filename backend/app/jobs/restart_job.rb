# Restarts a Dokku app and re-establishes network aliases for linked services.
# Creates a Deployment record of kind "restart" so the user sees real-time
# status and streamed log output in the same place they see deploys.
# Previously this ran as a silent background job: no record, no logs,
# no way to know whether the restart actually succeeded.
class RestartJob < ApplicationJob
  queue_as :default

  def perform(service_id, idempotency_key: nil, kind: "restart", triggered_by: "manual")
    service = Service.find(service_id)
    project = service.project
    server = project.server

    return unless server&.ssh_key.present?

    deployment, is_new = Deployment.create_idempotently!(
      service: service,
      key: idempotency_key,
      attributes: {
        kind: kind,
        status: "building",
        started_at: Time.current,
        branch: service.branch,
        triggered_by: triggered_by,
        build_log: "",
        deploy_log: ""
      }
    )

    if is_new
      RealtimeBroadcaster.deployment(service, {
        deployment_id: deployment.id,
        kind: kind,
        status: "building",
        message: "Restart started",
        started_at: deployment.created_at.iso8601
      })
    end

    engine = DokkuEngine.new(server)
    host_engine = HostEngine.new(server)
    restart_success = false

    begin
      log = ->(msg) {
        line = "[#{Time.current.iso8601}] #{msg}\n"
        line = deployment.append_log_chunk!(line)
        RealtimeBroadcaster.deployment(service, {
          deployment_id: deployment.id,
          kind: deployment.kind,
          status: "building",
          message: msg,
          log_chunk: line,
          sequence: deployment.event_sequence
        })
      }

      log.call("Restarting #{service.dokku_app_name} (#{service.subtype})")

      if service.service_type_database?
        result = restart_database_service(engine, service)
        log.call("#{service.subtype}:restart #{result[:success] ? 'succeeded' : 'reported failure'}: #{result[:output].to_s.truncate(500)}")
      else
        result = engine.ps_restart(service.dokku_app_name)
        log.call("ps:restart #{result[:success] ? 'succeeded' : 'reported failure'}: #{result[:output].to_s.truncate(500)}")
      end

      if result[:success]
        restart_success = true
      else
        # Dokku often returns exit code 1 even when the container was
        # created successfully (builds dir permission warnings, etc.).
        # Trust the actual container state.
        container = host_engine.wait_for_container(service.dokku_app_name, timeout: 60)
        if container.present? && host_engine.container_running?(container)
          restart_success = true
          log.call("Restart reported failure but container #{container} is running")
        end
      end

      log.call("Restoring network aliases")
      network_manager = ProjectNetworkManager.new(project, engine)
      begin
        restore_network_aliases(service, network_manager, log)
      rescue => e
        log.call("Network alias restore failed: #{e.message}")
      end

      if restart_success
        service.update!(status: "running")
        deployment.update!(status: "succeeded", completed_at: Time.current)
        RealtimeBroadcaster.deployment(service, {
          deployment_id: deployment.id,
          kind: deployment.kind,
          status: "succeeded",
          message: "Restart completed",
          completed_at: deployment.completed_at.iso8601
        })
        ActivityEvent.create!(
          project: project,
          service_name: service.name,
          action: :restarted,
          message: "Restarted #{service.name}"
        )
      else
        service.update!(status: "error")
        deployment.update!(status: "failed", completed_at: Time.current)
        RealtimeBroadcaster.deployment(service, {
          deployment_id: deployment.id,
          kind: deployment.kind,
          status: "failed",
          message: "Restart failed: container not running",
          completed_at: deployment.completed_at.iso8601
        })
      end
    rescue => e
      Rails.logger.error "RestartJob exception for #{service.dokku_app_name}: #{e.message}"
      deployment.update!(status: "failed", completed_at: Time.current) if deployment
      RealtimeBroadcaster.deployment(service, {
        deployment_id: deployment&.id,
        kind: "restart",
        status: "failed",
        message: "Restart failed: #{e.message}",
        completed_at: Time.current.iso8601
      }) if deployment
    end
  end

  private

  def restart_database_service(engine, service)
    case service.subtype
    when "postgres"
      engine.run("postgres:restart #{service.dokku_app_name}")
    when "redis"
      engine.run("redis:restart #{service.dokku_app_name}")
    when "mysql", "mariadb"
      engine.run("mysql:restart #{service.dokku_app_name}")
    when "mongo"
      engine.run("mongo:restart #{service.dokku_app_name}")
    else
      { success: false, output: "Unknown database subtype: #{service.subtype}" }
    end
  end

  def restore_network_aliases(service, network_manager, log)
    network_manager.connect_service(service)
    log.call("Restored aliases for #{service.name}")

    restore_linked_services_aliases(service, network_manager, log)
    restore_reverse_linked_services_aliases(service, network_manager, log)
    network_manager.inject_internal_hostnames(service)
  end

  def restore_linked_services_aliases(service, network_manager, log)
    return if service.linked_services.blank?
    service.linked_services.each do |linked|
      network_manager.ensure_linked_aliases(linked)
      log.call("Restored aliases for linked service #{linked.name}")
    end
  end

  def restore_reverse_linked_services_aliases(service, network_manager, log)
    linking_services = Service.where.not(id: service.id).select do |s|
      s.linked_services.any? { |linked| linked.id == service.id }
    end
    linking_services.each do |linking_service|
      container = HostEngine.new(linking_service.project.server).dokku_container_name(linking_service.dokku_app_name)
      if container.present?
        alias_name = linking_service.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-")
        network_manager.connect_container_with_aliases(container, [ alias_name ])
        log.call("Restored alias for linking service #{linking_service.name}")
      end
    end
  end
end

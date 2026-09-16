# Detects apps whose running container is not actually serving the routing
# labels RailDock intends.
#
# A deploy can report success while the app is unreachable: Traefik silently
# drops every router for a service that defines both a
# `loadbalancer.server.port` and a `loadbalancer.server.url`, and a container
# created before RailDock last changed its labels keeps serving the old
# configuration until it is recreated. Neither case fails a deploy, so this
# runs on a schedule and surfaces the mismatch instead of waiting for a user to
# report a 404/504.
class ProxyDriftCheckJob < ApplicationJob
  queue_as :default

  # Suppress repeat warnings for the same service within this window.
  REPORT_WINDOW = 24.hours

  def perform
    checked = 0
    drifted = 0

    Server.where(proxy_mode: "external").find_each do |server|
      engine = DokkuEngine.new(server)
      host_engine = HostEngine.new(server)

      server.projects.includes(:services).find_each do |project|
        project.services.select(&:service_type_app?).each do |service|
          next if service.domains.empty?

          result = check_service(project, service, engine, host_engine)
          next if result.nil?

          checked += 1
          drifted += 1 if result == :drifted
        end
      end
    end

    { checked: checked, drifted: drifted }
  end

  private

  # Returns :ok, :drifted, or nil when the service could not be inspected.
  def check_service(project, service, engine, host_engine)
    container = host_engine.dokku_container_name(service.dokku_app_name)
    return nil if container.blank?

    actual = host_engine.container_labels(container)
    return nil if actual.nil?

    problems = ExternalProxyConfigurator.new(service, engine, host_engine).routing_problems(actual)
    return :ok if problems.empty?

    report_problems(project, service, problems)
    :drifted
  end

  def report_problems(project, service, problems)
    detail = problems.map { |kind, keys| "#{kind}=#{keys.inspect}" }.join(" ")
    Rails.logger.warn(
      "ProxyDriftCheckJob: #{service.dokku_app_name} routing is broken — #{detail}"
    )

    return if recently_reported?(project, service)

    ActivityEvent.create!(
      project: project,
      service_name: service.name,
      action: :warning,
      message: "Proxy routing problem detected for #{service.name} " \
               "(#{problems.keys.join(', ')}): the running container is not serving the " \
               "intended Traefik routing. Redeploy the service to reconcile it."
    )
  end

  def recently_reported?(project, service)
    ActivityEvent
      .where(project: project, service_name: service.name, action: "warning")
      .where("message LIKE ?", "Proxy routing problem detected%")
      .where("created_at > ?", REPORT_WINDOW.ago)
      .exists?
  end
end

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

    drift = ExternalProxyConfigurator.new(service, engine, host_engine).drift(actual)
    return :ok if drift[:missing].empty? && drift[:stale].empty?

    report_drift(project, service, drift)
    :drifted
  end

  def report_drift(project, service, drift)
    Rails.logger.warn(
      "ProxyDriftCheckJob: #{service.dokku_app_name} routing labels are out of sync with the " \
      "running container — missing=#{drift[:missing].keys.inspect} stale=#{drift[:stale].keys.inspect}"
    )

    return if recently_reported?(project, service)

    ActivityEvent.create!(
      project: project,
      service_name: service.name,
      action: :warning,
      message: "Proxy configuration drift detected: routing labels on the running container for " \
               "#{service.name} do not match the desired state " \
               "(missing: #{drift[:missing].keys.size}, stale: #{drift[:stale].keys.size}). " \
               "Redeploy the service to reconcile it."
    )
  end

  def recently_reported?(project, service)
    ActivityEvent
      .where(project: project, service_name: service.name, action: "warning")
      .where("message LIKE ?", "Proxy configuration drift detected%")
      .where("created_at > ?", REPORT_WINDOW.ago)
      .exists?
  end
end

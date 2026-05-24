class TraefikLabelBuilder
  def initialize(service, domain)
    @service = service
    @domain = domain
    @app_name = service.dokku_app_name
  end

  def build_labels
    return {} unless domain.wildcard?

    target = domain.target_port || service.detected_port || 5000
    router_name = "#{app_name}-wildcard"
    service_name = "#{app_name}-web"

    labels = {}

    # HTTP router (with redirect middleware)
    labels["traefik.http.routers.#{router_name}-http.rule"] = domain.traefik_rule
    labels["traefik.http.routers.#{router_name}-http.entrypoints"] = "web"
    labels["traefik.http.routers.#{router_name}-http.middlewares"] = "redirect-to-https"
    labels["traefik.http.routers.#{router_name}-http.service"] = service_name

    # HTTPS router
    labels["traefik.http.routers.#{router_name}-https.rule"] = domain.traefik_rule
    labels["traefik.http.routers.#{router_name}-https.entrypoints"] = "websecure"
    labels["traefik.http.routers.#{router_name}-https.tls"] = "true"
    labels["traefik.http.routers.#{router_name}-https.tls.certresolver"] = "letsencrypt"
    labels["traefik.http.routers.#{router_name}-https.service"] = service_name

    # Service target port
    labels["traefik.http.services.#{service_name}.loadbalancer.server.port"] = target.to_s

    # Wildcard cert request
    labels["traefik.http.routers.#{router_name}-https.tls.domains[0].main"] = domain.base_hostname
    labels["traefik.http.routers.#{router_name}-https.tls.domains[0].sans"] = domain.hostname

    labels
  end

  private

  attr_reader :service, :domain, :app_name
end

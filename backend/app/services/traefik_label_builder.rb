class TraefikLabelBuilder
  def initialize(service, domain, server: nil)
    @service = service
    @domain = domain
    @server = server
    @app_name = service.dokku_app_name
  end

  def build_labels
    target = domain.target_port || service.detected_port || service.port || 5000
    router_name = "#{app_name}-#{domain.base_hostname.parameterize}"
    service_name = "#{app_name}-web"
    http_entrypoint = server&.external_proxy_http_entrypoint.presence || "web"
    https_entrypoint = server&.external_proxy_https_entrypoint.presence || "websecure"
    redirect_middleware = server&.external_proxy_redirect_middleware.presence || (server.nil? ? "redirect-to-https" : nil)
    cert_resolver = server&.external_proxy_cert_resolver.presence || (server.nil? ? "letsencrypt" : nil)

    labels = {}

    # HTTP router (with redirect middleware)
    labels["traefik.http.routers.#{router_name}-http.rule"] = domain.traefik_rule
    labels["traefik.http.routers.#{router_name}-http.entrypoints"] = http_entrypoint
    labels["traefik.http.routers.#{router_name}-http.middlewares"] = redirect_middleware if redirect_middleware
    labels["traefik.http.routers.#{router_name}-http.service"] = service_name

    # HTTPS router
    labels["traefik.http.routers.#{router_name}-https.rule"] = domain.traefik_rule
    labels["traefik.http.routers.#{router_name}-https.entrypoints"] = https_entrypoint
    labels["traefik.http.routers.#{router_name}-https.tls"] = "true"
    labels["traefik.http.routers.#{router_name}-https.tls.certresolver"] = cert_resolver if cert_resolver
    labels["traefik.http.routers.#{router_name}-https.service"] = service_name

    # Service target port
    labels["traefik.http.services.#{service_name}.loadbalancer.server.port"] = target.to_s

    # Wildcard cert request
    if domain.wildcard?
      labels["traefik.http.routers.#{router_name}-https.tls.domains[0].main"] = domain.base_hostname
      labels["traefik.http.routers.#{router_name}-https.tls.domains[0].sans"] = domain.hostname
    end

    labels
  end

  private

  attr_reader :service, :domain, :server, :app_name
end

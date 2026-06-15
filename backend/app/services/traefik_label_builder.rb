class TraefikLabelBuilder
  def initialize(service, domain, server: nil)
    @service = service
    @domain = domain
    @server = server
    @app_name = service.dokku_app_name
  end

  def build_labels
    # Prefer manifest-driven ports over auto-detected ones.
    # domain.target_port is set from the manifest's `port` field by the reconciler.
    # service.port is the manifest-declared port.  detected_port is auto-detected
    # from Docker EXPOSE / ports:report which can be unreliable.
    target = domain.target_port || service.port || service.detected_port || 5000
    router_name = "#{app_name}-#{domain.base_hostname.parameterize}"
    service_name = "#{app_name}-web"
    http_entrypoint = server&.external_proxy_http_entrypoint.presence || "web"
    https_entrypoint = server&.external_proxy_https_entrypoint.presence || "websecure"
    redirect_middleware = server&.external_proxy_redirect_middleware.presence || (server.nil? ? "redirect-to-https" : nil)
    cert_resolver = server&.external_proxy_cert_resolver.presence || (server.nil? ? "letsencrypt" : nil)

    labels = {}
    supports_ssl = domain.ssl != false  # nil = not set = assume SSL is supported

    # HTTP router — always created
    labels["traefik.http.routers.#{router_name}-http.rule"] = domain.traefik_rule
    labels["traefik.http.routers.#{router_name}-http.entrypoints"] = http_entrypoint
    # Only add redirect middleware when the domain supports SSL (otherwise
    # there's no HTTPS to redirect to — e.g. sslip.io / nip.io domains).
    labels["traefik.http.routers.#{router_name}-http.middlewares"] = redirect_middleware if redirect_middleware && supports_ssl
    labels["traefik.http.routers.#{router_name}-http.service"] = service_name

    # HTTPS router — only when the domain supports SSL
    if supports_ssl
      labels["traefik.http.routers.#{router_name}-https.rule"] = domain.traefik_rule
      labels["traefik.http.routers.#{router_name}-https.entrypoints"] = https_entrypoint
      labels["traefik.http.routers.#{router_name}-https.tls"] = "true"
      labels["traefik.http.routers.#{router_name}-https.tls.certresolver"] = cert_resolver if cert_resolver
      labels["traefik.http.routers.#{router_name}-https.service"] = service_name

      # Wildcard cert request
      if domain.wildcard?
        labels["traefik.http.routers.#{router_name}-https.tls.domains[0].main"] = domain.base_hostname
        labels["traefik.http.routers.#{router_name}-https.tls.domains[0].sans"] = domain.hostname
      end
    end

    # Service target port
    labels["traefik.http.services.#{service_name}.loadbalancer.server.port"] = target.to_s

    labels
  end

  private

  attr_reader :service, :domain, :server, :app_name
end

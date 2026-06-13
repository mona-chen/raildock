require "rails_helper"

RSpec.describe TraefikLabelBuilder do
  it "builds HTTP and HTTPS labels for a standard domain using server settings" do
    server = create(
      :server,
      proxy_mode: "external",
      external_proxy_network: "matrix_default",
      external_proxy_http_entrypoint: "http",
      external_proxy_https_entrypoint: "https",
      external_proxy_cert_resolver: "matrix-letsencrypt",
      external_proxy_redirect_middleware: "redirect-https@docker"
    )
    service = create(:service, project: create(:project, server: server), detected_port: 3000)
    domain = create(:domain, service: service, hostname: "app.example.com", target_port: 3000)

    labels = described_class.new(service, domain, server: server).build_labels
    router = "#{service.dokku_app_name}-app-example-com"

    expect(labels).to include(
      "traefik.http.routers.#{router}-http.rule" => "Host(`app.example.com`)",
      "traefik.http.routers.#{router}-http.entrypoints" => "http",
      "traefik.http.routers.#{router}-http.middlewares" => "redirect-https@docker",
      "traefik.http.routers.#{router}-https.entrypoints" => "https",
      "traefik.http.routers.#{router}-https.tls" => "true",
      "traefik.http.routers.#{router}-https.tls.certresolver" => "matrix-letsencrypt",
      "traefik.http.services.#{service.dokku_app_name}-web.loadbalancer.server.port" => "3000"
    )
  end
end

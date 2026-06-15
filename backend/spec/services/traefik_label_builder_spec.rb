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
    domain = create(:domain, service: service, hostname: "app.example.com", target_port: 3000, ssl: true)

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

  it "skips HTTPS labels for non-SSL domains (e.g. sslip.io)" do
    server = create(
      :server,
      proxy_mode: "external",
      external_proxy_network: "traefik",
      external_proxy_http_entrypoint: "web",
      external_proxy_https_entrypoint: "web-secure",
      external_proxy_cert_resolver: "letsencrypt"
    )
    service = create(:service, project: create(:project, server: server), detected_port: 8200)
    domain = create(:domain, service: service, hostname: "app.152.53.163.11.sslip.io", target_port: 8200, ssl: false)

    labels = described_class.new(service, domain, server: server).build_labels
    router = "#{service.dokku_app_name}-app-152-53-163-11-sslip-io"

    # HTTP router should exist without redirect middleware
    expect(labels).to include(
      "traefik.http.routers.#{router}-http.rule" => "Host(`app.152.53.163.11.sslip.io`)",
      "traefik.http.routers.#{router}-http.entrypoints" => "web",
      "traefik.http.routers.#{router}-http.service" => "#{service.dokku_app_name}-web",
      "traefik.http.services.#{service.dokku_app_name}-web.loadbalancer.server.port" => "8200"
    )
    # No redirect middleware for non-SSL
    expect(labels).not_to have_key("traefik.http.routers.#{router}-http.middlewares")
    # No HTTPS router
    expect(labels).not_to have_key("traefik.http.routers.#{router}-https.rule")
    expect(labels).not_to have_key("traefik.http.routers.#{router}-https.tls")
  end

  it "prefers domain target_port over detected_port when both set" do
    service = create(:service, detected_port: 8201)
    domain = create(:domain, service: service, target_port: 3000)

    labels = described_class.new(service, domain).build_labels

    expect(labels["traefik.http.services.#{service.dokku_app_name}-web.loadbalancer.server.port"]).to eq("3000")
  end

  it "uses domain target_port default of 80 when no manifest port and no detected_port" do
    service = create(:service, detected_port: nil)
    domain = create(:domain, service: service)

    labels = described_class.new(service, domain).build_labels

    expect(labels["traefik.http.services.#{service.dokku_app_name}-web.loadbalancer.server.port"]).to eq("80")
  end
end

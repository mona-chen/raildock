require "rails_helper"

RSpec.describe ManifestSerializer do
  let(:toml) do
    <<~TOML
      [[services]]
      name = "web"
      category = "app"
      subtype = "web"
      builder = "railpack"
      framework = "vite"
      version = "1.2.3"
      docker_image = "nginx:alpine"
      start_command = "npm start"
      root_directory = "app"
      publish_directory = "dist"
      spa_fallback = true
      node_version = "22"
      exposed = true
      port = 3000
      maintenance = false
      restart_policy = "on-failure"
      restart_max_retries = 10
      auto_deploy = false
      source_revision = "abc123"
      source = { type = "git", repo = "https://github.com/acme/store.git", branch = "main" }
      domains = ["shop.example.com", "www.example.com"]
      depends_on = ["db"]
      env = { API_URL = "https://api.example.com", CACHE_HOST = "[SHARED:CACHE]" }

      [services.proxy]
      enabled = true
      type = "traefik"

      [[services.proxy.ports]]
      host = 80
      container = 3000
      scheme = "http"

      [services.scaling]
      web = 2
      worker = 1

      [services.limits]
      web = { memory = "512m", cpu = "0.5" }

      [services.reservations]
      web = { memory = "256m" }

      [services.checks]
      enabled = true
      mode = "enabled"
      wait = 5
      timeout = 30
      attempts = 5
      wait_to_retire = 60
      path = "/_up"
      skip = ["host"]

      [[services.cron]]
      command = "bin/cleanup"
      schedule = "0 3 * * *"

      [[services.storage]]
      host = "data"
      container = "/data"
      kind = "volume"

      [[services.docker_options]]
      phase = "deploy"
      option = "--memory=512m"

      [services.traefik_labels]
      "traefik.http.routers.web.rule" = "Host(`shop.example.com`)"

      [services.letsencrypt]
      enabled = true
      email = "ops@example.com"
      staging = false
      auto_renew = true

      [[services]]
      name = "db"
      category = "database"
      subtype = "postgres"

      [[links]]
      from = "web"
      to = "db"
    TOML
  end

  it "round-trips a canonical TOML manifest through dump and parse" do
    desired = ManifestParser.parse(toml, filename: "raildock.toml")
    dumped = described_class.dump(
      { services: desired.services, links: desired.links },
      format: "raildock.toml"
    )
    reparsed = ManifestParser.parse(dumped, filename: "raildock.toml")

    expect(reparsed.services).to eq(desired.services)
    expect(reparsed.links).to eq(desired.links)
  end

  it "round-trips a canonical JSON manifest" do
    desired = ManifestParser.parse(toml, filename: "raildock.toml")
    dumped = described_class.dump(
      { services: desired.services, links: desired.links },
      format: "raildock.json"
    )
    reparsed = ManifestParser.parse(dumped, filename: "raildock.json")

    expect(reparsed.services).to eq(desired.services)
    expect(reparsed.links).to eq(desired.links)
  end

  it "refuses to regenerate compatibility formats" do
    expect {
      described_class.dump({ services: [], links: [] }, format: "railway.toml")
    }.to raise_error(ManifestSerializer::UnsupportedFormat)
  end
end

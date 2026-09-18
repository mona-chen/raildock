# frozen_string_literal: true

# Demo data for previewing RailDock locally.
#
#   docker compose -f docker-compose.dev.yml -f docker-compose.dev.dokku.yml up -d
#   make seed-demo
#
# Creates an admin, an organization, a server pointed at the in-repo Dokku
# simulator (test/dokku-sim), and two projects with apps, a database, a cache,
# domains, a volume, environment variables, and enough history — deployments,
# activity, metrics — that every panel has something real to render.
#
# Idempotent, and development-only on purpose. This must never run against an
# install that has actual applications on it.

unless Rails.env.development?
  abort "[seed:demo] Refusing to run outside development (RAILS_ENV=#{Rails.env})."
end

ADMIN_EMAIL = ENV.fetch("DEMO_ADMIN_EMAIL", "admin@raildock.local")
ADMIN_PASSWORD = ENV.fetch("DEMO_ADMIN_PASSWORD", "changeme123")
ORG_SLUG = "tween"
DOKKU_HOST = ENV.fetch("DEMO_DOKKU_HOST", "dokku-sim")
SSH_KEY = ENV["DEMO_DOKKU_SSH_KEY"].to_s

def demo_log(message)
  puts "[seed:demo] #{message}"
end

# ── Admin + organization ────────────────────────────────────────────────────

admin = User.find_or_initialize_by(email: ADMIN_EMAIL)
admin.name = "Demo Admin"
admin.admin = true
admin.password = ADMIN_PASSWORD
admin.password_confirmation = ADMIN_PASSWORD
admin.save!
demo_log "admin ready: #{admin.email} / #{ADMIN_PASSWORD}"

organization = Organization.find_or_initialize_by(slug: ORG_SLUG)
organization.name = "Tween"
organization.owner = admin
organization.save!

OrganizationMembership.find_or_initialize_by(organization: organization, user: admin).tap do |membership|
  membership.role = :owner
  membership.save!
end

# ── Server pointed at the Dokku simulator ───────────────────────────────────

server = Server.find_or_initialize_by(organization: organization, host: DOKKU_HOST)
server.name = "Local Dokku"
server.ssh_user = "dokku"
server.status = "connected"
server.proxy_mode = "managed"
server.base_domain = "127.0.0.1.sslip.io"
server.os = "Alpine Linux (Dokku simulator)"
server.dokku_version = "0.35.14"
server.docker_version = "26.1.5"
server.memory_total = 8192
server.memory_used = 2048
server.disk_total = 60_000
server.disk_used = 18_400
server.ssh_key = SSH_KEY if SSH_KEY.present?
server.save!

if server.ssh_key.blank?
  demo_log "WARNING: no DEMO_DOKKU_SSH_KEY — the server cannot be reached; run `make seed-demo` instead"
else
  demo_log "server ready: #{server.name} (#{server.ssh_user}@#{server.host})"
end

# ── Projects ────────────────────────────────────────────────────────────────

hello = Project.find_or_initialize_by(organization: organization, name: "hello-world")
hello.user = admin
hello.server = server
hello.environment = "production"
hello.description ||= "A hello-world app and its datastore."
hello.save!

playbook = Project.find_or_initialize_by(organization: organization, name: "brand-playbook")
playbook.user = admin
playbook.server = server
playbook.environment = "production"
playbook.description ||= "Static Vite site deployed as a static bundle."
playbook.save!

# Every project is created with a default `production` environment (see
# Project#create_default_environment). The demo adds a `staging` environment so
# the environment switcher has something to switch between.
staging = hello.environments.find_or_initialize_by(slug: "staging")
staging.name = "staging"
staging.description = "Auto-deploys from the staging branch"
staging.is_default = false
staging.save!

# ── Services ────────────────────────────────────────────────────────────────

def demo_service(project, name, attributes)
  service = Service.find_or_initialize_by(project: project, name: name)
  service.assign_attributes(attributes)
  service.save!
  service
end

web = demo_service(hello, "hello-web", {
  service_type: "app",
  subtype: "web",
  status: "running",
  builder: "railpack",
  framework: "vite",
  git_repo: "https://github.com/mona-chen/hello-dokku.git",
  branch: "main",
  detected_port: 3000,
  port: 3000,
  internal_hostname: "hello-web.web",
  exposed: true,
  last_deployed: 40.minutes.ago,
  canvas_x: 120,
  canvas_y: 180,
  restart_policy: "on-failure",
  restart_max_retries: 10,
  config: {
    "staticSite" => {
      "publishDirectory" => "dist",
      "spaFallback" => true,
      "nodeVersion" => "22"
    }
  }
})

api = demo_service(hello, "hello-api", {
  service_type: "app",
  subtype: "web",
  status: "running",
  builder: "nixpacks",
  framework: "node",
  git_repo: "https://github.com/mona-chen/hello-dokku.git",
  branch: "main",
  root_directory: "api",
  detected_port: 3000,
  port: 3000,
  internal_hostname: "hello-api.web",
  exposed: true,
  last_deployed: 3.hours.ago,
  canvas_x: 420,
  canvas_y: 120,
  restart_policy: "on-failure",
  restart_max_retries: 10
})

worker = demo_service(hello, "hello-worker", {
  service_type: "app",
  subtype: "worker",
  status: "stopped",
  builder: "nixpacks",
  framework: "node",
  git_repo: "https://github.com/mona-chen/hello-dokku.git",
  branch: "main",
  internal_hostname: "hello-worker.web",
  exposed: false,
  last_deployed: 2.days.ago,
  canvas_x: 420,
  canvas_y: 330,
  restart_policy: "on-failure",
  restart_max_retries: 10
})

database = demo_service(hello, "hello-db", {
  service_type: "database",
  subtype: "postgres",
  status: "running",
  version: "16",
  internal_hostname: "hello-db",
  canvas_x: 120,
  canvas_y: 400
})

cache = demo_service(hello, "hello-cache", {
  service_type: "cache",
  subtype: "redis",
  status: "running",
  version: "7",
  internal_hostname: "hello-cache",
  canvas_x: 720,
  canvas_y: 400
})

site = demo_service(playbook, "brand-playbook", {
  service_type: "app",
  subtype: "web",
  status: "running",
  builder: "railpack",
  framework: "vite",
  git_repo: "https://github.com/Tween-IM/brand-playbook.git",
  branch: "main",
  detected_port: 3000,
  port: 3000,
  internal_hostname: "brand-playbook.web",
  exposed: true,
  last_deployed: 20.minutes.ago,
  canvas_x: 200,
  canvas_y: 200,
  restart_policy: "on-failure",
  restart_max_retries: 10,
  config: {
    "staticSite" => {
      "publishDirectory" => "dist",
      "spaFallback" => true,
      "nodeVersion" => "24"
    }
  }
})

demo_log "services ready: #{Service.where(project: [ hello, playbook ]).pluck(:name).join(', ')}"

# ── Wiring: process types, variables, domains, volumes, links ───────────────

[
  [ web, "web", "caddy run --config /Caddyfile", 1 ],
  [ api, "web", "node index.js", 2 ],
  [ worker, "worker", "node worker.js", 1 ],
  [ site, "web", "caddy run --config /Caddyfile", 1 ]
].each do |service, name, command, quantity|
  process = ProcessType.find_or_initialize_by(service: service, name: name)
  process.command = command
  process.quantity = quantity
  process.running = service.status == "running" ? quantity : 0
  process.save!
end

{
  web => {
    "NODE_ENV" => "production",
    "VITE_API_URL" => "https://api.hello.localhost"
  },
  api => {
    "NODE_ENV" => "production",
    "LOG_LEVEL" => "info"
  },
  site => {
    "NODE_ENV" => "production"
  }
}.each do |service, variables|
  variables.each do |key, value|
    record = EnvironmentVariable.find_or_initialize_by(service: service, key: key)
    record.value = value
    record.source = "ui"
    record.is_dokku_internal = false
    record.save!
  end
end

ServiceLink.find_or_create_by!(from_service: api, to_service: database)
ServiceLink.find_or_create_by!(from_service: api, to_service: cache)

# Dokku injects the connection string when a datastore is linked; mirror that so
# the overview's connection card has something to show.
[
  [ database, "DATABASE_URL", "postgres://postgres:demo-password@hello-db:5432/hello_db" ],
  [ cache, "REDIS_URL", "redis://hello-cache:6379" ]
].each do |service, key, value|
  record = EnvironmentVariable.find_or_initialize_by(service: api, key: key)
  record.value = value
  record.source = "dokku"
  record.is_dokku_internal = true
  record.save!
end

[
  [ web, "hello-web.127.0.0.1.sslip.io", 443, 3000, "active" ],
  [ web, "hello-web.localhost", 443, 3000, "active" ],
  [ api, "hello-api.127.0.0.1.sslip.io", 443, 3000, "pending" ],
  [ site, "brand-playbook.127.0.0.1.sslip.io", 443, 3000, "active" ]
].each do |service, hostname, port, target_port, ssl_status|
  domain = Domain.find_or_initialize_by(service: service, hostname: hostname)
  domain.port = port
  domain.target_port = target_port
  domain.letsencrypt = true
  domain.ssl = ssl_status == "active"
  domain.ssl_status = ssl_status
  domain.ssl_expires_at = 60.days.from_now if ssl_status == "active"
  domain.ssl_checked_at = 10.minutes.ago
  domain.save!
end

volume = StorageMount.find_or_initialize_by(service: api, container_path: "/app/data")
volume.host_path = "hello-api-data"
volume.kind = "volume"
volume.save!

StorageMount.find_or_initialize_by(service: database, container_path: "/var/lib/postgresql/data").tap do |mount|
  mount.host_path = "hello-db-data"
  mount.kind = "volume"
  mount.save!
end

schedule = BackupSchedule.find_or_initialize_by(service: database, backup_kind: "database")
schedule.frequency = "daily"
schedule.retention_count = 7
schedule.last_run_at = 6.hours.ago
schedule.next_run_at = 18.hours.from_now
schedule.enabled = true
schedule.save!

# A paused volume-snapshot schedule so the Backups tab shows both schedule
# kinds and the pause/resume control has a real example.
volume_schedule = BackupSchedule.find_or_initialize_by(service: api, backup_kind: "volume")
volume_schedule.storage_mount = volume
volume_schedule.frequency = "weekly"
volume_schedule.retention_count = 4
volume_schedule.last_run_at = 3.days.ago
volume_schedule.next_run_at = 4.days.from_now
volume_schedule.enabled = false
volume_schedule.save!

# ── History: deployments, activity, metrics ─────────────────────────────────

def demo_deployments(service, entries)
  entries.each_with_index do |(status, trigger, offset, message), index|
    deployment = Deployment.find_or_initialize_by(
      service: service,
      idempotency_key: "demo-#{service.id}-#{index}"
    )
    deployment.status = status
    deployment.kind = "deploy"
    deployment.triggered_by = trigger
    deployment.branch = service.branch
    deployment.builder = service.builder
    deployment.commit_sha = format("%040x", service.id * 1000 + index)
    deployment.commit_message = message
    deployment.started_at = offset
    deployment.completed_at = status == "succeeded" ? offset + 90.seconds : offset + 40.seconds
    deployment.build_log = "-----> Building #{service.name} from #{service.builder}\n       done\n"
    deployment.deploy_log = status == "succeeded" ? "-----> Releasing #{service.name}\n=====> Application deployed\n" : " !     Node.js app detected\n !     No start script\n"
    deployment.save!
  end
end

demo_deployments(web, [
  [ "succeeded", "manual", 40.minutes.ago, "Add hero section" ],
  [ "succeeded", "github", 6.hours.ago, "Fix nav spacing" ],
  [ "failed", "github", 1.day.ago, "WIP: try Tailwind v4" ]
])
demo_deployments(api, [
  [ "succeeded", "github", 3.hours.ago, "Return JSON from /health" ],
  [ "succeeded", "manual", 2.days.ago, "Bump express" ]
])
demo_deployments(site, [
  [ "succeeded", "github", 20.minutes.ago, "Ship brand colours" ]
])
demo_deployments(worker, [
  [ "succeeded", "manual", 2.days.ago, "Initial worker" ]
])

[
  [ "created", "Created hello-world", 3.days.ago ],
  [ "deployed", "hello-web deployed", 40.minutes.ago ],
  [ "warning", "hello-web deployment failed — check the build log", 1.day.ago ],
  [ "linked", "hello-api linked to hello-db", 2.days.ago ],
  [ "deployed", "brand-playbook deployed", 20.minutes.ago ]
].each do |action, message, created_at|
  event = ActivityEvent.find_or_initialize_by(project: action == "deployed" && message.start_with?("brand") ? playbook : hello, message: message)
  event.action = action
  event.service_name = message.split(" ").first
  event.metadata = {}
  event.created_at = created_at
  event.save!
end

# A day of samples every five minutes, so the metrics panel draws a real series.
samples = []
[ [ web, 0.18, 220 ], [ api, 0.42, 310 ], [ site, 0.08, 120 ] ].each do |service, cpu_base, memory_base|
  (0...288).each do |i|
    sampled_at = Time.current - ((288 - i) * 5).minutes
    wave = Math.sin(i / 24.0)
    samples << {
      service_id: service.id,
      cpu: (cpu_base * (1.0 + (wave * 0.35))).round(4),
      cpu_cores: 2.0,
      memory: memory_base,
      memory_used: (memory_base * (1.0 + (wave * 0.15))).round(2),
      memory_limit: 512.0,
      network_in: (12_000 + (i * 37)).round(2),
      network_out: (8_000 + (i * 21)).round(2),
      block_read: (i * 512).round(2),
      block_write: (i * 256).round(2),
      sampled_at: sampled_at,
      created_at: Time.current,
      updated_at: Time.current
    }
  end
end

ServiceMetric.where(service_id: [ web.id, api.id, site.id ]).delete_all
ServiceMetric.insert_all(samples)

demo_log "history ready: #{Deployment.count} deployments, #{ActivityEvent.count} activity events, #{ServiceMetric.count} metric samples"
demo_log "done — sign in at http://localhost:5173 with #{ADMIN_EMAIL} / #{ADMIN_PASSWORD}"

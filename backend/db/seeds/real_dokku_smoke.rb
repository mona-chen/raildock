# An actual deployment through the same job used by the dashboard.
abort "Development only" unless Rails.env.development?
server = Server.find_by!(host: ENV.fetch("LOCAL_DOKKU_HOST", "host.docker.internal"), ssh_port: 52222)
raise "Refusing to run smoke deployment outside the local Linux VM" unless server.name == "Local Linux · Real Dokku"
project = Project.find_or_create_by!(organization: server.organization, name: "Real Dokku") do |record|
  record.server = server
  record.user = User.find_by!(email: "admin@raildock.local")
end
raise "Project is on a different host" unless project.server_id == server.id
service = project.services.find_or_create_by!(name: "Web") do |record|
  record.status = "stopped"
  record.service_type = "app"
  record.subtype = "web"
  record.docker_image = "nginx:alpine"
  record.port = "80"
  record.builder = "dockerfile"
  record.config = {
    "proxy" => { "enabled" => true, "proxyType" => "nginx" },
    "checks" => { "path" => "/", "attempts" => 3 },
    "cron" => [ { "schedule" => "@hourly", "command" => "/bin/true", "concurrency_policy" => "forbid" } ],
    "scripts" => { "predeploy" => "echo RAILDOCK_NATIVE_PREDEPLOY", "postdeploy" => "echo RAILDOCK_NATIVE_POSTDEPLOY" }
  }
end
service.domains.find_or_create_by!(hostname: "raildock-native.localhost") { |domain| domain.port = 80 }
deployment = service.deployments.create!(status: "pending", started_at: Time.current, triggered_by: "manual")
DeploymentJob.perform_now(service.id, deployment.id)
deployment.reload
puts "Real deployment #{deployment.id}: #{deployment.status}; preview project #{project.id}"
abort LogRedactor.redact(deployment.deploy_log.to_s).last(3000) unless deployment.succeeded?

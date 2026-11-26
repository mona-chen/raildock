# Register an isolated real Linux development host without moving simulator apps.
abort "Development only" unless Rails.env.development?
organization = Organization.find_by!(slug: ENV.fetch("LOCAL_DOKKU_ORG", "tween"))
host = ENV.fetch("LOCAL_DOKKU_HOST", "host.docker.internal")
port = ENV.fetch("LOCAL_DOKKU_PORT", "52222").to_i
result = ServerTestService.new(organization: organization, host: host, ssh_port: port).test
abort result[:error] || result[:output] || "Could not verify real Dokku host" unless result[:success]
server = Server.find_or_initialize_by(organization: organization, host: host)
abort "Refusing to repoint an existing server on another SSH port" if server.persisted? && server.ssh_port != port
server.assign_attributes(name: "Local Linux · Real Dokku", ssh_port: port, ssh_user: "dokku",
  ssh_key: organization.ensure_ssh_key!.private_key, host_key: result[:host_key],
  host_key_fingerprint: result[:host_key_fingerprint], os: result[:os],
  dokku_version: result[:dokku_version], docker_version: result[:docker_version],
  proxy_mode: "managed", status: "connected", status_checked_at: Time.current)
server.save!
puts "Registered real Dokku server #{server.id}: #{server.os}, Dokku #{server.dokku_version}"

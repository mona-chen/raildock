# Auto-configure the local Dokku server on boot if no servers exist.
# This provides a zero-config setup experience similar to Coolify/Dokploy.

Rails.application.config.after_initialize do
  next unless Server.table_exists?
  next if Server.count > 0

  dokku_key_path = "/data/dokku-ssh/id_ed25519"

  if File.exist?(dokku_key_path)
    private_key = File.read(dokku_key_path).strip

    server = Server.create!(
      name: "Local Dokku",
      host: "dokku",
      ssh_key: private_key,
      status: :disconnected,
      default_proxy: "traefik"
    )

    begin
      engine = DokkuEngine.new(server)
      result = engine.validate_connection

      if result[:success]
        proxy_result = engine.run("proxy:report")
        detected = %w[traefik caddy haproxy openresty].find { |p| proxy_result[:output].to_s.downcase.include?(p) } || "nginx"

        server.update!(
          status: :connected,
          dokku_version: result[:dokku_version],
          docker_version: result[:docker_version],
          os: result[:os],
          uptime: result[:uptime],
          default_proxy: detected,
          public_ip: result[:public_ip]
        )

        Rails.logger.info "[AutoSetup] Local Dokku server auto-configured successfully (version #{result[:dokku_version]})"
      else
        server.update!(status: :error)
        Rails.logger.warn "[AutoSetup] Local Dokku server created but connection failed: #{result[:output]}"
      end
    rescue => e
      server.update!(status: :error)
      Rails.logger.error "[AutoSetup] Failed to validate local Dokku server: #{e.message}"
    end
  else
    Rails.logger.info "[AutoSetup] No Dokku SSH key found at #{dokku_key_path}, skipping auto-configuration"
  end
end

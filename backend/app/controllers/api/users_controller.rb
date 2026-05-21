module Api
  class UsersController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def setup_required
      render json: { required: User.count.zero? }
    end

    def create
      if User.count > 0
        render json: { error: "First user already created" }, status: :unprocessable_entity
        return
      end

      user = User.new(user_params)
      if user.save
        ensure_local_dokku_server
        render json: { token: user.generate_jwt, user: user.as_json(only: [:id, :email, :name]) }, status: :created
      else
        render json: { error: user.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    private

    def user_params
      params.require(:user).permit(:name, :email, :password)
    end

    def ensure_local_dokku_server
      dokku_key_path = "/data/dokku-ssh/id_ed25519"
      return unless File.exist?(dokku_key_path)

      private_key = File.read(dokku_key_path).strip

      # Find existing local server or create one
      server = Server.find_by(host: "dokku") || Server.create!(
        name: "Local Dokku",
        host: "dokku",
        ssh_key: private_key,
        status: :disconnected,
        default_proxy: "traefik"
      )

      # Always validate connection — Dokku may not have been ready during auto-setup
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
          default_proxy: detected
        )
      else
        server.update!(status: :error)
      end
    rescue => e
      Rails.logger.error "[Setup] Failed to auto-configure local Dokku server: #{e.message}"
    end
  end
end

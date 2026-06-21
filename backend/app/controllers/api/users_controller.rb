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

      user = User.new(user_params.merge(admin: true))
      if user.save
        organization = ensure_personal_organization(user)
        ensure_local_dokku_server
        render json: {
          token: user.generate_jwt,
          user: user_payload_with_orgs(user),
          organization: organization_payload(organization)
        }, status: :created
      else
        render json: { error: user.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    private

    def user_params
      params.require(:user).permit(:name, :email, :password)
    end

    def organization_payload(organization)
      return nil unless organization
      {
        id: organization.id,
        name: organization.name,
        slug: organization.slug,
        role: "owner",
        member_count: 1
      }
    end

    def ensure_local_dokku_server
      dokku_key_path = "/data/dokku-ssh/id_ed25519"
      return unless File.exist?(dokku_key_path)

      dokku_host = ENV.fetch("DOKKU_HOST", "dokku")
      private_key = File.read(dokku_key_path).strip

      # Find existing local server or create one
      server = Server.find_by(host: dokku_host) || Server.create!(
        name: "Local Dokku",
        host: dokku_host,
        ssh_key: private_key,
        status: :disconnected,
        default_proxy: "traefik"
      )

      # Always validate connection — Dokku may not have been ready during auto-setup
      engine = DokkuEngine.new(server)
      result = engine.validate_connection

      if result[:success]
        proxy_type_result = engine.run("proxy:report --global --proxy-global-type")
        detected = proxy_type_result[:output].to_s.strip.presence
        detected ||= %w[traefik caddy haproxy openresty].find { |p| engine.run("proxy:report")[:output].to_s.downcase.include?(p) }
        detected ||= "nginx"
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

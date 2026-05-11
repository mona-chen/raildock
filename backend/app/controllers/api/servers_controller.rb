module Api
  class ServersController < BaseController
    def index
      servers = Server.all
      render json: servers
    end

    def create
      server = Server.create!(server_params.merge(status: :disconnected))
      render json: server, status: :created
    end

    def validate
      server = Server.find(params[:id])
      engine = DokkuEngine.new(server)
      result = engine.validate_connection

      if result[:success]
        # Detect installed proxy plugin
        proxy_result = engine.run("proxy:report")
        detected_proxy = detect_proxy_type(proxy_result[:output])

        server.update!(
          status: :connected,
          dokku_version: result[:dokku_version],
          docker_version: result[:docker_version],
          os: result[:os],
          uptime: result[:uptime],
          default_proxy: detected_proxy
        )
      else
        server.update!(status: :error)
      end

      render json: result.merge(default_proxy: server.default_proxy)
    end

    def metrics
      server = Server.find(params[:id])

      if server.ssh_key.present?
        engine = DokkuEngine.new(server)

        # Try to get real system metrics via SSH
        cpu_result = engine.run("docker system info --format '{{.NCPU}}'")
        mem_result = engine.run("free -m | awk 'NR==2{printf \"%.0f\", $3*100/$2 }'")
        disk_result = engine.run("df -h / | awk 'NR==2{print $5}' | sed 's/%//'")

        return render json: {
          cpu: cpu_result[:success] ? cpu_result[:output].to_i : 0,
          memory: mem_result[:success] ? mem_result[:output].to_i : 0,
          disk: disk_result[:success] ? disk_result[:output].to_i : 0,
          uptime: server.uptime || "0d 0h 0m"
        }
      end

      render json: {
        cpu: 0,
        memory: 0,
        disk: 0,
        uptime: server.uptime || "0d 0h 0m"
      }
    end

    def destroy
      server = Server.find(params[:id])
      server.destroy!
      head :no_content
    end

    private

    def server_params
      params.require(:server).permit(:name, :host, :ssh_key, :default_proxy)
    rescue ActionController::ParameterMissing
      params.permit(:name, :host, :ssh_key, :default_proxy)
    end

    def detect_proxy_type(output)
      return "nginx" unless output.present?
      # Check for traefik, caddy, haproxy, openresty in proxy report
      %w[traefik caddy haproxy openresty].each do |p|
        return p if output.downcase.include?(p)
      end
      "nginx"
    end
  end
end

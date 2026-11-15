module Api
  class ServersController < BaseController
    include Authorizable

    before_action :set_server, only: [ :show, :update, :destroy, :validate, :metrics, :metrics_history ]

    def index
      authorize_server!(action: :read)
      return if performed?

      servers = scoped_servers
      render json: servers
    end

    def show
      authorize_server_record!(@server, action: :read)
      return if performed?

      render json: @server
    end

    def create
      authorize_server!(action: :create)
      return if performed?

      server = build_server_from_params
      server.save!
      audit_log(action: "server.create", server: server, metadata: { host: server.host })
      render json: server, status: :created
    end

    def test
      authorize_server!(action: :create)
      return if performed?

      unless current_organization
        return render json: { error: "Organization required" }, status: :unprocessable_entity
      end

      result = ServerTestService.new(
        organization: current_organization,
        host: test_params[:host],
        ssh_user: test_params[:ssh_user]
      ).test

      audit_log(
        action: "server.test",
        metadata: { host: test_params[:host], ssh_user: test_params[:ssh_user], success: result[:success] }
      )
      render json: result
    end

    def provision
      authorize_server!(action: :create)
      return if performed?

      unless current_organization
        return render json: { error: "Organization required" }, status: :unprocessable_entity
      end

      setup_id = SecureRandom.uuid
      ProvisionServerJob.perform_later(
        setup_id,
        current_organization.id,
        provision_params[:host].to_s.strip,
        provision_params[:admin_user].presence || "root",
        Rails.application.config.x.app_url.presence || "#{request.protocol}#{request.host_with_port}",
        proxy_mode: provision_params[:proxy_mode].to_s.presence || "managed",
        server_name: provision_params[:server_name].to_s.strip.presence,
        base_domain: provision_params[:base_domain].to_s.strip.presence,
        auto_domains: provision_params[:auto_domains] != false,
        external_proxy_network: provision_params[:external_proxy_network].to_s.strip.presence,
        external_proxy_http_entrypoint: provision_params[:external_proxy_http_entrypoint].to_s.strip.presence,
        external_proxy_https_entrypoint: provision_params[:external_proxy_https_entrypoint].to_s.strip.presence,
        external_proxy_cert_resolver: provision_params[:external_proxy_cert_resolver].to_s.strip.presence,
        external_proxy_redirect_middleware: provision_params[:external_proxy_redirect_middleware].to_s.strip.presence
      )

      audit_log(
        action: "server.provision",
        metadata: { host: provision_params[:host], admin_user: provision_params[:admin_user] || "root", setup_id: setup_id }
      )
      render json: { setup_id: setup_id }
    end

    def provision_status
      setup_id = params[:setup_id].to_s.strip
      if setup_id.blank?
        return render json: { error: "setup_id required" }, status: :bad_request
      end

      render json: SetupProgress.get(setup_id)
    end

    def update
      authorize_server_record!(@server, action: :update)
      return if performed?

      @server.update!(server_params)
      audit_log(action: "server.update", server: @server, metadata: { host: @server.host })
      render json: @server
    end

    def validate
      authorize_server_record!(@server, action: :update)
      return if performed?

      engine = DokkuEngine.new(@server)
      result = engine.validate_connection

      if result[:success]
        # Detect installed proxy plugin
        proxy_type_result = engine.run("proxy:report --global --proxy-global-type")
        detected_proxy = proxy_type_result[:output].to_s.strip.presence
        detected_proxy ||= detect_proxy_type(engine.run("proxy:report")[:output])

        # The dokku SSH user cannot run raw shell commands; detect OS/uptime
        # via the root user. Best-effort — falls back to defaults.
        host_info = begin
          HostEngine.new(@server).host_info
        rescue ApplicationController::AuthorizationDenied, ServiceOperationLock::Busy
          raise
        rescue => e
          Rails.logger.warn "Server validate: host info unavailable for #{@server.host}: #{e.message}"
          { os: "Unknown", uptime: "unknown" }
        end

        @server.update!(
          status: :connected,
          dokku_version: result[:dokku_version],
          docker_version: result[:docker_version],
          os: result[:os].presence || host_info[:os],
          uptime: result[:uptime].presence || host_info[:uptime],
          default_proxy: detected_proxy,
          public_ip: result[:public_ip]
        )
      else
        @server.update!(status: :error)
      end

      audit_log(action: "server.validate", server: @server, metadata: { host: @server.host, success: result[:success] })
      render json: result.merge(
        default_proxy: @server.default_proxy,
        os: @server.os,
        uptime: @server.uptime
      )
    end

    def metrics
      authorize_server_record!(@server, action: :read)
      return if performed?

      unless ObservabilitySettings.hosts_enabled?
        return render json: { available: false, collection_enabled: false, cpu: nil, memory: nil, disk: nil }
      end
      sample = HostMetricsCollector.call(@server)
      return render json: { available: false, reason: "First sample is being collected" }, status: :accepted unless sample

      render json: sample.data.merge(sampled_at: sample.sampled_at.iso8601, collection_enabled: true)
    end

    def metrics_history
      authorize_server_record!(@server, action: :read)
      return if performed?

      hours = params[:hours].present? ? params[:hours].to_i.clamp(1, 168) : 1
      # Bucket long windows to keep response size bounded. Failed samples retain
      # their gaps rather than being averaged into a fictional healthy reading.
      step = hours > 24 ? 600 : (hours > 6 ? 300 : 60)
      rows = @server.server_metrics.where(sampled_at: hours.hours.ago..)
        .select("DISTINCT ON (floor(extract(epoch from sampled_at) / #{step})) server_metrics.*")
        .order(Arel.sql("floor(extract(epoch from sampled_at) / #{step}), sampled_at DESC"))
      render json: {
        collection_enabled: ObservabilitySettings.hosts_enabled?,
        retention_days: ObservabilitySettings.retention_days,
        samples: rows.map { |row| row.data.merge(at: row.sampled_at.iso8601) }
      }
    end

    def destroy
      authorize_server_record!(@server, action: :delete)
      return if performed?

      # A server can hold backup destinations whose artifacts are the only
      # remaining copy of a datastore. Refuse to cascade-delete them and say so
      # instead of replying 204 for work that did not happen.
      destinations = @server.backup_destinations.count
      if destinations.positive?
        return render json: {
          error: "Refusing to delete #{@server.name}: it still holds #{destinations} backup destination(s) whose artifacts are the only copy of your data. Move or delete them first.",
          code: "dependent_records_present",
          actionable: true
        }, status: :unprocessable_entity
      end

      audit_log(action: "server.destroy", server: @server, metadata: { host: @server.host })
      @server.destroy!
      head :no_content
    rescue ActiveRecord::RecordNotDestroyed => e
      render json: {
        error: @server.errors.full_messages.presence&.join("; ") || e.message,
        code: "dependent_records_present",
        actionable: true
      }, status: :unprocessable_entity
    end

    private

    def set_server
      @server = scoped_servers.find(params[:id])
    end

    def server_params
      permitted = [
        :name, :host, :ssh_key, :ssh_user, :default_proxy, :base_domain, :auto_domains,
        :proxy_mode, :external_proxy_network, :external_proxy_http_entrypoint,
        :external_proxy_https_entrypoint, :external_proxy_cert_resolver,
        :external_proxy_redirect_middleware, :host_key, :host_key_fingerprint,
        external_proxy_default_labels: {}
      ]
      params.require(:server).permit(permitted)
    rescue ActionController::ParameterMissing
      params.permit(permitted)
    end

    def test_params
      params.require(:server).permit(:host, :ssh_user)
    rescue ActionController::ParameterMissing
      params.permit(:host, :ssh_user)
    end

    def provision_params
      params.require(:server).permit(
        :host, :admin_user, :proxy_mode, :server_name, :base_domain, :auto_domains,
        :external_proxy_network, :external_proxy_http_entrypoint,
        :external_proxy_https_entrypoint, :external_proxy_cert_resolver,
        :external_proxy_redirect_middleware
      )
    rescue ActionController::ParameterMissing
      params.permit(
        :host, :admin_user, :proxy_mode, :server_name, :base_domain, :auto_domains,
        :external_proxy_network, :external_proxy_http_entrypoint,
        :external_proxy_https_entrypoint, :external_proxy_cert_resolver,
        :external_proxy_redirect_middleware
      )
    end

    def build_server_from_params
      server = Server.new(server_params.merge(status: :disconnected))

      if current_organization
        server.organization = current_organization
        server.user = nil
        server.ssh_key ||= current_organization.ensure_ssh_key!.private_key
      else
        server.user = current_user
      end

      server
    end

    def authorize_server_record!(server, action:)
      return true if current_user.admin?

      if server.organization_id.present?
        membership = current_user.organization_memberships.find_by(organization_id: server.organization_id)
        allowed = PERMISSIONS.dig(:server, action) || []
        return true if membership && allowed.include?(membership.role.to_sym)
      elsif server.user_id == current_user.id
        return true
      end

      render json: { error: "Forbidden" }, status: :forbidden
    end

    def detect_proxy_type(output)
      return "nginx" unless output.present?
      # Check for traefik, caddy, haproxy, openresty in proxy report
      %w[traefik caddy haproxy openresty].each do |p|
        return p if output.downcase.include?(p)
      end
      "nginx"
    end

    def audit_log(action:, server: nil, metadata: {})
      Rails.logger.info({
        event: "audit",
        action: action,
        user_id: current_user&.id,
        organization_id: current_organization&.id || server&.organization_id,
        server_id: server&.id,
        ip: request.remote_ip,
        metadata: metadata
      }.to_json)
    end
  end
end

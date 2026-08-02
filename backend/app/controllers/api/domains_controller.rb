module Api
  class DomainsController < BaseController
    include Authorizable
    before_action :set_and_authorize_service!

    def create
      is_wildcard = domain_params[:hostname].to_s.start_with?("*.")
      target = domain_params[:target_port].presence || @service.port || @service.detected_port || 80

      use_ssl = domain_params[:ssl] != false
      challenge = if is_wildcard
        "dns"  # Wildcards require DNS challenge
      else
        domain_params[:challenge_type].presence || "http"
      end

      # Magic domains (sslip.io, nip.io) can't get SSL certs
      magic = Domain::MAGIC_DOMAINS.any? { |m| domain_params[:hostname].to_s.end_with?(".#{m}") }
      use_ssl = false if magic

      # Auto-detect Cloudflare — if domain resolves to CF IPs, SSL is
      # handled by Cloudflare. Keep TLS labels (Cloudflare in Full mode
      # connects to origin over HTTPS and accepts Traefik's default cert).

      domain = @service.domains.create!(
        hostname: domain_params[:hostname],
        port: use_ssl ? (domain_params[:port] || 443) : (domain_params[:port] || 80),
        target_port: target,
        ssl: use_ssl,
        letsencrypt: use_ssl && domain_params[:letsencrypt] != false,
        wildcard: is_wildcard,
        ssl_status: use_ssl ? "pending" : "none",
        challenge_type: challenge
      )

      # Sync to Dokku
      sync_to_dokku(:add, domain)

      render json: domain, status: :created
    end

    def destroy
      hostname = normalize_hostname_param(params[:hostname])
      domain = @service.domains.find_by!(hostname: hostname)

      domain.destroy!
      sync_to_dokku(:remove, domain)
      head :no_content
    end

    private

    def set_and_authorize_service!
      @service = Service.find(params[:service_id])
      authorize_service!(@service)
    end

    def domain_params
      params.permit(:hostname, :port, :target_port, :ssl, :letsencrypt)
    end

    def normalize_hostname_param(value)
      value.to_s
        .strip
        .sub(/\Ahttps?:\/\/?/i, "")
        .sub(/:\d+\z/, "")
        .sub(/\/.*\z/, "")
        .downcase
    end

    def sync_to_dokku(action, domain)
      return unless @service.project&.server&.ssh_key.present?

      engine = DokkuEngine.new(@service.project.server)

      if domain.wildcard?
        sync_wildcard_to_dokku(action, domain, engine)
      else
        sync_standard_to_dokku(action, domain, engine)
      end

      if @service.project.server.external_proxy?
        refresh_external_proxy(engine)
      else
        sync_port_mapping(domain, engine)
        rebuild_for_port_change!(engine)
      end
    end

    def refresh_external_proxy(engine)
      server = @service.project.server
      result = ExternalProxyConfigurator.new(@service.reload, engine, HostEngine.new(server)).apply!
      raise "External proxy configuration failed: #{result[:output]}" unless result[:success]

      if @service.running?
        rebuild_result = engine.ps_rebuild(@service.dokku_app_name)
        raise "External proxy rebuild failed: #{rebuild_result[:output]}" unless rebuild_result[:success]
      end
    end

    # When a domain changes the expected container port (e.g. user adds a custom
    # domain pointing to 3000 on an app currently listening on 5000), rebuild so
    # Dokku injects the matching PORT env var and the proxy routes correctly.
    def rebuild_for_port_change!(engine)
      return unless @service.running?

      target = @service.port ||
               @service.domains.where(temporary: false).pick(:target_port) ||
               @service.domains.pick(:target_port) ||
               @service.detected_port ||
               5000
      return if target == @service.detected_port

      result = engine.ps_rebuild(@service.dokku_app_name)
      raise "Port change rebuild failed: #{result[:output]}" unless result[:success]

      @service.update!(detected_port: target)
    end

    def sync_standard_to_dokku(action, domain, engine)
      if action == :add
        engine.domain_add(@service.dokku_app_name, domain.hostname)
      else
        engine.domain_remove(@service.dokku_app_name, domain.hostname)
      end
    end

    def sync_wildcard_to_dokku(action, domain, engine)
      if action == :add
        labels = TraefikLabelBuilder.new(@service, domain).build_labels
        labels.each do |key, value|
          engine.run("traefik:labels:add #{escape(@service.dokku_app_name)} #{escape(key)} #{escape(value)}")
        end
      else
        # Remove wildcard labels — find and remove all labels for this app's wildcard router
        router_name = "#{@service.dokku_app_name}-wildcard"
        result = engine.traefik_show_config(@service.dokku_app_name)
        return unless result[:success]

        # Remove all labels that reference the wildcard router
        result[:output].each_line do |line|
          if line.include?(router_name)
            key = line.split("=").first&.strip
            if key.present?
              engine.run("traefik:labels:remove #{escape(@service.dokku_app_name)} #{escape(key)}")
            end
          end
        end
      end
    end

    def sync_port_mapping(domain, engine)
      target = domain.target_port || @service.detected_port || 5000
      # Only map https when the domain has SSL. A stray https:443 mapping on a
      # managed Traefik without letsencrypt makes Dokku emit an https router
      # for a nonexistent certresolver, breaking routing for the whole app.
      mappings = [ "http:80:#{target.to_i}" ]
      mappings << "https:443:#{target.to_i}" if domain.ssl
      engine.ports_set(@service.dokku_app_name, *mappings)
    end

    def escape(value)
      Shellwords.escape(value.to_s)
    end
  end
end

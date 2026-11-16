module Api
  class ObservabilityController < BaseController
    include Authorizable
    def notifications
      organization = current_organization
      return render json: { error: "Select an organization" }, status: :unprocessable_entity unless organization
      authorize_organization!(organization)
      if request.patch?
        values = params.require(:settings).permit(*(MonitoringPolicy::DEFAULTS.keys - [ "email_destinations" ]), email_destinations: []).to_h
        MonitoringPolicy.validate!(values)
        organization.update!(notification_settings: MonitoringPolicy.for(organization).merge(values))
      end
      server_ids = Server.where(organization: organization).select(:id)
      incidents = MonitoringIncident.where(server_id: server_ids).where.not(state: %w[pending discarded]).order(updated_at: :desc).limit(100)
      render json: { settings: MonitoringPolicy.for(organization), smtp_configured: (SystemSetting.smtp_enabled && SystemSetting.smtp_address.present?) || ENV["SMTP_ADDRESS"].present?, incidents: incidents.includes(:server).map { |incident| incident.as_json(only: [ :id, :signal, :state, :message, :started_at, :last_seen_at, :resolved_at, :delivery_status, :notified_at ]).merge(server_name: incident.server.name) } }
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def traffic_setup
      server = scoped_servers.find(params[:server_id])
      authorize_server!(action: :update)
      setup = HttpTrafficSetup.new(server)
      return render json: setup.discover(capture_paths: ActiveModel::Type::Boolean.new.cast(params[:capture_paths])) unless request.post?

      setup.verify!(params.require(:review_token))
      server.with_lock do
        if server.traffic_settings["setup_state"] == "running" && server.updated_at > 10.minutes.ago
          return render json: { error: "Proxy setup is already running." }, status: :conflict
        end
        server.update!(traffic_settings: server.traffic_settings.merge("setup_state" => "running", "setup_error" => nil))
        ConfigureHttpTrafficJob.perform_later(server.id, params[:review_token])
      end
      render json: { accepted: true }, status: :accepted
    rescue HttpTrafficSetup::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def traffic
      server = scoped_servers.find(params[:server_id])
      authorize_server!(action: request.patch? ? :update : :read)
      if request.patch?
        if server.traffic_settings["setup_state"] == "running" && server.updated_at > 10.minutes.ago
          return render json: { error: "Wait for proxy setup to finish before editing collection." }, status: :conflict
        end
        values = params.require(:settings).permit(:enabled, :path, :format, :retention_days, :capture_paths).to_h
        settings = { "enabled" => false, "format" => "traefik", "retention_days" => 7, "capture_paths" => false }.merge(server.traffic_settings).merge(values)
        # Managed logging decides path fields at the proxy, so flipping this here
        # would claim retention the log file cannot provide.
        if values.key?("capture_paths") && server.traffic_settings["managed_logging"] && values["capture_paths"] != server.traffic_settings.fetch("capture_paths", false)
          return render json: { error: "Path retention for automatically configured logging is part of the reviewed proxy setup. Run setup review again to change it." }, status: :unprocessable_entity
        end
        path = settings["path"].to_s
        valid_path = path.match?(%r{\A/(?:var/log|var/lib/dokku)/[A-Za-z0-9_./-]+\.(?:log|jsonl)\z}) && !path.split("/").include?("..")
        unless [ true, false ].include?(settings["capture_paths"]) && [ true, false ].include?(settings["enabled"]) && %w[traefik caddy].include?(settings["format"]) && settings["retention_days"].is_a?(Integer) && (1..30).cover?(settings["retention_days"]) && (!settings["enabled"] || valid_path)
          return render json: { error: "Enter an existing host log path under /var/log or /var/lib/dokku ending in .log or .jsonl, choose Traefik or Caddy JSON, and set retention to 1–30 days. Use automatic setup if no log exists." }, status: :unprocessable_entity
        end
        # Clearing the cursor when the source changes prevents an old file's byte
        # offset from skipping unrelated records in a newly selected source.
        if settings.values_at("path", "format") != server.traffic_settings.values_at("path", "format")
          settings["managed_logging"] = false
        end
        settings["setup_state"] = nil
        settings["setup_error"] = nil
        source_changed = settings.values_at("path", "format", "enabled") != server.traffic_settings.values_at("path", "format", "enabled")
        server.update!(traffic_settings: settings, traffic_cursor: source_changed ? {} : server.traffic_cursor)
      end
      CollectHttpTrafficJob.perform_later(server.id) if server.traffic_settings["enabled"] && params[:refresh] == "true"
      HttpTrafficSetup.new(server).refresh_status if server.traffic_settings["setup_state"] == "running"
      hours = params[:hours].to_i.clamp(1, 168)
      resolution = hours > 6 ? "hour" : "minute"
      rows = server.http_traffic_buckets.where(resolution: resolution, bucket_at: hours.hours.ago..).order(:bucket_at)
      summary = {}
      service_id = params[:service_id]&.to_s
      if service_id.present?
        service = Service.joins(:project).where(projects: { server_id: server.id }).find(service_id)
        authorize_service!(service)
      end
      step = hours > 6 ? 3600 : 60
      samples = rows.group_by { |row| row.bucket_at.to_i / step * step }.map do |at, buckets|
        total = buckets.reduce({}) do |sum, bucket|
          values = service_id.present? ? [ bucket.data[service_id] ].compact : bucket.data.values
          values.reduce(sum) { |acc, data| HttpTrafficCollector.merge(acc, data) }
        end
        summary = HttpTrafficCollector.merge(summary, total)
        total.merge("paths" => total.fetch("paths", {}).map { |path, count| { path: path, count: count } }, "at" => Time.at(at).utc.iso8601)
      end
      applications = Service.joins(:project).where(projects: { server_id: server.id }).pluck(:id, :name).to_h.transform_keys(&:to_s)
      by_application = rows.each_with_object(Hash.new(0)) { |bucket, totals| bucket.data.each { |id, data| totals[id] += data.fetch("requests", 0) if service_id.blank? || id == service_id } }.sort_by { |_id, count| -count }.first(25).map { |id, count| { id: id, name: applications[id] || "Unmapped traffic", requests: count } }
      render json: { settings: server.traffic_settings, collection: server.traffic_cursor.except("inode", "offset"), summary: summary.merge("paths" => summary.fetch("paths", {}).map { |path, count| { path: path, count: count } }), samples: samples, applications: applications.map { |id, name| { id: id, name: name } }, by_application: by_application, bucket_seconds: step, coverage: "Configured JSON access log only; first enable starts at end of file. Unmapped traffic is included in host totals." }
    end
  end
end

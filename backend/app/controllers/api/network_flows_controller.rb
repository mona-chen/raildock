module Api
  class NetworkFlowsController < BaseController
    include Authorizable

    def settings
      server = scoped_servers.find(params[:server_id])
      authorize_server!(action: request.patch? ? :update : :read)
      if request.patch?
        values = params.require(:settings).permit(:enabled, :retention_days).to_h
        policy = NetworkFlowCollector.settings(server).merge(values)
        unless [ true, false ].include?(policy["enabled"]) && policy["retention_days"].is_a?(Integer) && (0..30).cover?(policy["retention_days"])
          return render json: { error: "Choose enabled or disabled and history retention from 0–30 days (0 means live only)." }, status: :unprocessable_entity
        end
        policy["epoch"] = SecureRandom.hex(8)
        server.with_lock { server.update!(network_flow_settings: policy, network_flow_snapshot: {}) }
        NetworkFlowSamplerJob.perform_later(server.id)
      end
      render json: { settings: NetworkFlowCollector.settings(server).slice("enabled", "retention_days"), sampled_at: server.network_flow_snapshot["sampled_at"], error: server.network_flow_snapshot["error"] }
    end

    def index
      project = scoped_projects.find(params[:project_id])
      authorize_project!(project)
      server = project.server
      return render json: { enabled: false, links: [] } unless server
      enabled = NetworkFlowCollector.settings(server)["enabled"]
      snapshot = server.network_flow_snapshot
      NetworkFlowSamplerJob.enqueue_once(server.id) if enabled && (snapshot["sampled_at"].blank? || Time.iso8601(snapshot["sampled_at"]) < 9.seconds.ago)
      services = project.services
      if params[:environment_id].present?
        environment = project.environments.find(params[:environment_id])
        services = services.where(environment: environment)
      else
        services = services.where(environment: project.environments.find_by!(is_default: true))
      end
      ids = services.pluck(:id)
      links = ServiceLink.where(from_service_id: ids, to_service_id: ids)
      rows = Array(snapshot["links"]).index_by { |row| row["id"] }
      fresh = enabled && snapshot["sampled_at"].present? && Time.iso8601(snapshot["sampled_at"]) > 25.seconds.ago && snapshot["error"].blank?
      render json: { enabled: enabled, sampled_at: snapshot["sampled_at"], error: snapshot["error"], coverage: snapshot["coverage"], links: links.map do |link|
        row = rows[link.id.to_s]
        state = !enabled ? "disabled" : !fresh || !row ? "unavailable" : row["state"]
        (row || {}).merge("id" => link.id.to_s, "from_id" => link.from_service_id.to_s, "to_id" => link.to_service_id.to_s, "state" => state)
      end }
    end

    def history
      project = scoped_projects.find(params[:project_id])
      authorize_project!(project)
      link = ServiceLink.find(params[:link_id])
      ids = project.services.pluck(:id)
      raise ActiveRecord::RecordNotFound unless ids.include?(link.from_service_id) && ids.include?(link.to_service_id)
      rows = NetworkFlowSample.where(service_link: link).where("sampled_at > ?", 24.hours.ago).order(sampled_at: :desc).limit(360).reverse
      render json: rows.as_json(only: [ :sampled_at, :sent_bytes, :received_bytes, :connections, :window_seconds ])
    end
  end
end

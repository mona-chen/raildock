module Api
  class ServerPackagesController < BaseController
    include Authorizable

    def show
      authorize_server!(action: :read)
      server = scoped_servers.find(params[:server_id])
      render json: server.package_updates
    end

    def create
      authorize_server!(action: :update)
      server = scoped_servers.find(params[:server_id])
      kind = params[:kind].to_s
      return render json: { error: "Choose check or install" }, status: :unprocessable_entity unless %w[check install].include?(kind)
      if kind == "install" && (params[:confirmation] != server.name || params[:acknowledge_disruption] != true)
        return render json: { error: "Confirm the server name and acknowledge service restarts", code: "confirmation_required" }, status: :precondition_required
      end
      state = ServerPackageManager.start(server, kind, reviewed_id: params[:reviewed_id])
      Rails.logger.info({ event: "audit", action: "server.packages.#{kind}", user_id: current_user.id, organization_id: server.organization_id, server_id: server.id, operation_id: state.dig("operation", "id") }.to_json)
      render json: state, status: :accepted
    rescue ServerPackageManager::Busy, ServerPackageManager::InvalidPlan => error
      render json: { error: error.message }, status: :conflict
    end
  end
end

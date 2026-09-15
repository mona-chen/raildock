module Api
  class ServerUnmanagedDatastoresController < BaseController
    include Authorizable

    before_action :set_and_authorize_server!

    # GET /api/servers/:server_id/unmanaged_datastores
    # Datastores on the host with no Service record: invisible to the dashboard
    # and therefore to backups.
    def index
      result = UnmanagedDatastoreScanner.new(@server).scan
      unless result[:success]
        return render json: { error: result[:error] }, status: :unprocessable_entity
      end

      render json: { resources: result[:resources], errors: result[:errors] }
    end

    # POST /api/servers/:server_id/unmanaged_datastores/adopt
    def adopt
      project = scoped_projects.find(params[:project_id])
      authorize_project!(project, action: :update)

      service = DatastoreAdopter.new(@server, user: current_user).adopt!(
        resource_name: params[:resource_name],
        project: project,
        name: params[:name]
      )

      render json: service.as_json, status: :created
    rescue DatastoreAdopter::NotAdoptable => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def set_and_authorize_server!
      @server = scoped_servers.find(params[:server_id])
      authorize_server!(action: :update)
      nil if performed?
    end
  end
end

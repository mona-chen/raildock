module Api
  class ServerDockerImportsController < BaseController
    include Authorizable

    before_action :set_and_authorize_server!

    # GET /api/servers/:server_id/docker_imports
    def index
      result = DockerContainerScanner.new(@server).scan
      if result[:success]
        render json: result[:containers]
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    # POST /api/servers/:server_id/docker_imports
    def create
      containers = Array(params[:containers]).filter_map do |c|
        if c.respond_to?(:to_unsafe_h)
          c.to_unsafe_h.deep_symbolize_keys
        else
          c.presence
        end
      end
      if containers.empty?
        return render json: { error: "No containers selected" }, status: :unprocessable_entity
      end

      project = load_project_if_requested
      importer = ContainerImporter.new(@server, current_user, organization: current_organization)
      result = importer.import(containers, project: project)

      if result[:success]
        render json: result, status: :created
      else
        render json: { error: result[:error], results: result[:results] }, status: :unprocessable_entity
      end
    end

    private

    def set_and_authorize_server!
      @server = scoped_servers.find(params[:server_id])
      authorize_server!(action: :update)
      nil if performed?
    end

    def load_project_if_requested
      return nil if params[:project_id].blank?

      project = scoped_projects.find_by(id: params[:project_id])
      unless project
        render json: { error: "Project not found" }, status: :not_found
        return nil
      end
      authorize_project!(project, action: :update)
      return nil if performed?
      project
    end
  end
end

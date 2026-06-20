module Api
  class BuildersController < BaseController
    include Authorizable

    skip_before_action :authenticate_user!, only: [ :index ]
    before_action :authenticate_capability_request!, only: [ :index ]

    def index
      capabilities = builder_capabilities
      render json: [
        { id: "herokuish", name: "Herokuish", description: "Heroku-compatible buildpack-based builder" },
        { id: "pack", name: "Cloud Native Buildpacks", description: "Modern OCI-compliant buildpacks via pack" },
        { id: "dockerfile", name: "Dockerfile", description: "Build from a Dockerfile in your repo" },
        { id: "nixpacks", name: "Nixpacks", description: "Auto-detect language and build with Nix" },
        { id: "railpack", name: "Railpack", description: "Railway's modern buildpack alternative" },
        { id: "lambda", name: "AWS Lambda", description: "Package for AWS Lambda deployment" },
        { id: "null", name: "Null Builder", description: "Skip build, use existing image" }
      ].map { |builder| builder.merge(available: builder_available?(builder[:id], capabilities)) }
    end

    private
      def builder_capabilities
        return {} unless @capability_server&.ssh_key.present?

        HostEngine.new(@capability_server).builder_capabilities
      end

      def authenticate_capability_request!
        return if params[:server_id].blank?

        authenticate_user!
        return if performed?

        @capability_server = scoped_servers.find(params[:server_id])
      end

      def builder_available?(builder, capabilities)
        return true if capabilities.empty? || builder.in?(%w[herokuish dockerfile lambda null])
        return capabilities["railpack"] && capabilities["buildkit"] if builder == "railpack"

        capabilities.fetch(builder, true)
      end
  end
end

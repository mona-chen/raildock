module Api
  class BuildersController < BaseController
    skip_before_action :authenticate_user!, only: [ :index ]

    def index
      render json: [
        { id: "herokuish", name: "Herokuish", description: "Heroku-compatible buildpack-based builder" },
        { id: "pack", name: "Cloud Native Buildpacks", description: "Modern OCI-compliant buildpacks via pack" },
        { id: "dockerfile", name: "Dockerfile", description: "Build from a Dockerfile in your repo" },
        { id: "nixpacks", name: "Nixpacks", description: "Auto-detect language and build with Nix" },
        { id: "railpack", name: "Railpack", description: "Railway's modern buildpack alternative" },
        { id: "lambda", name: "AWS Lambda", description: "Package for AWS Lambda deployment" },
        { id: "null", name: "Null Builder", description: "Skip build, use existing image" }
      ]
    end
  end
end

module Api
  class GitSourcesController < BaseController
    def index
      sources = GitSource.all
      render json: sources
    end

    def create
      source = GitSource.create!(git_source_params.merge(connected: true))
      render json: source, status: :created
    end

    def destroy
      source = GitSource.find(params[:id])
      source.update!(connected: false, access_token: nil)
      head :no_content
    end

    private

    def git_source_params
      params.permit(:provider, :access_token, :username)
    end
  end
end

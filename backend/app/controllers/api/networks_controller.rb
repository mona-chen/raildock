module Api
  class NetworksController < BaseController
    skip_before_action :authenticate_user!, only: [ :index ]

    def index
      # TODO: fetch real Docker networks via DokkuEngine when server is connected
      render json: []
    end
  end
end

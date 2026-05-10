module Api
  class BaseController < ApplicationController
    include Authenticatable

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable

    private

    def not_found(error)
      render json: { error: "Not found" }, status: :not_found
    end

    def unprocessable(error)
      render json: { error: error.message }, status: :unprocessable_entity
    end
  end
end

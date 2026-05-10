module Api
  class UsersController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def setup_required
      render json: { required: User.count.zero? }
    end

    def create
      if User.count > 0
        render json: { error: "First user already created" }, status: :unprocessable_entity
        return
      end

      user = User.new(user_params)
      if user.save
        render json: { token: user.generate_jwt, user: user.as_json(only: [:id, :email, :name]) }, status: :created
      else
        render json: { error: user.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    private

    def user_params
      params.require(:user).permit(:name, :email, :password)
    end
  end
end

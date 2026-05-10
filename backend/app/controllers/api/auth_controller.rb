module Api
  class AuthController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def health
      render json: { status: "ok", time: Time.current.iso8601 }
    end

    def login
      user = User.find_by(email: params[:email])

      if user&.authenticate(params[:password])
        render json: { token: user.generate_jwt, user: user.as_json(only: [:id, :email, :name]) }
      else
        render json: { error: "Invalid credentials" }, status: :unauthorized
      end
    end

    def me
      user = current_user

      # Development fallback
      if !user && Rails.env.development?
        user = User.first
      end

      if user
        render json: user.as_json(only: [:id, :email, :name])
      else
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end

    private

    def current_user
      header = request.headers["Authorization"]
      token = header&.split(" ")&.last
      return nil unless token

      decoded = JWT.decode(token, Rails.application.credentials.secret_key_base, true, { algorithm: "HS256" })
      User.find_by(id: decoded[0]["user_id"]) if decoded
    rescue JWT::ExpiredSignature, JWT::DecodeError
      nil
    end
  end
end

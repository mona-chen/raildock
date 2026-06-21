module Api
  class AuthController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def health
      render json: { status: "ok", time: Time.current.iso8601 }
    end

    def login
      user = User.find_by(email: params[:email])

      if user&.authenticate(params[:password])
        ensure_personal_organization(user)
        render json: { token: user.generate_jwt, user: user_payload_with_orgs(user) }
      else
        render json: { error: "Invalid credentials" }, status: :unauthorized
      end
    end

    def me
      user = current_user

      if user
        ensure_personal_organization(user)
        render json: user_payload_with_orgs(user)
      else
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end

    private

    def jwt_secret
      ENV.fetch("JWT_SECRET_KEY") { Rails.application.credentials.jwt_secret_key || Rails.application.credentials.secret_key_base || Rails.application.secret_key_base }
    end

    def current_user
      header = request.headers["Authorization"]
      token = header&.split(" ")&.last
      return nil unless token

      decoded = JWT.decode(token, jwt_secret, true, { algorithm: "HS256" })
      User.find_by(id: decoded[0]["user_id"]) if decoded
    rescue JWT::ExpiredSignature, JWT::DecodeError
      nil
    end
  end
end

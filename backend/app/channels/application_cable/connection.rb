module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = request.params[:token] || request.headers["Authorization"]&.split(" ")&.last

      if token
        jwt_secret = ENV.fetch("JWT_SECRET_KEY") { Rails.application.credentials.jwt_secret_key || Rails.application.credentials.secret_key_base }
        decoded = JWT.decode(token, jwt_secret, true, { algorithm: "HS256" })
        user = User.find_by(id: decoded[0]["user_id"])
        Rails.logger.info "[ActionCable] Connection authenticated for user #{user.id}" if user
        return user if user
      end

      Rails.logger.warn "[ActionCable] Connection rejected: invalid or missing token"
      reject_unauthorized_connection
    rescue JWT::DecodeError => e
      Rails.logger.warn "[ActionCable] Connection rejected: JWT decode error - #{e.message}"
      reject_unauthorized_connection
    end
  end
end

module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
  end

  private

  def authenticate_user!
    header = request.headers["Authorization"]
    token = header&.split(" ")&.last

    unless token
      render json: { error: "Unauthorized" }, status: :unauthorized and return
    end

    begin
      jwt_secret = ENV["JWT_SECRET_KEY"].presence ||
        Rails.application.credentials.jwt_secret_key ||
        Rails.application.credentials.secret_key_base ||
        Rails.application.secret_key_base
      raise "JWT_SECRET_KEY must be set in production" if Rails.env.production? && jwt_secret.blank?

      decoded = JWT.decode(token, jwt_secret, true, { algorithm: "HS256" })
      @current_user = User.find(decoded[0]["user_id"])
    rescue JWT::ExpiredSignature
      render json: { error: "Token expired" }, status: :unauthorized and return
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render json: { error: "Unauthorized" }, status: :unauthorized and return
    end
  end

  def current_user
    @current_user
  end

  def current_organization
    @current_organization ||= begin
      org_id = request.headers["X-Organization-ID"] || params[:organization_id]
      Organization.find_by(id: org_id) if org_id
    end
  end

  def authorize_organization_access!(organization)
    return true if organization.nil?
    return true if current_user.organizations.include?(organization)
    render json: { error: "Forbidden" }, status: :forbidden
    nil
  end
end

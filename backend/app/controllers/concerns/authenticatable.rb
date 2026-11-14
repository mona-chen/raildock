module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    before_action :validate_organization_context!
  end

  private

  def authenticate_user!
    header = request.headers["Authorization"]
    token = header&.split(" ")&.last

    unless token
      render json: { error: "Unauthorized" }, status: :unauthorized and return
    end

    begin
      jwt_secret = JwtSecret.value
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

  def validate_organization_context!
    current_organization if current_user
  end

  def current_organization
    return @current_organization if defined?(@current_organization)

    org_id = request.headers["X-Organization-ID"].presence || params[:organization_id].presence
    @current_organization = if org_id
      current_user.organizations.find_by(id: org_id).tap do |organization|
        raise ApplicationController::AuthorizationDenied unless organization
      end
    end
  end

  def authorize_organization_access!(organization)
    raise ApplicationController::AuthorizationDenied unless organization && current_user.organizations.exists?(id: organization.id)

    true
  end
end

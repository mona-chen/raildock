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

    return authenticate_api_token!(token) if token.start_with?(ApiToken::PREFIX)

    authenticate_jwt!(token)
  end

  def authenticate_jwt!(token)
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

  # API tokens are delegated users: the membership role still decides what the
  # caller may do, and the token narrows it with scopes and a binding.
  def authenticate_api_token!(secret)
    api_token = ApiToken.authenticate(secret)
    return render json: { error: "Unauthorized", code: "token_invalid" }, status: :unauthorized unless api_token
    return render json: { error: "Token revoked", code: "token_revoked" }, status: :unauthorized if api_token.revoked?
    return render json: { error: "Token expired", code: "token_expired" }, status: :unauthorized if api_token.expired?

    unless api_token.user.organization_memberships.exists?(organization_id: api_token.organization_id)
      return render json: {
        error: "The token owner is no longer a member of this organization",
        code: "membership_revoked"
      }, status: :forbidden
    end

    @current_api_token = api_token
    @current_user = api_token.user
    api_token.touch_last_used!
  end

  def current_user
    @current_user
  end

  def current_api_token
    @current_api_token
  end

  def validate_organization_context!
    current_organization if current_user
  end

  def current_organization
    return @current_organization if defined?(@current_organization)

    # A token belongs to exactly one organization. A foreign header is refused
    # rather than silently ignored, so an agent cannot be pointed at another
    # tenant by a caller that reuses the header.
    if current_api_token
      requested = request.headers["X-Organization-ID"].presence || params[:organization_id].presence
      if requested && requested.to_s != current_api_token.organization_id.to_s
        raise ApplicationController::AuthorizationDenied
      end

      return @current_organization = current_api_token.organization
    end

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

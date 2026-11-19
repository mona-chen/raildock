module Api
  class ApiTokensController < BaseController
    include Authorizable

    rescue_from ActionController::ParameterMissing do |error|
      render json: { error: error.message, code: "invalid_token" }, status: :unprocessable_entity
    end

    def index
      organization = require_organization!
      authorize_organization!(organization, action: :settings)

      render json: { tokens: organization.api_tokens.order(created_at: :desc).map { |token| serialize(token) } }
    end

    def create
      organization = require_organization!
      authorize_organization!(organization, action: :settings)

      token = ApiToken.issue!(organization: organization, user: current_user, **token_params)

      # The secret is shown exactly once; only its digest is stored.
      render json: { token: serialize(token), secret: token.plaintext }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence, code: "invalid_token" }, status: :unprocessable_entity
    rescue ArgumentError => e
      render json: { error: e.message, code: "invalid_token" }, status: :unprocessable_entity
    end

    def destroy
      organization = require_organization!
      authorize_organization!(organization, action: :settings)

      token = organization.api_tokens.find(params[:id])
      token.revoke!

      render json: { token: serialize(token) }
    end

    private

    def require_organization!
      current_organization || raise(ApplicationController::AuthorizationDenied)
    end

    def token_params
      params.require(:token).permit(:name, :project_id, :environment_id, :expires_at, scopes: []).to_h.symbolize_keys
    end

    def serialize(token)
      {
        id: token.id.to_s,
        name: token.name,
        prefix: token.prefix,
        scopes: token.scopes,
        project_id: token.project_id&.to_s,
        environment_id: token.environment_id&.to_s,
        expires_at: token.expires_at&.iso8601,
        last_used_at: token.last_used_at&.iso8601,
        revoked_at: token.revoked_at&.iso8601,
        created_at: token.created_at.iso8601
      }
    end
  end
end

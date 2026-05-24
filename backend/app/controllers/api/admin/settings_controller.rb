module Api
  module Admin
    class SettingsController < BaseController
      before_action :authorize_admin!

      GITHUB_APP_KEYS = %w[
        github_app_slug
        github_app_id
        github_client_id
        github_webhook_secret
        github_app_pem
        github_client_secret
      ].freeze

      # GET /api/admin/settings
      def index
        settings = SystemSetting.where(key: GITHUB_APP_KEYS)
        render json: settings.map { |s| { key: s.key, value: s.value } }
      end

      # PATCH /api/admin/settings
      def update
        settings_params.each do |key, value|
          next unless GITHUB_APP_KEYS.include?(key)
          SystemSetting.set!(key, value.presence)
        end

        render json: { success: true }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/admin/settings/test-github-app
      def test_github_app
        slug = SystemSetting.github_app_slug ||
               GithubAppService.app_slug

        unless slug.present?
          return render json: { error: "GitHub App slug is not configured" }, status: :bad_request
        end

        response = Faraday.get("https://api.github.com/apps/#{slug}")

        if response.success?
          data = JSON.parse(response.body)
          render json: {
            valid: true,
            name: data["name"],
            description: data["description"],
            html_url: data["html_url"]
          }
        else
          render json: {
            valid: false,
            status: response.status,
            error: "GitHub App not found or not accessible"
          }, status: :unprocessable_entity
        end
      rescue JSON::ParserError
        render json: { valid: false, error: "Invalid response from GitHub" }, status: :unprocessable_entity
      end

      private

      def settings_params
        params.permit(*GITHUB_APP_KEYS)
      end

      def authorize_admin!
        unless current_user&.admin?
          render json: { error: "Forbidden - admin access required" }, status: :forbidden
        end
      end
    end
  end
end

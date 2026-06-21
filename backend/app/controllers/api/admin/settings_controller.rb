module Api
  module Admin
    class SettingsController < BaseController
      before_action :authorize_admin!

      ALLOWED_KEYS = (SystemSetting::GITHUB_APP_KEYS + SystemSetting::SMTP_KEYS).freeze

      # GET /api/admin/settings
      def index
        settings = SystemSetting.where(key: ALLOWED_KEYS)
        render json: settings.map { |s| { key: s.key, value: s.read_value } }
      end

      # PATCH /api/admin/settings
      def update
        settings_params.each do |key, value|
          next unless ALLOWED_KEYS.include?(key)
          SystemSetting.set!(key, value.presence)
        end

        SmtpService.apply_from_db!

        render json: { success: true }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/admin/settings/test-smtp
      def test_smtp
        unless SystemSetting.smtp_enabled
          return render json: { error: "SMTP is not configured" }, status: :bad_request
        end

        test_email = params[:email].presence || current_user.email

        SmtpMailer.test_email(to: test_email).deliver_now

        render json: { success: true, email: test_email }
      rescue => e
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
        params.permit(*ALLOWED_KEYS)
      end

      def authorize_admin!
        unless current_user&.admin?
          render json: { error: "Forbidden - admin access required" }, status: :forbidden
        end
      end
    end
  end
end
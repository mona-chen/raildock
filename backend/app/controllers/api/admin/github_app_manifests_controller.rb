module Api
  module Admin
    class GithubAppManifestsController < BaseController
      skip_before_action :authenticate_user!, only: [:callback, :setup]
      before_action :authorize_admin!, only: [:manifest]

      MANIFEST_PERMISSIONS = {
        contents: "read",
        metadata: "read",
        pull_requests: "write",
      }.freeze

      MANIFEST_EVENTS = %w[push pull_request].freeze

      # GET /api/admin/github-app-manifest
      # Returns the manifest JSON for the frontend to submit to GitHub
      def manifest
        base_url = request.base_url

        manifest = {
          name: "RailDock",
          url: base_url,
          description: "RailDock - Self-hosted deployment platform",
          hook_attributes: {
            url: "#{base_url}/api/github-apps/webhook",
            active: true,
          },
          redirect_url: "#{base_url}/api/admin/github-app-manifest/callback",
          setup_url: "#{base_url}/api/admin/github-app-manifest/setup",
          setup_on_update: true,
          public: true,
          default_permissions: MANIFEST_PERMISSIONS,
          default_events: MANIFEST_EVENTS,
        }

        render json: {
          manifest: manifest,
          form_url: "https://github.com/settings/apps/new?state=#{generate_state}",
        }
      end

      # GET /api/admin/github-app-manifest/callback
      # GitHub redirects here after the user creates the app
      def callback
        code = params[:code]
        state = params[:state]

        unless code.present?
          return redirect_to frontend_redirect_url(github_app_manifest: "error", message: "Missing code from GitHub"), allow_other_host: true
        end

        unless valid_state?(state)
          return redirect_to frontend_redirect_url(github_app_manifest: "error", message: "Invalid state parameter"), allow_other_host: true
        end

        # Exchange the temporary code for app credentials
        credentials = exchange_code(code)

        unless credentials
          return redirect_to frontend_redirect_url(github_app_manifest: "error", message: "Failed to exchange code with GitHub"), allow_other_host: true
        end

        # Store all credentials in SystemSetting
        store_credentials(credentials)

        redirect_to frontend_redirect_url(github_app_manifest: "success"), allow_other_host: true
      rescue => e
        Rails.logger.error "GitHub App Manifest callback failed: #{e.message}"
        redirect_to frontend_redirect_url(github_app_manifest: "error", message: "Internal error"), allow_other_host: true
      end

      # GET /api/admin/github-app-manifest/setup
      # GitHub redirects here after app installation (setup_url)
      def setup
        installation_id = params[:installation_id]
        if installation_id.present?
          redirect_to frontend_redirect_url(github_app_manifest: "setup_complete", installation_id: installation_id), allow_other_host: true
        else
          redirect_to frontend_redirect_url(github_app_manifest: "setup_complete"), allow_other_host: true
        end
      end

      private

      def generate_state
        # Simple signed state to prevent CSRF
        payload = { exp: 1.hour.from_now.to_i, nonce: SecureRandom.hex(8) }
        JWT.encode(payload, Rails.application.secret_key_base, "HS256")
      end

      def valid_state?(state)
        return false unless state.present?
        JWT.decode(state, Rails.application.secret_key_base, true, { algorithm: "HS256", verify_expiration: true })
        true
      rescue JWT::DecodeError, JWT::ExpiredSignature
        false
      end

      def exchange_code(code)
        response = Faraday.post(
          "https://api.github.com/app-manifests/#{code}/conversions",
          "",
          {
            "Accept" => "application/vnd.github+json",
            "X-GitHub-Api-Version" => "2022-11-28",
          }
        )

        return nil unless response.success?

        data = JSON.parse(response.body)
        {
          id: data["id"],
          slug: data["slug"],
          name: data["name"],
          client_id: data["client_id"],
          client_secret: data["client_secret"],
          pem: data["pem"],
          webhook_secret: data["webhook_secret"],
          html_url: data["html_url"],
        }
      rescue JSON::ParserError, Faraday::Error => e
        Rails.logger.error "GitHub App Manifest exchange failed: #{e.message}"
        nil
      end

      def store_credentials(credentials)
        SystemSetting.set!("github_app_id", credentials[:id].to_s)
        SystemSetting.set!("github_app_slug", credentials[:slug])
        SystemSetting.set!("github_client_id", credentials[:client_id])
        SystemSetting.set!("github_client_secret", credentials[:client_secret])
        SystemSetting.set!("github_app_pem", credentials[:pem])
        SystemSetting.set!("github_webhook_secret", credentials[:webhook_secret])
      end

      def frontend_redirect_url(params = {})
        base = ENV.fetch("FRONTEND_URL") { request.base_url }
        query = URI.encode_www_form(params)
        "#{base}/#/dashboard/settings?tab=git-sources&#{query}"
      end

      def authorize_admin!
        unless current_user&.admin?
          render json: { error: "Forbidden - admin access required" }, status: :forbidden
        end
      end
    end
  end
end

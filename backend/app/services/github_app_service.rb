require "openssl"
require "jwt"

class GithubAppService
  # GitHub App JWT expires after 10 minutes; we use 9 to be safe.
  JWT_TTL = 540

  class << self
    def app_id
      SystemSetting.github_app_id ||
        Rails.application.credentials.dig(:github_app, :app_id)
    end

    def private_key_pem
      SystemSetting.github_app_pem ||
        Rails.application.credentials.dig(:github_app, :private_key)
    end

    def client_id
      SystemSetting.github_client_id ||
        Rails.application.credentials.dig(:github_app, :client_id)
    end

    def client_secret
      SystemSetting.github_client_secret ||
        Rails.application.credentials.dig(:github_app, :client_secret)
    end

    def webhook_secret
      SystemSetting.github_webhook_secret ||
        Rails.application.credentials.dig(:github_app, :webhook_secret)
    end

    def app_slug
      SystemSetting.github_app_slug ||
        Rails.application.credentials.dig(:github_app, :app_slug) ||
        ENV.fetch("GITHUB_APP_SLUG", nil)
    end

    def enabled?
      app_id.present? && private_key_pem.present?
    end

    # Generate a JWT to authenticate as the GitHub App itself
    def generate_jwt
      raise "GitHub App credentials not configured" unless enabled?

      private_key = OpenSSL::PKey::RSA.new(private_key_pem)
      payload = {
        iat: Time.now.to_i - 60,
        exp: Time.now.to_i + JWT_TTL,
        iss: app_id.to_i
      }
      JWT.encode(payload, private_key, "RS256")
    end

    # Get an installation access token (short-lived, 1 hour)
    def installation_token(installation_id)
      raise "GitHub App credentials not configured" unless enabled?
      raise "Installation ID required" if installation_id.blank?

      jwt = generate_jwt
      response = Faraday.post(
        "https://api.github.com/app/installations/#{installation_id}/access_tokens",
        "",
        {
          "Authorization" => "Bearer #{jwt}",
          "Accept" => "application/vnd.github+json",
          "X-GitHub-Api-Version" => "2022-11-28"
        }
      )

      unless response.success?
        Rails.logger.error "GitHub App token exchange failed: #{response.status} #{response.body}"
        raise "Failed to generate installation token: #{response.status}"
      end

      JSON.parse(response.body)["token"]
    end

    # Create an Octokit client authenticated as the installation
    def installation_client(installation_id)
      token = installation_token(installation_id)
      Octokit::Client.new(access_token: token)
    end

    def repository_client(git_source)
      raise "Git source must use a GitHub App installation" unless git_source&.github_app?

      installation_client(git_source.installation_id)
    end

    def user_authorization_url(state, callback_url:)
      raise "GitHub App OAuth credentials not configured" if client_id.blank? || client_secret.blank?

      query = URI.encode_www_form(
        client_id: client_id,
        redirect_uri: callback_url,
        state: state
      )
      "https://github.com/login/oauth/authorize?#{query}"
    end

    def exchange_user_code(code, callback_url:)
      raise "GitHub App OAuth credentials not configured" if client_id.blank? || client_secret.blank?

      response = Faraday.post(
        "https://github.com/login/oauth/access_token",
        URI.encode_www_form(
          client_id: client_id,
          client_secret: client_secret,
          code: code,
          redirect_uri: callback_url
        ),
        {
          "Accept" => "application/json",
          "Content-Type" => "application/x-www-form-urlencoded"
        }
      )
      data = JSON.parse(response.body)
      token = data["access_token"]
      error = data["error_description"] || data["error"]
      raise "Failed to exchange GitHub user code: #{error || response.status}" unless response.success? && token.present?

      token
    end

    def user_installations(user_token)
      installations = []
      page = 1

      loop do
        response = Faraday.get(
          "https://api.github.com/user/installations",
          { per_page: 100, page: page },
          {
            "Authorization" => "Bearer #{user_token}",
            "Accept" => "application/vnd.github+json",
            "X-GitHub-Api-Version" => "2022-11-28"
          }
        )
        raise "Failed to list GitHub user installations: #{response.status}" unless response.success?

        page_installations = JSON.parse(response.body)["installations"] || []
        installations.concat(page_installations)
        break if page_installations.length < 100

        page += 1
      end

      installations
    end

    # Fetch details for a specific installation
    def installation_details(installation_id)
      raise "GitHub App credentials not configured" unless enabled?
      raise "Installation ID required" if installation_id.blank?

      jwt = generate_jwt
      response = Faraday.get(
        "https://api.github.com/app/installations/#{installation_id}",
        {},
        {
          "Authorization" => "Bearer #{jwt}",
          "Accept" => "application/vnd.github+json",
          "X-GitHub-Api-Version" => "2022-11-28"
        }
      )

      unless response.success?
        Rails.logger.error "GitHub App installation details failed: #{response.status} #{response.body}"
        raise "Failed to fetch installation details: #{response.status}"
      end

      JSON.parse(response.body)
    end

    # List all repositories accessible to an installation (paginated)
    # Uses the installation token to call /installation/repositories
    def list_repos(installation_id)
      raise "GitHub App credentials not configured" unless enabled?
      raise "Installation ID required" if installation_id.blank?

      token = installation_token(installation_id)
      all_repos = []
      page = 1

      loop do
        response = Faraday.get(
          "https://api.github.com/installation/repositories",
          { per_page: 100, page: page },
          {
            "Authorization" => "Bearer #{token}",
            "Accept" => "application/vnd.github+json",
            "X-GitHub-Api-Version" => "2022-11-28"
          }
        )

        unless response.success?
          Rails.logger.error "GitHub App repo list failed: #{response.status} #{response.body}"
          raise "Failed to list repositories: #{response.status}"
        end

        data = JSON.parse(response.body)
        repos = data["repositories"] || []
        break if repos.empty?

        all_repos.concat(repos.map do |repo|
          {
            id: repo["id"],
            full_name: repo["full_name"],
            default_branch: repo["default_branch"],
            private: repo["private"],
            clone_url: repo["clone_url"],
            ssh_url: repo["ssh_url"],
            html_url: repo["html_url"]
          }
        end)

        break if repos.length < 100
        page += 1
      end

      all_repos
    rescue JSON::ParserError, Faraday::Error => e
      Rails.logger.error "GitHub App repo list failed: #{e.message}"
      raise
    end

    # Delete an installation from GitHub
    def delete_installation(installation_id)
      raise "GitHub App credentials not configured" unless enabled?
      raise "Installation ID required" if installation_id.blank?

      jwt = generate_jwt
      response = Faraday.delete(
        "https://api.github.com/app/installations/#{installation_id}",
        {},
        {
          "Authorization" => "Bearer #{jwt}",
          "Accept" => "application/vnd.github+json",
          "X-GitHub-Api-Version" => "2022-11-28"
        }
      )

      unless response.success?
        Rails.logger.error "GitHub App installation deletion failed: #{response.status} #{response.body}"
        raise "Failed to delete installation: #{response.status}"
      end

      true
    rescue Faraday::Error => e
      Rails.logger.error "GitHub App installation deletion failed: #{e.message}"
      raise
    end
  end
end

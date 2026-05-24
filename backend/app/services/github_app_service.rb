require 'openssl'
require 'jwt'

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
        ENV.fetch('GITHUB_APP_SLUG', nil)
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
      JWT.encode(payload, private_key, 'RS256')
    end

    # Get an installation access token (short-lived, 1 hour)
    def installation_token(installation_id)
      raise "GitHub App credentials not configured" unless enabled?
      raise "Installation ID required" if installation_id.blank?

      jwt = generate_jwt
      response = Faraday.post(
        "https://api.github.com/app/installations/#{installation_id}/access_tokens",
        '',
        {
          'Authorization' => "Bearer #{jwt}",
          'Accept' => 'application/vnd.github+json',
          'X-GitHub-Api-Version' => '2022-11-28'
        }
      )

      unless response.success?
        Rails.logger.error "GitHub App token exchange failed: #{response.status} #{response.body}"
        raise "Failed to generate installation token: #{response.status}"
      end

      JSON.parse(response.body)['token']
    end

    # Create an Octokit client authenticated as the installation
    def installation_client(installation_id)
      token = installation_token(installation_id)
      Octokit::Client.new(access_token: token)
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
          'Authorization' => "Bearer #{jwt}",
          'Accept' => 'application/vnd.github+json',
          'X-GitHub-Api-Version' => '2022-11-28'
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
            'Authorization' => "Bearer #{token}",
            'Accept' => 'application/vnd.github+json',
            'X-GitHub-Api-Version' => '2022-11-28'
          }
        )

        unless response.success?
          Rails.logger.error "GitHub App repo list failed: #{response.status} #{response.body}"
          raise "Failed to list repositories: #{response.status}"
        end

        data = JSON.parse(response.body)
        repos = data['repositories'] || []
        break if repos.empty?

        all_repos.concat(repos.map do |repo|
          {
            id: repo['id'],
            full_name: repo['full_name'],
            default_branch: repo['default_branch'],
            private: repo['private'],
            clone_url: repo['clone_url']
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
  end
end

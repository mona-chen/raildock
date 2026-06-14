require "rails_helper"

RSpec.describe "Api::GithubAppsController", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/github-apps/callback" do
    it "redirects with error without installation_id" do
      get "/api/github-apps/callback"
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(%r{github_app=error})
    end

    it "stores a GitHub organization installation in a personal RailDock workspace" do
      state = JWT.encode(
        { user_id: user.id, installation_id: "12345", exp: 5.minutes.from_now.to_i },
        Rails.application.secret_key_base,
        "HS256"
      )
      allow(GithubAppService).to receive(:exchange_user_code).with(
        "oauth-code",
        callback_url: "http://www.example.com/api/github-apps/callback"
      ).and_return("user-token")
      allow(GithubAppService).to receive(:user_installations).with("user-token").and_return(
        [ { "id" => 12345, "account" => { "type" => "Organization", "login" => "acme" } } ]
      )
      allow(GithubSyncReposJob).to receive(:perform_later)

      expect {
        get "/api/github-apps/callback", params: { code: "oauth-code", state: state }
      }.to change(GitSource, :count).by(1)

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(%r{github_app=success})
      source = GitSource.last
      expect(source.provider).to eq("github")
      expect(source.installation_id).to eq("12345")
      expect(source.connected).to be true
      expect(source.account_type).to eq("organization")
      expect(source.user).to eq(user)
      expect(source.organization).to be_nil
      expect(Organization.find_by(slug: "acme")).to be_nil
    end

    it "stores an installation in the selected RailDock organization" do
      organization = create(:organization)
      create(:organization_membership, organization: organization, user: user)
      state = JWT.encode(
        {
          user_id: user.id,
          organization_id: organization.id,
          installation_id: "67890",
          exp: 5.minutes.from_now.to_i
        },
        Rails.application.secret_key_base,
        "HS256"
      )
      allow(GithubAppService).to receive(:exchange_user_code).and_return("user-token")
      allow(GithubAppService).to receive(:user_installations).and_return(
        [ { "id" => 67890, "account" => { "type" => "User", "login" => "monalisa" } } ]
      )
      allow(GithubSyncReposJob).to receive(:perform_later)

      get "/api/github-apps/callback", params: { code: "oauth-code", state: state }

      expect(response).to redirect_to(%r{github_app=success})
      source = GitSource.last
      expect(source.account_type).to eq("personal")
      expect(source.organization).to eq(organization)
      expect(source.user).to be_nil
    end

    it "rejects an installation the authorized GitHub user cannot access" do
      state = JWT.encode(
        { user_id: user.id, installation_id: "12345", exp: 5.minutes.from_now.to_i },
        Rails.application.secret_key_base,
        "HS256"
      )
      allow(GithubAppService).to receive(:exchange_user_code).and_return("user-token")
      allow(GithubAppService).to receive(:user_installations).and_return([])

      expect {
        get "/api/github-apps/callback", params: { code: "oauth-code", state: state }
      }.not_to change(GitSource, :count)

      expect(response).to redirect_to(%r{github_app=error})
    end
  end

  describe "POST /api/github-apps/finish-setup" do
    before do
      allow(GithubSyncReposJob).to receive(:perform_later)
      allow(GithubAppService).to receive(:user_authorization_url)
    end

    it "starts user authorization for a personal RailDock workspace" do
      allow(GithubAppService).to receive(:user_authorization_url).and_return("https://github.com/login/oauth/authorize?state=signed")

      post "/api/github-apps/finish-setup",
        params: { installation_id: "12345" },
        headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["authorization_url"]).to eq("https://github.com/login/oauth/authorize?state=signed")
      expect(GitSource.find_by(installation_id: "12345")).to be_nil
    end

    it "includes an authorized RailDock organization in signed setup state" do
      organization = create(:organization)
      create(:organization_membership, organization: organization, user: user)
      allow(GithubAppService).to receive(:user_authorization_url) do |state, callback_url:|
        payload = JWT.decode(state, Rails.application.secret_key_base, true, algorithm: "HS256").first
        expect(payload).to include(
          "user_id" => user.id,
          "organization_id" => organization.id.to_s,
          "installation_id" => "67890"
        )
        expect(callback_url).to end_with("/api/github-apps/callback")
        "https://github.com/login/oauth/authorize"
      end

      post "/api/github-apps/finish-setup",
        params: { installation_id: "67890", organization_id: organization.id },
        headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
    end

    it "rejects a RailDock organization the user cannot access" do
      organization = create(:organization)

      post "/api/github-apps/finish-setup",
        params: { installation_id: "99999", organization_id: organization.id },
        headers: auth_headers(user)

      expect(response).to have_http_status(:forbidden)
      expect(GithubAppService).not_to have_received(:user_authorization_url)
    end
  end

  describe "POST /api/github-apps/webhook" do
    let(:project) { create(:project, user: user, server: nil) }
    let!(:service) { create(:service, project: project, git_repo: "https://github.com/acme/app.git", branch: "main", auto_deploy: true) }
    let!(:git_source) do
      create(
        :git_source,
        user: user,
        provider: "github",
        access_token: nil,
        installation_id: "12345",
        auth_method: :oauth_app,
        metadata: {
          "repos" => [
            { "id" => 1, "full_name" => "acme/app", "default_branch" => "main", "clone_url" => "https://github.com/acme/app.git" }
          ]
        }
      )
    end

    it "returns 204 for a valid push event" do
      payload = {
        ref: "refs/heads/main",
        after: "abc1234",
        installation: { id: "12345" },
        repository: { full_name: "acme/app", clone_url: "https://github.com/acme/app.git", default_branch: "main" }
      }.to_json

      expect {
        post "/api/github-apps/webhook",
             params: payload,
             headers: {
               "CONTENT_TYPE" => "application/json",
               "X-GitHub-Event" => "push",
               "X-Hub-Signature-256" => "sha256=invalid"
             }
      }.to change(Deployment, :count).by(1)

      # Without webhook secret configured, signature verification is skipped in dev
      expect(response).to have_http_status(:no_content)
      deployment = Deployment.last
      expect(deployment.service).to eq(service)
      expect(deployment.triggered_by).to eq("github_app")
      expect(deployment.commit_sha).to eq("abc1234")
    end

    it "does not deploy services outside the installation owner scope" do
      other_project = create(:project, user: create(:user), server: nil)
      create(:service, project: other_project, git_repo: "acme/app", branch: "main", auto_deploy: true)

      payload = {
        ref: "refs/heads/main",
        after: "abc1234",
        installation: { id: "12345" },
        repository: { full_name: "acme/app", clone_url: "https://github.com/acme/app.git", default_branch: "main" }
      }.to_json

      post "/api/github-apps/webhook",
           params: payload,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "X-GitHub-Event" => "push",
             "X-Hub-Signature-256" => "sha256=invalid"
           }

      expect(response).to have_http_status(:no_content)
      expect(Deployment.count).to eq(1)
    end

    it "deduplicates repeated GitHub deliveries" do
      payload = {
        ref: "refs/heads/main",
        after: "abc1234",
        installation: { id: "12345" },
        repository: { full_name: "acme/app", clone_url: "https://github.com/acme/app.git", default_branch: "main" }
      }.to_json
      headers = {
        "CONTENT_TYPE" => "application/json",
        "X-GitHub-Event" => "push",
        "X-GitHub-Delivery" => "delivery-123",
        "X-Hub-Signature-256" => "sha256=invalid"
      }

      expect {
        2.times { post "/api/github-apps/webhook", params: payload, headers: headers }
      }.to change(Deployment, :count).by(1)
    end

    it "creates separate deployments for different commits" do
      headers = {
        "CONTENT_TYPE" => "application/json",
        "X-GitHub-Event" => "push",
        "X-Hub-Signature-256" => "sha256=invalid"
      }

      expect {
        %w[abc1234 def5678].each do |commit|
          post "/api/github-apps/webhook",
            params: {
              ref: "refs/heads/main",
              after: commit,
              installation: { id: "12345" },
              repository: { full_name: "acme/app", clone_url: "https://github.com/acme/app.git", default_branch: "main" }
            }.to_json,
            headers: headers
        end
      }.to change(Deployment, :count).by(2)
    end

    it "returns 403 for invalid signature when secret is configured" do
      allow(GithubAppService).to receive(:webhook_secret).and_return("secret")

      payload = { ref: "refs/heads/main", repository: { full_name: "acme/app" } }.to_json
      post "/api/github-apps/webhook",
           params: payload,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "X-GitHub-Event" => "push",
             "X-Hub-Signature-256" => "sha256=invalid"
           }

      expect(response).to have_http_status(:forbidden)
    end
  end
end

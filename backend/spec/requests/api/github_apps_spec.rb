require "rails_helper"

RSpec.describe "Api::GithubAppsController", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/github-apps/callback" do
    it "redirects with error without installation_id" do
      get "/api/github-apps/callback"
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(%r{github_app=error})
    end

    it "creates a GitSource for the installation and redirects" do
      allow(GithubAppService).to receive(:installation_details).with("12345").and_return(
        { "account" => { "type" => "User", "login" => "monalisa" } }
      )
      allow(GithubSyncReposJob).to receive(:perform_later)

      expect {
        get "/api/github-apps/callback", params: { installation_id: "12345", state: Base64.urlsafe_encode64({ user_id: user.id }.to_json) }
      }.to change(GitSource, :count).by(1)

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(%r{github_app=success})
      source = GitSource.last
      expect(source.provider).to eq("github")
      expect(source.installation_id).to eq("12345")
      expect(source.connected).to be true
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

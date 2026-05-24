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
    it "returns 204 for a valid push event" do
      payload = {
        ref: "refs/heads/main",
        after: "abc1234",
        repository: { full_name: "acme/app" }
      }.to_json

      post "/api/github-apps/webhook",
           params: payload,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "X-GitHub-Event" => "push",
             "X-Hub-Signature-256" => "sha256=invalid"
           }

      # Without webhook secret configured, signature verification is skipped in dev
      expect(response).to have_http_status(:no_content)
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

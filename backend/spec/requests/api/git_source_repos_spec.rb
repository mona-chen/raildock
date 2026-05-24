require "rails_helper"

RSpec.describe "Api::GitSourcesController#repos", type: :request do
  let(:user) { create(:user) }
  let(:git_source) { create(:git_source, user: user, provider: "github", metadata: { "repos" => [
    { "id" => 1, "full_name" => "acme/app", "default_branch" => "main", "private" => false },
    { "id" => 2, "full_name" => "acme/api", "default_branch" => "master", "private" => true },
  ] }) }

  describe "GET /api/git-sources/:id/repos" do
    it "returns repos from the git source metadata" do
      get "/api/git-sources/#{git_source.id}/repos", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["repos"]).to be_an(Array)
      expect(json["repos"].length).to eq(2)
      expect(json["repos"][0]["full_name"]).to eq("acme/app")
      expect(json["syncing"]).to eq(false)
    end

    it "returns 404 for non-existent source" do
      get "/api/git-sources/99999/repos", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end

    it "triggers async sync when repos are empty and stale" do
      empty_source = create(:git_source, user: user, provider: "gitlab", metadata: { "repos" => [] })
      empty_source.update_column(:updated_at, 10.minutes.ago)

      expect {
        get "/api/git-sources/#{empty_source.id}/repos", headers: auth_headers(user)
      }.to have_enqueued_job(GithubSyncReposJob)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["syncing"]).to eq(true)
    end

    it "always triggers sync when repos are empty" do
      empty_source = create(:git_source, user: user, provider: "gitlab", metadata: { "repos" => [] })

      expect {
        get "/api/git-sources/#{empty_source.id}/repos", headers: auth_headers(user)
      }.to have_enqueued_job(GithubSyncReposJob)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["syncing"]).to eq(true)
    end

    it "does not trigger sync when repos exist and recently synced" do
      get "/api/git-sources/#{git_source.id}/repos", headers: auth_headers(user)

      expect {
        get "/api/git-sources/#{git_source.id}/repos", headers: auth_headers(user)
      }.not_to have_enqueued_job(GithubSyncReposJob)

      expect(response).to have_http_status(:ok)
    end
  end
end

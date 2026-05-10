require "rails_helper"

RSpec.describe "Api::GitSourcesController", type: :request do
  let(:user) { create(:user) }
  let!(:git_source) { create(:git_source) }

  describe "GET /api/git-sources" do
    context "when unauthenticated" do
      it "returns 401" do
        get "/api/git-sources"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "returns all git sources" do
        get "/api/git-sources", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["provider"]).to eq("github")
      end
    end
  end

  describe "POST /api/git-sources" do
    let(:valid_params) do
      {
        provider: "gitlab",
        access_token: "glpat-123456",
        username: "testuser"
      }
    end

    context "when unauthenticated" do
      it "returns 401" do
        post "/api/git-sources", params: valid_params
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "creates a connected git source" do
        expect {
          post "/api/git-sources", params: valid_params, headers: auth_headers(user)
        }.to change(GitSource, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["provider"]).to eq("gitlab")
        expect(json["connected"]).to be true
      end

      it "returns 422 with invalid data" do
        post "/api/git-sources", params: { provider: "" }, headers: auth_headers(user)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /api/git-sources/:id" do
    context "when unauthenticated" do
      it "returns 401" do
        delete "/api/git-sources/#{git_source.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      it "disconnects the git source and clears token" do
        delete "/api/git-sources/#{git_source.id}", headers: auth_headers(user)

        expect(response).to have_http_status(:no_content)
        git_source.reload
        expect(git_source.connected).to be false
        expect(git_source.access_token).to be_nil
      end

      it "returns 404 for non-existent git source" do
        delete "/api/git-sources/999999", headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end

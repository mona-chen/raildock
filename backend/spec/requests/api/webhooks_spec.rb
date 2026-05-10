require "rails_helper"

RSpec.describe "Api::WebhooksController", type: :request do
  let!(:service) { create(:service, git_repo: "owner/repo-name") }

  describe "POST /api/webhooks/deploy" do
    context "with GitHub payload" do
      let(:github_payload) do
        {
          repository: { full_name: "owner/repo-name" },
          ref: "refs/heads/main"
        }
      end

      it "triggers deployments for matching services" do
        expect {
          post "/api/webhooks/deploy", params: github_payload
        }.to change(Deployment, :count).by(1)
          .and change { service.reload.status }.to("deploying")

        expect(response).to have_http_status(:accepted)
      end

      it "returns 404 when no services match the repo" do
        post "/api/webhooks/deploy", params: {
          repository: { full_name: "owner/non-existent" },
          ref: "refs/heads/main"
        }

        expect(response).to have_http_status(:not_found)
      end

      it "returns 400 when repository info is missing" do
        post "/api/webhooks/deploy", params: { ref: "refs/heads/main" }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with GitLab payload" do
      let(:gitlab_payload) do
        {
          project: { path_with_namespace: "owner/repo-name" },
          ref: "refs/heads/develop"
        }
      end

      it "triggers deployments for matching services with correct branch" do
        expect {
          post "/api/webhooks/deploy", params: gitlab_payload
        }.to change(Deployment, :count).by(1)

        expect(response).to have_http_status(:accepted)
        deployment = Deployment.last
        expect(deployment.branch).to eq("develop")
      end
    end

    context "with missing ref" do
      it "defaults branch to main" do
        expect {
          post "/api/webhooks/deploy", params: { repository: { full_name: "owner/repo-name" } }
        }.to change(Deployment, :count).by(1)

        expect(response).to have_http_status(:accepted)
        deployment = Deployment.last
        expect(deployment.branch).to eq("main")
      end
    end

    it "does not require authentication" do
      post "/api/webhooks/deploy", params: {
        repository: { full_name: "owner/repo-name" },
        ref: "refs/heads/main"
      }

      expect(response).to have_http_status(:accepted)
    end
  end
end

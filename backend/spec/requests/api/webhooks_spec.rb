require "rails_helper"

RSpec.describe "Api::WebhooksController", type: :request do
  let(:project) { create(:project) }
  let!(:service) { create(:service, project: project, git_repo: "acme/app", branch: "main") }

  describe "POST /api/webhooks/deploy" do
    context "without webhook secret configured" do
      it "triggers deployment" do
        expect {
          post "/api/webhooks/deploy", params: {
            repository: { full_name: "acme/app" },
            ref: "refs/heads/main"
          }
        }.to change(Deployment, :count).by(1)

        expect(response).to have_http_status(:accepted)
      end

      it "matches GitHub clone URLs and preserves branch names with slashes" do
        service.update!(git_repo: "https://github.com/acme/app.git", branch: "feature/api")

        expect {
          post "/api/webhooks/deploy", params: {
            repository: { full_name: "acme/app", clone_url: "https://github.com/acme/app.git" },
            ref: "refs/heads/feature/api",
            after: "abc1234"
          }
        }.to change(Deployment, :count).by(1)

        expect(response).to have_http_status(:accepted)
        deployment = Deployment.last
        expect(deployment.branch).to eq("feature/api")
        expect(deployment.commit_sha).to eq("abc1234")
        expect(deployment.triggered_by).to eq("webhook")
      end

      it "does not trigger deployment for non-matching branches" do
        expect {
          post "/api/webhooks/deploy", params: {
            repository: { full_name: "acme/app" },
            ref: "refs/heads/develop"
          }
        }.not_to change(Deployment, :count)

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with webhook secret configured" do
      before do
        allow(Rails.application).to receive(:credentials).and_return(
          ActiveSupport::OrderedOptions.new.tap { |c| c.webhook_secret = "supersecret" }
        )
      end

      it "returns 403 without signature" do
        post "/api/webhooks/deploy", params: {
          repository: { full_name: "acme/app" },
          ref: "refs/heads/main"
        }

        expect(response).to have_http_status(:forbidden)
      end

      it "accepts valid GitHub signature" do
        payload = {
          repository: { full_name: "acme/app" },
          ref: "refs/heads/main"
        }.to_json

        signature = 'sha256=' + OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new('sha256'), "supersecret", payload
        )

        expect {
          post "/api/webhooks/deploy",
               params: payload,
               headers: {
                 "CONTENT_TYPE" => "application/json",
                 "X-Hub-Signature-256" => signature
               }
        }.to change(Deployment, :count).by(1)

        expect(response).to have_http_status(:accepted)
      end

      it "accepts valid GitLab token" do
        expect {
          post "/api/webhooks/deploy", params: {
            repository: { full_name: "acme/app" },
            ref: "refs/heads/main"
          }, headers: { "X-Gitlab-Token" => "supersecret" }
        }.to change(Deployment, :count).by(1)

        expect(response).to have_http_status(:accepted)
      end
    end
  end

  describe "POST /api/services/:id/webhooks/:token/deploy" do
    it "returns 404 for invalid token" do
      post "/api/services/#{service.id}/webhooks/invalid-token/deploy"
      expect(response).to have_http_status(:not_found)
    end

    it "triggers deployment with valid token" do
      service.update!(webhook_token: "valid-token-123")

      expect {
        post "/api/services/#{service.id}/webhooks/valid-token-123/deploy"
      }.to change(Deployment, :count).by(1)

      expect(response).to have_http_status(:accepted)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("deploying")
      expect(json["deployment_id"]).to be_present

      deployment = Deployment.last
      expect(deployment.triggered_by).to eq("webhook")
    end

    it "accepts optional branch parameter" do
      service.update!(webhook_token: "valid-token-123")

      post "/api/services/#{service.id}/webhooks/valid-token-123/deploy", params: { branch: "staging" }

      expect(response).to have_http_status(:accepted)
      deployment = Deployment.last
      expect(deployment.branch).to eq("staging")
    end

    it "falls back to service branch when no branch param" do
      service.update!(webhook_token: "valid-token-123", branch: "develop")

      post "/api/services/#{service.id}/webhooks/valid-token-123/deploy"

      deployment = Deployment.last
      expect(deployment.branch).to eq("develop")
    end
  end
end

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
end

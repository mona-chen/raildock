require "rails_helper"

RSpec.describe "Api::V1 agent surface", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, organization: organization, server: server) }
  let(:production) { project.environments.find_by!(is_default: true) }
  let(:staging) { project.environments.create!(name: "staging", slug: "staging") }
  let!(:web) { create(:service, project: project, environment: production, name: "web", dokku_app_name: "demo-web") }
  let!(:worker) { create(:service, project: project, environment: staging, name: "worker", dokku_app_name: "demo-worker") }
  let!(:link) { ServiceLink.create!(from_service: web, to_service: worker) }
  let(:secret) { "hunter2-production-password" }
  let!(:variable) { create(:environment_variable, service: web, key: "DATABASE_URL", value: secret) }

  def token_for(**overrides)
    ApiToken.issue!(organization: organization, user: user, name: "agent", scopes: [ "read" ], **overrides)
  end

  def token_headers(token)
    { "Authorization" => "Bearer #{token.plaintext}", "X-Organization-ID" => organization.id.to_s }
  end

  describe "GET /api/v1/context" do
    it "returns topology and capabilities without secrets" do
      get "/api/v1/context", headers: token_headers(token_for)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig("organization", "id")).to eq(organization.id.to_s)
      expect(body.dig("actor", "type")).to eq("api_token")
      expect(body["capabilities"]).to include("read" => true, "deploy" => false, "destructive" => false)
      expect(body["servers"].map { |entry| entry["id"] }).to eq([ server.id.to_s ])

      project_json = body["projects"].first
      expect(project_json["services"].map { |entry| entry["name"] }).to contain_exactly("web", "worker")
      expect(project_json["links"]).to contain_exactly(
        { "from_service_id" => web.id.to_s, "to_service_id" => worker.id.to_s }
      )
      expect(response.body).not_to include(secret)
      expect(response.body).not_to include(web.webhook_token)
    end

    it "requires an organization context" do
      get "/api/v1/context", headers: auth_headers(user)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("organization_required")
    end

    it "refuses a token used against another organization" do
      other = create(:organization)

      get "/api/v1/context", headers: {
        "Authorization" => "Bearer #{token_for.plaintext}",
        "X-Organization-ID" => other.id.to_s
      }

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects an expired token" do
      token = token_for(expires_at: 1.hour.from_now)
      token.update_column(:expires_at, 1.minute.ago)

      get "/api/v1/context", headers: token_headers(token)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["code"]).to eq("token_expired")
    end

    it "rejects a token whose owner lost membership" do
      token = token_for
      membership.destroy!

      get "/api/v1/context", headers: token_headers(token)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("membership_revoked")
    end
  end

  describe "GET /api/v1/projects/:id" do
    it "returns environments, manifest state and deletion state" do
      get "/api/v1/projects/#{project.id}", headers: token_headers(token_for)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["environments"].map { |entry| entry["slug"] }).to include("production", "staging")
      expect(body["manifest"]).to include("configured" => false, "synced" => false)
      expect(body["deletion"]).to include("pending" => false, "status" => nil)
    end

    it "does not leak another organization's project" do
      other_project = create(:project, organization: create(:organization))

      get "/api/v1/projects/#{other_project.id}", headers: token_headers(token_for)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/services/:id" do
    it "lists variable names and build settings without values" do
      get "/api/v1/services/#{web.id}", headers: token_headers(token_for)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["variables"]).to eq([ { "key" => "DATABASE_URL", "source" => nil, "dokku_internal" => false } ])
      expect(body["webhook_configured"]).to be(true)
      expect(body["links"]).to include("outgoing_service_ids" => [ worker.id.to_s ])
      expect(response.body).not_to include(secret)
      expect(body).not_to have_key("webhook_token")
    end

    it "hides services outside the token's environment binding" do
      token = token_for(environment_id: staging.id)

      get "/api/v1/services/#{web.id}", headers: token_headers(token)
      expect(response).to have_http_status(:not_found)

      get "/api/v1/services/#{worker.id}", headers: token_headers(token)
      expect(response).to have_http_status(:ok)
    end

    it "hides projects outside the token's project binding" do
      other = create(:project, organization: organization, server: server)
      token = token_for(project_id: project.id)

      get "/api/v1/projects/#{other.id}", headers: token_headers(token)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/services/:id/diagnose" do
    it "composes stored evidence without contacting the host" do
      deployment = create(:deployment, service: web, status: :failed, build_log: "boom password=#{secret}")
      create(:service_metric, service: web, sampled_at: 5.minutes.ago)
      create(:activity_event, project: project, message: "restart failed")

      expect(DokkuEngine).not_to receive(:new)

      get "/api/v1/services/#{web.id}/diagnose", headers: token_headers(token_for)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig("status", "healthy")).to be(false)
      expect(body.dig("status", "signals")).to include("Last deployment failed")
      expect(body["deployments"].first["id"]).to eq(deployment.id.to_s)
      expect(body.dig("metrics", "available")).to be(true)
      expect(body["activity"].first["message"]).to eq("restart failed")
      expect(response.body).not_to include(secret)
      expect(body.dig("build_log_tail", "lines")).to include(a_string_including("[REDACTED]"))
    end

    it "reports unavailable metrics instead of zero usage" do
      get "/api/v1/services/#{web.id}/diagnose", headers: token_headers(token_for)

      expect(response.parsed_body.dig("metrics", "available")).to be(false)
      expect(response.parsed_body.dig("metrics", "cpu")).to be_nil
    end
  end

  describe "GET /api/v1/services/:id/logs" do
    it "returns live logs from the host when the command succeeds" do
      allow_any_instance_of(DokkuEngine).to receive(:logs).and_return(success: true, output: "line one\nline two")

      get "/api/v1/services/#{web.id}/logs", headers: token_headers(token_for)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["source"]).to eq("host")
      expect(body["lines"].map { |entry| entry["message"] }).to eq([ "line one", "line two" ])
    end

    it "falls back to stored logs with a reason when the host refuses" do
      allow_any_instance_of(DokkuEngine).to receive(:logs).and_return(success: false, output: "ssh down")

      get "/api/v1/services/#{web.id}/logs", headers: token_headers(token_for)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("source" => "stored", "error" => "ssh down")
    end
  end
end

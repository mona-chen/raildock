require "rails_helper"

RSpec.describe "Api::V1 write surface", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, organization: organization, server: server) }
  let(:production) { project.environments.find_by!(is_default: true) }
  let!(:web) { create(:service, project: project, environment: production, name: "web", dokku_app_name: "demo-web") }

  let(:manifest) do
    <<~TOML
      [[services]]
      name = "web"
      category = "app"
      subtype = "web"
    TOML
  end

  def token_for(**overrides)
    ApiToken.issue!(organization: organization, user: user, name: "agent", scopes: [ "read" ], **overrides)
  end

  def token_headers(token)
    { "Authorization" => "Bearer #{token.plaintext}", "X-Organization-ID" => organization.id.to_s }
  end

  def create_plan(token, content: manifest, project: self.project)
    post "/api/v1/plans",
      params: { plan: { project_id: project.id, content: content } },
      headers: token_headers(token),
      as: :json

    response.parsed_body.fetch("plan")
  end

  describe "POST /api/v1/plans" do
    it "returns a signed plan with the diff and no removals" do
      plan = create_plan(token_for)

      expect(response).to have_http_status(:created)
      expect(plan["id"]).to be_present
      expect(plan["project_id"]).to eq(project.id.to_s)
      expect(plan["changes"]).not_to be_empty
      expect(plan["requires_removal_confirmation"]).to be(false)
      expect(plan["expires_at"]).to be_present
    end

    it "rejects an invalid manifest without persisting anything" do
      post "/api/v1/plans",
        params: { plan: { project_id: project.id, content: "this is not toml [" } },
        headers: token_headers(token_for),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("invalid_manifest")
    end
  end

  describe "POST /api/v1/plans/apply" do
    it "requires config:write" do
      plan = create_plan(token_for)

      post "/api/v1/plans/apply",
        params: { plan: plan["id"] },
        headers: token_headers(token_for),
        as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("scope_denied")
    end

    it "enqueues the apply and returns a pollable operation" do
      token = token_for(scopes: [ "read", "config:write" ])
      plan = create_plan(token)

      expect do
        post "/api/v1/plans/apply",
          params: { plan: plan["id"] },
          headers: token_headers(token),
          as: :json
      end.to have_enqueued_job(ManifestApplyJob)

      expect(response).to have_http_status(:accepted)
      operation = response.parsed_body.fetch("operation")
      expect(operation["kind"]).to eq("manifest_apply")
      expect(operation["project_id"]).to eq(project.id.to_s)
      expect(Operation.find(operation["id"]).api_token).to eq(token)
    end

    it "refuses to apply a plan after the stored manifest moved" do
      token = token_for(scopes: [ "read", "config:write" ])
      plan = create_plan(token)
      project.update!(manifest_content: manifest.sub("web", "other"), manifest_format: "raildock.toml")

      post "/api/v1/plans/apply",
        params: { plan: plan["id"] },
        headers: token_headers(token),
        as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("plan_drifted")
    end

    it "rejects an expired plan" do
      token = token_for(scopes: [ "read", "config:write" ])
      plan = create_plan(token)

      travel 16.minutes do
        post "/api/v1/plans/apply",
          params: { plan: plan["id"] },
          headers: token_headers(token),
          as: :json
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("plan_expired")
    end

    it "attaches a replay to the operation already started" do
      token = token_for(scopes: [ "read", "config:write" ])
      plan = create_plan(token)

      post "/api/v1/plans/apply", params: { plan: plan["id"] }, headers: token_headers(token), as: :json
      first = response.parsed_body.fetch("operation")

      expect do
        post "/api/v1/plans/apply", params: { plan: plan["id"] }, headers: token_headers(token), as: :json
      end.not_to have_enqueued_job(ManifestApplyJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("operation", "id")).to eq(first["id"])
    end

    context "when the plan removes a service" do
      let!(:old_worker) do
        create(:service, project: project, environment: production, name: "old-worker", managed_by: :manifest)
      end

      it "requires the removal token and destructive scope" do
        token = token_for(scopes: [ "read", "config:write", "destructive" ])
        plan = create_plan(token)

        expect(plan["requires_removal_confirmation"]).to be(true)
        expect(plan["removals"].map { |entry| entry["service_name"] }).to eq([ "old-worker" ])
        expect(plan["removal_token"]).to be_present

        post "/api/v1/plans/apply",
          params: { plan: plan["id"] },
          headers: token_headers(token),
          as: :json

        expect(response).to have_http_status(:precondition_required)
        expect(response.parsed_body["code"]).to eq("removals_required")

        expect do
          post "/api/v1/plans/apply",
            params: {
              plan: plan["id"],
              confirm_removals: true,
              removal_token: plan["removal_token"]
            },
            headers: token_headers(token),
            as: :json
        end.to have_enqueued_job(ManifestApplyJob)

        expect(response).to have_http_status(:accepted)
      end

      it "refuses removals without the destructive scope" do
        token = token_for(scopes: [ "read", "config:write" ])
        plan = create_plan(token)

        post "/api/v1/plans/apply",
          params: { plan: plan["id"], confirm_removals: true, removal_token: plan["removal_token"] },
          headers: token_headers(token),
          as: :json

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["code"]).to eq("scope_denied")
      end
    end
  end

  describe "POST /api/v1/services/:id/deploy" do
    let(:token) { token_for(scopes: [ "read", "deploy" ]) }

    it "requires an Idempotency-Key" do
      post "/api/v1/services/#{web.id}/deploy", headers: token_headers(token), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("idempotency_key_required")
      expect(web.deployments.count).to eq(0)
    end

    it "starts exactly one deployment for repeated calls with the same key" do
      headers = token_headers(token).merge("Idempotency-Key" => "deploy-web-1")

      expect do
        post "/api/v1/services/#{web.id}/deploy", headers: headers, as: :json
        expect(response).to have_http_status(:accepted)
        @first_operation = response.parsed_body.fetch("operation")

        post "/api/v1/services/#{web.id}/deploy", headers: headers, as: :json
      end.to have_enqueued_job(DeploymentJob).exactly(:once)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("operation", "id")).to eq(@first_operation["id"])
      expect(web.deployments.count).to eq(1)
      expect(ActivityEvent.where(project: project).order(:id).last.api_token_id).to eq(token.id)
    end

    it "rejects reusing a key for a different service" do
      other = create(:service, project: project, environment: production, name: "other")
      headers = token_headers(token).merge("Idempotency-Key" => "shared-key")

      post "/api/v1/services/#{web.id}/deploy", headers: headers, as: :json
      expect(response).to have_http_status(:accepted)

      post "/api/v1/services/#{other.id}/deploy", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("idempotency_key_reused")
    end

    it "requires deploy scope" do
      post "/api/v1/services/#{web.id}/deploy",
        headers: token_headers(token_for).merge("Idempotency-Key" => "deploy-2"),
        as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("scope_denied")
    end

    it "refuses to deploy a database service" do
      database = create(:service, project: project, environment: production, name: "db", service_type: :database, subtype: "postgres")

      post "/api/v1/services/#{database.id}/deploy",
        headers: token_headers(token).merge("Idempotency-Key" => "deploy-db"),
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["code"]).to eq("not_deployable")
    end
  end

  describe "POST /api/v1/services/:id/restart" do
    it "starts a restart deployment and returns its operation" do
      token = token_for(scopes: [ "read", "deploy" ])
      headers = token_headers(token).merge("Idempotency-Key" => "restart-web-1")

      expect do
        post "/api/v1/services/#{web.id}/restart", headers: headers, as: :json
      end.to have_enqueued_job(RestartJob)

      expect(response).to have_http_status(:accepted)
      operation = response.parsed_body.fetch("operation")
      expect(operation["kind"]).to eq("restart")
      expect(operation["status"]).to eq("running")
      expect(web.deployments.last.kind).to eq("restart")
    end
  end

  describe "POST /api/v1/services/:id/rollback" do
    let(:token) { token_for(scopes: [ "read", "deploy" ]) }

    it "deploys the target commit as a new operation" do
      target = create(:deployment, service: web, status: :succeeded, commit_sha: "abc1234", branch: "main")
      headers = token_headers(token).merge("Idempotency-Key" => "rollback-web-1")

      expect do
        post "/api/v1/services/#{web.id}/rollback",
          params: { deployment_id: target.id },
          headers: headers,
          as: :json
      end.to have_enqueued_job(DeploymentJob)

      expect(response).to have_http_status(:accepted)
      operation = response.parsed_body.fetch("operation")
      expect(operation["kind"]).to eq("rollback")

      rollback = web.deployments.order(:id).last
      expect(rollback.commit_sha).to eq("abc1234")
      expect(rollback.triggered_by).to eq("rollback")
    end

    it "rejects a deployment that belongs to another service" do
      other = create(:service, project: project, environment: production, name: "other")
      target = create(:deployment, service: other)
      headers = token_headers(token).merge("Idempotency-Key" => "rollback-web-2")

      post "/api/v1/services/#{web.id}/rollback",
        params: { deployment_id: target.id },
        headers: headers,
        as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/operations/:id" do
    it "derives status from the deployment instead of copying it" do
      deployment = create(:deployment, service: web, status: :succeeded)
      operation = Operation.create!(
        organization: organization,
        project: project,
        service: web,
        kind: "deploy",
        subject: deployment,
        api_token: token_for
      )

      get "/api/v1/operations/#{operation.id}", headers: token_headers(token_for)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body.fetch("operation")
      expect(body["status"]).to eq("succeeded")
      expect(body.dig("subject", "type")).to eq("Deployment")
      expect(body.dig("result", "deployment_id")).to eq(deployment.id.to_s)
    end

    it "hides another organization's operation" do
      other = create(:organization)
      operation = Operation.create!(
        organization: other,
        kind: "deploy",
        status: "pending"
      )

      get "/api/v1/operations/#{operation.id}", headers: token_headers(token_for)

      expect(response).to have_http_status(:not_found)
    end
  end
end

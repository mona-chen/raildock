require "rails_helper"

RSpec.describe "MCP Streamable HTTP transport", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:server) { create(:server, organization: organization) }
  let(:project) { create(:project, organization: organization, server: server) }
  let(:production) { project.environments.find_by!(is_default: true) }
  let!(:web) { create(:service, project: project, environment: production, name: "web", dokku_app_name: "demo-web") }
  let!(:variable) { create(:environment_variable, service: web, key: "DATABASE_URL", value: "super-secret-value") }

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

  def headers_for(token)
    {
      "Authorization" => "Bearer #{token.plaintext}",
      "X-Organization-ID" => organization.id.to_s,
      "Content-Type" => "application/json"
    }
  end

  def rpc(token, payload)
    post "/mcp", params: payload.to_json, headers: headers_for(token)
    response.parsed_body
  end

  def call_tool(token, name, arguments = {})
    rpc(token, { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } })
  end

  def content(body)
    JSON.parse(body.dig("result", "content", 0, "text"))
  end

  describe "initialize" do
    it "negotiates the protocol and advertises tools and resources" do
      body = rpc(token_for, {
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } }
      })

      expect(body["result"]["protocolVersion"]).to eq("2025-06-18")
      expect(body["result"]["capabilities"]).to include("tools", "resources")
      expect(body["result"]["serverInfo"]["name"]).to eq("raildock")
    end

    it "accepts notifications without a response body" do
      post "/mcp",
        params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
        headers: headers_for(token_for)

      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_blank
    end
  end

  describe "tools" do
    it "lists the ten tools with input schemas" do
      body = rpc(token_for, { jsonrpc: "2.0", id: 2, method: "tools/list" })

      tools = body.dig("result", "tools")
      expect(tools.map { |tool| tool["name"] }).to contain_exactly(
        "get_context", "list_services", "get_service", "diagnose_service", "query_logs",
        "plan_change", "apply_plan", "get_operation", "deploy", "rollback"
      )
      expect(tools).to all(include("description", "inputSchema"))
    end

    it "returns context through the same presenter and never leaks values" do
      body = call_tool(token_for, "get_context")
      payload = content(body)

      expect(body.dig("result", "isError")).to be(false)
      expect(payload.dig("organization", "id")).to eq(organization.id.to_s)
      expect(payload["services"]).to be_nil
      expect(payload.dig("projects", 0, "services").map { |service| service["name"] }).to eq([ "web" ])
      expect(response.body).not_to include("super-secret-value")
    end

    it "lists services inside the binding" do
      body = call_tool(token_for, "list_services")
      payload = content(body)

      expect(body.dig("result", "isError")).to be(false)
      expect(payload["services"].map { |service| service["name"] }).to eq([ "web" ])
      expect(response.body).not_to include("super-secret-value")
    end

    it "round-trips plan_change into apply_plan" do
      token = token_for(scopes: [ "read", "config:write" ])

      plan_body = call_tool(token, "plan_change", { project_id: project.id, content: manifest })
      plan = content(plan_body)
      expect(plan_body.dig("result", "isError")).to be(false)
      expect(plan["changes"]).not_to be_empty

      expect do
        @apply_body = call_tool(token, "apply_plan", { plan: plan["id"] })
      end.to have_enqueued_job(ManifestApplyJob)

      operation = content(@apply_body)
      expect(@apply_body.dig("result", "isError")).to be(false)
      expect(operation["kind"]).to eq("manifest_apply")
      expect(operation["service_id"]).to be_nil
    end

    it "starts a rollback through the shared write path" do
      token = token_for(scopes: [ "read", "deploy" ])
      target = create(:deployment, service: web, commit_sha: "abc1234", branch: "main")

      expect do
        @rollback_body = call_tool(token, "rollback", {
          service_id: web.id,
          deployment_id: target.id,
          idempotency_key: "mcp-rollback-1"
        })
      end.to have_enqueued_job(DeploymentJob)

      operation = content(@rollback_body)
      expect(@rollback_body.dig("result", "isError")).to be(false)
      expect(operation["kind"]).to eq("rollback")
      expect(web.deployments.order(:id).last.commit_sha).to eq("abc1234")
    end

    it "returns the same scope_denied payload as v1" do
      body = call_tool(token_for, "deploy", { service_id: web.id, idempotency_key: "mcp-1" })

      expect(body.dig("result", "isError")).to be(true)
      denied = content(body)
      expect(denied["code"]).to eq("scope_denied")
      expect(denied["required_scope"]).to eq("deploy")
      expect(denied["granted_scopes"]).to eq([ "read" ])
    end

    it "hides a service outside the token's environment binding" do
      staging = project.environments.create!(name: "staging", slug: "staging")
      token = token_for(environment_id: staging.id)

      body = call_tool(token, "get_service", { service_id: web.id })

      expect(body.dig("result", "isError")).to be(true)
      expect(content(body)["code"]).to eq("not_found")
    end

    it "rejects an unknown tool as invalid params" do
      body = call_tool(token_for, "nope")

      expect(body.dig("error", "code")).to eq(-32602)
    end

    it "rejects a missing required argument" do
      body = call_tool(token_for, "get_service", {})

      expect(body.dig("error", "code")).to eq(-32602)
    end
  end

  describe "resources" do
    it "lists and reads the organization context" do
      token = token_for
      uri = "raildock://context/#{organization.id}"

      list = rpc(token, { jsonrpc: "2.0", id: 3, method: "resources/list" })
      expect(list.dig("result", "resources").map { |resource| resource["uri"] }).to include(uri)

      read = rpc(token, { jsonrpc: "2.0", id: 4, method: "resources/read", params: { uri: uri } })
      payload = JSON.parse(read.dig("result", "contents", 0, "text"))
      expect(payload.dig("organization", "id")).to eq(organization.id.to_s)
      expect(read.dig("result", "contents", 0, "mimeType")).to eq("application/json")
    end

    it "serves the OpenAPI document as a resource" do
      read = rpc(token_for, { jsonrpc: "2.0", id: 5, method: "resources/read", params: { uri: "raildock://openapi" } })

      document = JSON.parse(read.dig("result", "contents", 0, "text"))
      expect(document["openapi"]).to start_with("3.1")
    end

    it "rejects an unknown uri" do
      body = rpc(token_for, { jsonrpc: "2.0", id: 6, method: "resources/read", params: { uri: "raildock://nope" } })

      expect(body.dig("error", "code")).to eq(-32602)
    end
  end

  describe "protocol" do
    it "rejects unknown methods with method-not-found" do
      body = rpc(token_for, { jsonrpc: "2.0", id: 7, method: "prompts/list" })

      expect(body.dig("error", "code")).to eq(-32601)
    end

    it "answers ping" do
      body = rpc(token_for, { jsonrpc: "2.0", id: 8, method: "ping" })

      expect(body["result"]).to eq({})
    end

    it "refuses GET and DELETE streams" do
      get "/mcp", headers: headers_for(token_for)
      expect(response).to have_http_status(:method_not_allowed)

      delete "/mcp", headers: headers_for(token_for)
      expect(response).to have_http_status(:method_not_allowed)
    end

    it "requires a credential" do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to eq(%(Bearer realm="raildock"))
    end
  end
end

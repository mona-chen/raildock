# Streamable HTTP transport for MCP.
#
# A thin JSON-RPC layer over Mcp::Toolset: initialize, tools, resources and
# ping. It intentionally keeps no session state (no Mcp-Session-Id) and does
# not offer a server-initiated SSE stream, so every request is authenticated and
# answered on its own.
class McpController < Api::V1::BaseController
  MCP_PROTOCOL_VERSION = "2025-06-18"
  SUPPORTED_PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze

  def handle
    return head :method_not_allowed unless request.post?

    payload = parse_body
    return if performed?

    dispatch_jsonrpc(payload)
  end

  def method_not_allowed
    head :method_not_allowed
  end

  private

  def authenticate_user!
    super
    response.headers["WWW-Authenticate"] = %(Bearer realm="raildock") if performed? && response.status == 401
  end

  def toolset
    @toolset ||= Mcp::Toolset.new(
      organization: current_organization,
      user: current_user,
      token: current_api_token,
      scope: agent_scope
    )
  end

  def parse_body
    raw = request.raw_post.to_s
    return jsonrpc_http_error(nil, -32700, "Parse error") if raw.blank?

    parsed = JSON.parse(raw)
    return jsonrpc_http_error(nil, -32600, "Batch requests are not supported") if parsed.is_a?(Array)
    return jsonrpc_http_error(nil, -32600, "Invalid Request") unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError
    jsonrpc_http_error(nil, -32700, "Parse error")
  end

  def dispatch_jsonrpc(payload)
    id = payload["id"]
    method = payload["method"]

    unless payload["jsonrpc"] == "2.0" && method.is_a?(String) && method.present?
      return jsonrpc_http_error(id, -32600, "Invalid Request")
    end

    # A message without an id is a notification; MCP expects no response body.
    return head :accepted unless payload.key?("id")

    case method
    when "initialize" then jsonrpc_result(id, initialize_result(payload["params"]))
    when "ping" then jsonrpc_result(id, {})
    when "tools/list" then jsonrpc_result(id, { tools: toolset.tools })
    when "tools/call" then call_tool(id, payload["params"])
    when "resources/list" then jsonrpc_result(id, { resources: resources })
    when "resources/templates/list" then jsonrpc_result(id, { resourceTemplates: resource_templates })
    when "resources/read" then read_resource(id, payload["params"])
    else jsonrpc_error(id, -32601, "Method not found: #{method}")
    end
  end

  def call_tool(id, params)
    return jsonrpc_error(id, -32602, "Invalid params") unless params.is_a?(Hash)

    name = params["name"].to_s
    return jsonrpc_error(id, -32602, "Tool name is required") if name.blank?

    arguments = params["arguments"] || {}
    return jsonrpc_error(id, -32602, "arguments must be an object") unless arguments.is_a?(Hash)

    jsonrpc_result(id, tool_result(toolset.call(name, arguments)))
  rescue Mcp::Toolset::UnknownTool, Mcp::Toolset::InvalidArguments => error
    jsonrpc_error(id, -32602, error.message)
  rescue Mcp::Toolset::ScopeDenied => error
    tool_error(id, scope_denied_payload(error))
  rescue Mcp::Toolset::ToolError => error
    tool_error(id, { error: error.message, code: error.code }.merge(error.details))
  rescue AgentPlan::Expired => error
    tool_error(id, error: error.message, code: "plan_expired")
  rescue AgentPlan::Drifted => error
    tool_error(id, error: error.message, code: "plan_drifted")
  rescue AgentPlan::Invalid => error
    tool_error(id, error: error.message, code: "invalid_manifest")
  rescue AgentPlanApply::RemovalRequired => error
    tool_error(
      id,
      error: error.message,
      code: "removals_required",
      removals: error.removals,
      removal_token: error.removal_token
    )
  rescue AgentWrites::IdempotencyConflict
    tool_error(id, error: "Idempotency key was already used for a different request", code: "idempotency_key_reused")
  rescue ActiveRecord::RecordNotFound
    tool_error(id, error: "Not found", code: "not_found")
  rescue ApplicationController::AuthorizationDenied
    tool_error(id, error: "Forbidden", code: "forbidden")
  end

  def initialize_result(params)
    requested = params.is_a?(Hash) ? params["protocolVersion"].to_s : ""
    version = SUPPORTED_PROTOCOL_VERSIONS.include?(requested) ? requested : MCP_PROTOCOL_VERSION

    {
      protocolVersion: version,
      capabilities: {
        tools: { listChanged: false },
        resources: { subscribe: false, listChanged: false }
      },
      serverInfo: {
        name: "raildock",
        version: ENV.fetch("BUILD_VERSION", "0.1.0")
      }
    }
  end

  def resources
    [
      {
        uri: context_uri,
        name: "RailDock context",
        description: "Organization, projects, services, links and capabilities for this credential.",
        mimeType: "application/json"
      },
      {
        uri: openapi_uri,
        name: "RailDock OpenAPI",
        description: "OpenAPI 3.1 description of the v1 HTTP surface.",
        mimeType: "application/json"
      }
    ]
  end

  def resource_templates
    [
      {
        uriTemplate: "raildock://context/{organization}",
        name: "RailDock context",
        description: "Context for one organization.",
        mimeType: "application/json"
      }
    ]
  end

  def read_resource(id, params)
    uri = params.is_a?(Hash) ? params["uri"].to_s : ""

    text = case uri
    when context_uri then JSON.generate(toolset.call("get_context", {}))
    when openapi_uri then JSON.generate(AgentApiDocument.new.as_json)
    end

    return jsonrpc_error(id, -32602, "Unknown resource: #{uri}") if text.nil?

    jsonrpc_result(id, { contents: [ { uri: uri, mimeType: "application/json", text: text } ] })
  end

  def context_uri
    "raildock://context/#{current_organization.id}"
  end

  def openapi_uri
    "raildock://openapi"
  end

  def scope_denied_payload(error)
    {
      error: error.message,
      code: "scope_denied",
      required_scope: error.required_scope,
      granted_scopes: current_api_token&.scopes || ApiToken::SCOPES
    }
  end

  def tool_error(id, payload)
    jsonrpc_result(id, tool_result(payload, is_error: true))
  end

  # structuredContent must be an object, so every tool payload is a hash.
  def tool_result(payload, is_error: false)
    normalized = JSON.parse(JSON.generate(payload))
    {
      content: [ { type: "text", text: JSON.generate(normalized) } ],
      structuredContent: normalized,
      isError: is_error
    }
  end

  def jsonrpc_result(id, result)
    render json: { jsonrpc: "2.0", id: id, result: result }
  end

  def jsonrpc_error(id, code, message, data: nil)
    error = { code: code, message: message }
    error[:data] = data if data
    render json: { jsonrpc: "2.0", id: id, error: error }
  end

  def jsonrpc_http_error(id, code, message, data: nil)
    error = { code: code, message: message }
    error[:data] = data if data
    render json: { jsonrpc: "2.0", id: id, error: error }, status: :bad_request
  end
end

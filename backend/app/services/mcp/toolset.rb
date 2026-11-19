# The tool surface behind `/mcp`.
#
# Every tool goes through the same scope, binding and role checks as `/api/v1`
# and composes the same services and presenters. MCP is a transport, not a
# second implementation: a tool must never be able to do something the REST
# surface cannot.
class Mcp::Toolset
  include Authorizable

  class UnknownTool < StandardError; end
  class InvalidArguments < StandardError; end

  class ScopeDenied < StandardError
    attr_reader :required_scope

    def initialize(required_scope)
      @required_scope = required_scope.to_s
      super("This token lacks the #{@required_scope} scope")
    end
  end

  class ToolError < StandardError
    attr_reader :code, :details

    def initialize(message, code:, details: {})
      @code = code
      @details = details
      super(message)
    end
  end

  TOOLS = [
    {
      name: "get_context",
      description: "One call to orient: organization, actor, scopes, servers, projects and services. Never returns secret values.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false }
    },
    {
      name: "list_services",
      description: "List services the credential can see, optionally filtered by project or environment.",
      inputSchema: {
        type: "object",
        properties: {
          project_id: { type: "string" },
          environment_id: { type: "string" }
        },
        additionalProperties: false
      }
    },
    {
      name: "get_service",
      description: "Service configuration, domains, mounts, links and variable names. Values are never returned.",
      inputSchema: {
        type: "object",
        properties: { service_id: { type: "string" } },
        required: [ "service_id" ],
        additionalProperties: false
      }
    },
    {
      name: "diagnose_service",
      description: "Stored deployments, metrics and activity for a service. Reads no host state and performs no SSH.",
      inputSchema: {
        type: "object",
        properties: { service_id: { type: "string" } },
        required: [ "service_id" ],
        additionalProperties: false
      }
    },
    {
      name: "query_logs",
      description: "Recent logs for a service. Falls back to stored deployment logs with an explicit reason when the host is unreachable.",
      inputSchema: {
        type: "object",
        properties: {
          service_id: { type: "string" },
          lines: { type: "integer", minimum: 1, maximum: 500, default: 100 }
        },
        required: [ "service_id" ],
        additionalProperties: false
      }
    },
    {
      name: "plan_change",
      description: "Diff a manifest against the project and return a signed, 15-minute plan. Applies nothing.",
      inputSchema: {
        type: "object",
        properties: {
          project_id: { type: "string" },
          content: { type: "string" },
          format: { type: "string" }
        },
        required: [ "project_id" ],
        additionalProperties: false
      }
    },
    {
      name: "apply_plan",
      description: "Apply a reviewed plan token. Removals need confirm_removals and the removal_token from the plan response.",
      inputSchema: {
        type: "object",
        properties: {
          plan: { type: "string" },
          confirm_removals: { type: "boolean" },
          removal_token: { type: "string" },
          force_destroy_data: { type: "boolean" }
        },
        required: [ "plan" ],
        additionalProperties: false
      }
    },
    {
      name: "get_operation",
      description: "Poll asynchronous work started by this API. Status is derived from the deployment or manifest operation.",
      inputSchema: {
        type: "object",
        properties: { operation_id: { type: "string" } },
        required: [ "operation_id" ],
        additionalProperties: false
      }
    },
    {
      name: "deploy",
      description: "Start a deployment. Idempotency-Key equivalent is required and a repeat returns the same operation.",
      inputSchema: {
        type: "object",
        properties: {
          service_id: { type: "string" },
          idempotency_key: { type: "string" },
          branch: { type: "string" },
          commit_sha: { type: "string" },
          commit_message: { type: "string" }
        },
        required: [ "service_id", "idempotency_key" ],
        additionalProperties: false
      }
    },
    {
      name: "rollback",
      description: "Deploy the commit from an earlier deployment. Idempotency-Key equivalent is required.",
      inputSchema: {
        type: "object",
        properties: {
          service_id: { type: "string" },
          deployment_id: { type: "string" },
          idempotency_key: { type: "string" }
        },
        required: [ "service_id", "deployment_id", "idempotency_key" ],
        additionalProperties: false
      }
    }
  ].freeze

  def initialize(organization:, user:, token:, scope:)
    @organization = organization
    @user = user
    @token = token
    @scope = scope
  end

  def tools
    TOOLS
  end

  def call(name, arguments)
    case name
    when "get_context" then get_context
    when "list_services" then list_services(arguments)
    when "get_service" then get_service(arguments)
    when "diagnose_service" then diagnose_service(arguments)
    when "query_logs" then query_logs(arguments)
    when "plan_change" then plan_change(arguments)
    when "apply_plan" then apply_plan(arguments)
    when "get_operation" then get_operation(arguments)
    when "deploy" then deploy(arguments)
    when "rollback" then rollback(arguments)
    else raise UnknownTool, "Unknown tool: #{name}"
    end
  end

  private

  attr_reader :organization, :user, :token, :scope

  def current_user = user
  def current_organization = organization

  def require_scope!(scope_name)
    return if token.nil? || token.allows?(scope_name)

    raise ScopeDenied, scope_name
  end

  def get_context
    projects = scope.projects.includes(:environments, services: :domains).order(:name)

    Api::V1::ContextPresenter.new(
      organization: organization,
      projects: projects,
      servers: scope.servers.order(:name),
      role: current_role,
      token: token,
      user: user
    ).as_json
  end

  def list_services(arguments)
    require_scope!(:read)

    services = scope.services.includes(:domains, :process_types, :environment_variables)
    services = services.where(project_id: arguments["project_id"]) if arguments["project_id"].present?
    services = services.where(environment_id: arguments["environment_id"]) if arguments["environment_id"].present?

    {
      services: services.order(:name).map { |service| Api::V1::ServicePresenter.new(service).as_json }
    }
  end

  def get_service(arguments)
    require_scope!(:read)
    Api::V1::ServicePresenter.new(load_service(arguments)).as_json
  end

  def diagnose_service(arguments)
    require_scope!(:read)
    Api::V1::DiagnosisPresenter.new(load_service(arguments)).as_json
  end

  def query_logs(arguments)
    require_scope!(:read)

    limit = arguments["lines"].present? ? arguments["lines"].to_i.clamp(1, 500) : 100
    AgentLogs.new(service: load_service(arguments), limit: limit).payload
  end

  def plan_change(arguments)
    require_scope!(:read)

    project = load_project(arguments)
    authorize_project!(project, action: :read)

    content = arguments["content"].presence || project.manifest_content
    if content.blank?
      raise ToolError.new("No manifest configured. Supply content.", code: "manifest_missing")
    end

    AgentPlan.build(
      project: project,
      content: content,
      format: arguments["format"],
      actor: token
    ).as_json
  end

  def apply_plan(arguments)
    require_scope!("config:write")

    payload = AgentPlan.decode!(required_string(arguments, "plan"))
    project = scope.projects.find_by(id: payload[:project_id])
    raise ActiveRecord::RecordNotFound unless project

    authorize_project!(project, action: :update)
    require_scope!(:destructive) if Array(payload[:removals]).any?

    result = AgentPlanApply.new(organization: organization, actor: token).call(
      payload: payload,
      project: project,
      confirm_removals: arguments["confirm_removals"],
      removal_token: arguments["removal_token"],
      force_destroy_data: arguments["force_destroy_data"]
    )

    Api::V1::OperationPresenter.new(result.operation).as_json.merge(replayed: !result.created)
  end

  def get_operation(arguments)
    require_scope!(:read)

    operation = Operation.where(organization: organization).find(required_string(arguments, "operation_id"))
    raise ActiveRecord::RecordNotFound unless visible_operation?(operation)

    Api::V1::OperationPresenter.new(operation).as_json
  end

  def deploy(arguments)
    require_scope!(:deploy)

    service = load_service(arguments)
    authorize_service!(service, action: :deploy)
    if service.service_type == "database"
      raise ToolError.new(
        "Database services cannot be deployed. They are managed directly by Dokku.",
        code: "not_deployable"
      )
    end

    result = writes.deploy(
      service: service,
      key: required_string(arguments, "idempotency_key"),
      branch: arguments["branch"],
      commit_sha: arguments["commit_sha"],
      commit_message: arguments["commit_message"]
    )

    Api::V1::OperationPresenter.new(result.operation).as_json.merge(replayed: !result.created)
  end

  def rollback(arguments)
    require_scope!(:deploy)

    service = load_service(arguments)
    authorize_service!(service, action: :deploy)

    target = service.deployments.find(required_string(arguments, "deployment_id"))
    if service.git_repo.present? && target.commit_sha.blank?
      raise ToolError.new(
        "This deployment has no commit SHA and cannot be rolled back precisely",
        code: "rollback_not_precise"
      )
    end

    result = writes.rollback(
      service: service,
      key: required_string(arguments, "idempotency_key"),
      target: target
    )

    Api::V1::OperationPresenter.new(result.operation).as_json.merge(replayed: !result.created)
  end

  def load_service(arguments)
    scope.services.find(required_string(arguments, "service_id"))
  end

  def load_project(arguments)
    scope.projects.find(required_string(arguments, "project_id"))
  end

  def required_string(arguments, key)
    value = arguments[key]
    value = value.to_s if value.is_a?(String) || value.is_a?(Numeric)
    raise InvalidArguments, "#{key} is required" unless value.is_a?(String) && value.present?

    value
  end

  def visible_operation?(operation)
    return false if operation.project_id && !scope.projects.exists?(id: operation.project_id)
    return false if operation.service_id && !scope.services.exists?(id: operation.service_id)

    true
  end

  def writes
    @writes ||= AgentWrites.new(organization: organization, actor: token)
  end
end

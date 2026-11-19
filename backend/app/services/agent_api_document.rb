# OpenAPI 3.1 description of the agent-facing HTTP surface.
#
# Kept as one object instead of a generated schema library: the presenters are
# hand-written hashes too, so the document is the same kind of artifact. A spec
# asserts every `/api/v1` route is described, which is the part that goes stale
# when an endpoint is added.
class AgentApiDocument
  def as_json
    {
      openapi: "3.1.0",
      info: {
        title: "RailDock Agent API",
        version: ENV.fetch("BUILD_VERSION", "0.1.0"),
        description: <<~MARKDOWN
          Token-scoped API for agents. Authenticate with `Authorization: Bearer rd_...`.
          Environment variable values, config values, SSH keys and webhook tokens are
          never serialized. Destructive work follows the same typed-confirmation and
          snapshot protocol as the dashboard. See `docs/agents-api.md`.
        MARKDOWN
      },
      servers: [ { url: "/", description: "This RailDock installation" } ],
      security: [ { bearerAuth: [] } ],
      tags: [
        { name: "context", description: "Orientation and topology" },
        { name: "services", description: "Reads, logs, diagnosis and service operations" },
        { name: "plans", description: "Review a manifest change before applying it" },
        { name: "operations", description: "Poll asynchronous work" },
        { name: "meta", description: "API description" }
      ],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: "http",
            scheme: "bearer",
            description: "A RailDock API token (`rd_...`) or a user JWT. Tokens carry their organization."
          }
        },
        parameters: parameters,
        responses: responses,
        schemas: schemas
      },
      paths: paths
    }
  end

  private

  def parameters
    {
      organization: {
        name: "X-Organization-ID",
        in: "header",
        required: false,
        schema: { type: "string" },
        description: "Selects the organization for user JWTs. Tokens carry their organization and refuse a different id."
      },
      idempotency: {
        name: "Idempotency-Key",
        in: "header",
        required: true,
        schema: { type: "string", maxLength: 140 },
        description: "Retry-safe key. A repeat with the same key returns the original operation."
      },
      id: {
        name: "id",
        in: "path",
        required: true,
        schema: { type: "string" },
        description: "Resource id."
      }
    }
  end

  def responses
    {
      "BadRequest": json_response("Malformed request"),
      "Unauthorized": json_response("Missing, malformed, revoked or expired credential"),
      "Forbidden": json_response("Scope, role or organization binding denied"),
      "NotFound": json_response("Not found in the credential's project/environment binding"),
      "Conflict": json_response("Work was blocked by the current state"),
      "Unprocessable": json_response("Validation failed"),
      "PreconditionRequired": json_response("A typed confirmation, removal token or snapshot is required"),
      "RateLimited": header_json_response("Per-token rate limit exceeded", "Retry-After")
    }
  end

  def json_response(description)
    {
      description: description,
      content: { "application/json" => { schema: { "$ref" => "#/components/schemas/Error" } } }
    }
  end

  def header_json_response(description, header)
    json_response(description).merge(
      headers: { header => { schema: { type: "string" }, description: "Seconds to wait before retrying." } }
    )
  end

  def paths
    {
      "/api/v1/context" => {
        get: {
          tags: [ "context" ],
          summary: "Organization, actor, capabilities, servers, projects and services",
          parameters: [ ref(:organization), ref(:id) ],
          responses: ok("Context", "#/components/schemas/Context").merge(failure_responses)
        }
      },
      "/api/v1/projects/{id}" => {
        get: {
          tags: [ "context" ],
          summary: "Project detail with environments, services, links and manifest state",
          parameters: [ ref(:organization), ref(:id) ],
          responses: ok("Project", "#/components/schemas/Project").merge(failure_responses)
        }
      },
      "/api/v1/services/{id}" => {
        get: {
          tags: [ "services" ],
          summary: "Service configuration, domains, mounts, links and variable names",
          parameters: [ ref(:organization), ref(:id) ],
          responses: ok("Service", "#/components/schemas/Service").merge(failure_responses)
        }
      },
      "/api/v1/services/{id}/logs" => {
        get: {
          tags: [ "services" ],
          summary: "Recent logs, falling back to stored deployment logs with a reason",
          parameters: [
            ref(:organization),
            ref(:id),
            {
              name: "lines",
              in: "query",
              required: false,
              schema: { type: "integer", minimum: 1, maximum: 500, default: 100 }
            }
          ],
          responses: ok("Logs", "#/components/schemas/Logs").merge(failure_responses)
        }
      },
      "/api/v1/services/{id}/diagnose" => {
        get: {
          tags: [ "services" ],
          summary: "Stored deployments, metrics and activity; performs no SSH",
          parameters: [ ref(:organization), ref(:id) ],
          responses: ok("Diagnosis", "#/components/schemas/Diagnosis").merge(failure_responses)
        }
      },
      "/api/v1/services/{id}/deploy" => {
        post: {
          tags: [ "services" ],
          summary: "Start a deployment and return a pollable operation",
          parameters: [ ref(:organization), ref(:id), ref(:idempotency) ],
          requestBody: request_body("#/components/schemas/DeployRequest"),
          responses: accepted("Operation", "#/components/schemas/OperationEnvelope").merge(failure_responses)
        }
      },
      "/api/v1/services/{id}/restart" => {
        post: {
          tags: [ "services" ],
          summary: "Restart a service and return a pollable operation",
          parameters: [ ref(:organization), ref(:id), ref(:idempotency) ],
          responses: accepted("Operation", "#/components/schemas/OperationEnvelope").merge(failure_responses)
        }
      },
      "/api/v1/services/{id}/rollback" => {
        post: {
          tags: [ "services" ],
          summary: "Deploy an earlier deployment's commit",
          parameters: [ ref(:organization), ref(:id), ref(:idempotency) ],
          requestBody: request_body("#/components/schemas/RollbackRequest"),
          responses: accepted("Operation", "#/components/schemas/OperationEnvelope").merge(failure_responses)
        }
      },
      "/api/v1/plans" => {
        post: {
          tags: [ "plans" ],
          summary: "Diff a manifest and return a signed, expiring plan",
          parameters: [ ref(:organization) ],
          requestBody: request_body("#/components/schemas/PlanCreateRequest"),
          responses: {
            "201" => {
              description: "Plan",
              content: { "application/json" => { schema: { "$ref" => "#/components/schemas/PlanEnvelope" } } }
            }
          }.merge(failure_responses)
        }
      },
      "/api/v1/plans/apply" => {
        post: {
          tags: [ "plans" ],
          summary: "Apply a reviewed plan; removals require the removal token",
          parameters: [ ref(:organization) ],
          requestBody: request_body("#/components/schemas/PlanApplyRequest"),
          responses: accepted("Operation", "#/components/schemas/OperationEnvelope").merge(failure_responses)
        }
      },
      "/api/v1/operations/{id}" => {
        get: {
          tags: [ "operations" ],
          summary: "Poll asynchronous work",
          parameters: [ ref(:organization), ref(:id) ],
          responses: ok("Operation", "#/components/schemas/OperationEnvelope").merge(failure_responses)
        }
      },
      "/api/v1/openapi" => {
        get: {
          tags: [ "meta" ],
          summary: "This OpenAPI document",
          parameters: [ ref(:organization) ],
          responses: {
            "200" => {
              description: "OpenAPI 3.1 document",
              content: { "application/json" => { schema: { type: "object", additionalProperties: true } } }
            }
          }.merge(failure_responses)
        }
      }
    }
  end

  def ref(name)
    { "$ref" => "#/components/parameters/#{name}" }
  end

  def request_body(schema_ref)
    { required: true, content: { "application/json" => { schema: { "$ref" => schema_ref } } } }
  end

  def ok(description, schema_ref)
    {
      "200" => {
        description: description,
        content: { "application/json" => { schema: { "$ref" => schema_ref } } }
      }
    }
  end

  def accepted(description, schema_ref)
    {
      "200" => {
        description: "#{description} (replayed idempotent request)",
        content: { "application/json" => { schema: { "$ref" => schema_ref } } }
      },
      "202" => {
        description: description,
        content: { "application/json" => { schema: { "$ref" => schema_ref } } }
      }
    }
  end

  def failure_responses
    {
      "400" => ref_response("BadRequest"),
      "401" => ref_response("Unauthorized"),
      "403" => ref_response("Forbidden"),
      "404" => ref_response("NotFound"),
      "409" => ref_response("Conflict"),
      "422" => ref_response("Unprocessable"),
      "428" => ref_response("PreconditionRequired"),
      "429" => ref_response("RateLimited")
    }
  end

  def ref_response(name)
    { "$ref" => "#/components/responses/#{name}" }
  end

  def schemas
    {
      Error: {
        type: "object",
        properties: {
          error: { type: "string" },
          code: {
            type: "string",
            description: "Stable machine code, for example scope_denied, plan_drifted, removals_required, rate_limited."
          },
          required_scope: { type: "string" },
          granted_scopes: { type: "array", items: { type: "string" } },
          actionable: { type: "boolean" },
          removals: { type: "array", items: { type: "string" } },
          removal_token: { type: "string" },
          retry_after: { type: "integer" }
        },
        required: [ "error" ],
        additionalProperties: true
      },
      Organization: {
        type: "object",
        properties: {
          id: { type: "string" },
          name: { type: "string" },
          slug: { type: "string" }
        },
        additionalProperties: true
      },
      Actor: {
        type: "object",
        properties: {
          type: { type: "string", enum: [ "api_token", "user" ] },
          id: { type: "string" },
          role: { type: "string", nullable: true },
          scopes: { type: "array", items: { type: "string" }, nullable: true },
          project_id: { type: "string", nullable: true },
          environment_id: { type: "string", nullable: true },
          expires_at: { type: "string", format: "date-time", nullable: true }
        },
        additionalProperties: true
      },
      Context: {
        type: "object",
        properties: {
          organization: { "$ref" => "#/components/schemas/Organization" },
          actor: { "$ref" => "#/components/schemas/Actor" },
          capabilities: {
            type: "object",
            properties: {
              read: { type: "boolean" },
              deploy: { type: "boolean" },
              config_write: { type: "boolean" },
              destructive: { type: "boolean" }
            },
            additionalProperties: false
          },
          counts: { type: "object", additionalProperties: true },
          servers: { type: "array", items: { type: "object", additionalProperties: true } },
          projects: { type: "array", items: { "$ref" => "#/components/schemas/Project" } }
        },
        required: [ "organization", "actor", "capabilities", "projects" ],
        additionalProperties: true
      },
      Project: {
        type: "object",
        properties: {
          id: { type: "string" },
          name: { type: "string" },
          description: { type: "string", nullable: true },
          environment: { type: "string" },
          deletion: { type: "object", additionalProperties: true },
          manifest: { type: "object", additionalProperties: true },
          environments: { type: "array", items: { type: "object", additionalProperties: true } },
          services: { type: "array", items: { "$ref" => "#/components/schemas/ServiceSummary" } },
          links: { type: "array", items: { type: "object", additionalProperties: true } }
        },
        required: [ "id", "name", "manifest", "services" ],
        additionalProperties: true
      },
      ServiceSummary: {
        type: "object",
        properties: {
          id: { type: "string" },
          name: { type: "string" },
          service_type: { type: "string" },
          subtype: { type: "string" },
          status: { type: "string" },
          environment_id: { type: "string", nullable: true },
          exposed: { type: "boolean" },
          domains: { type: "array", items: { type: "string" } },
          last_deployed: { type: "string", format: "date-time", nullable: true }
        },
        additionalProperties: true
      },
      Service: {
        allOf: [
          { "$ref" => "#/components/schemas/ServiceSummary" },
          {
            type: "object",
            properties: {
              project_id: { type: "string" },
              created_at: { type: "string", format: "date-time", nullable: true },
              port: { type: "object", additionalProperties: true },
              internal_hostname: { type: "string", nullable: true },
              storage_mounts: { type: "array", items: { type: "object", additionalProperties: true } },
              process_types: { type: "array", items: { type: "object", additionalProperties: true } },
              links: { type: "object", additionalProperties: true },
              variables: {
                type: "array",
                description: "Names only. Values are never returned.",
                items: { type: "object", additionalProperties: true }
              },
              config_keys: { type: "array", items: { type: "string" } },
              build: { type: "object", additionalProperties: true },
              restart_policy: { type: "string" },
              maintenance_mode: { type: "boolean" },
              webhook_configured: { type: "boolean" }
            },
            additionalProperties: true
          }
        ]
      },
      Logs: {
        type: "object",
        properties: {
          service_id: { type: "string" },
          source: { type: "string", enum: [ "host", "stored" ] },
          truncated: { type: "boolean" },
          lines: {
            type: "array",
            items: {
              type: "object",
              properties: {
                timestamp: { type: "string", format: "date-time" },
                process_type: { type: "string", nullable: true },
                message: { type: "string" }
              },
              additionalProperties: true
            }
          },
          error: { type: "string", description: "Why live logs were unavailable." }
        },
        required: [ "service_id", "source", "lines" ],
        additionalProperties: true
      },
      Diagnosis: {
        type: "object",
        properties: {
          service: { "$ref" => "#/components/schemas/ServiceSummary" },
          generated_at: { type: "string", format: "date-time" },
          status: { type: "object", additionalProperties: true },
          deployments: { type: "array", items: { type: "object", additionalProperties: true } },
          build_log_tail: { type: "object", additionalProperties: true },
          metrics: { type: "object", additionalProperties: true },
          activity: { type: "array", items: { type: "object", additionalProperties: true } },
          limits: { type: "array", items: { type: "string" } }
        },
        required: [ "status", "deployments" ],
        additionalProperties: true
      },
      Plan: {
        type: "object",
        properties: {
          id: { type: "string", description: "Signed plan token. Send it to /plans/apply." },
          project_id: { type: "string" },
          format: { type: "string" },
          digest: { type: "string" },
          base_digest: { type: "string" },
          expires_at: { type: "string", format: "date-time" },
          changes: { type: "array", items: { type: "object", additionalProperties: true } },
          total_changes: { type: "integer" },
          severity: { type: "string", enum: [ "reload", "restart", "redeploy" ] },
          by_severity: { type: "object", additionalProperties: { type: "integer" } },
          warnings: { type: "array", items: { type: "string" } },
          removals: { type: "array", items: { type: "object", additionalProperties: true } },
          requires_removal_confirmation: { type: "boolean" },
          removal_token: { type: "string", nullable: true }
        },
        required: [ "id", "project_id", "digest", "expires_at", "changes" ],
        additionalProperties: true
      },
      PlanEnvelope: {
        type: "object",
        properties: { plan: { "$ref" => "#/components/schemas/Plan" } },
        required: [ "plan" ],
        additionalProperties: false
      },
      Operation: {
        type: "object",
        properties: {
          id: { type: "string" },
          kind: { type: "string", enum: [ "deploy", "restart", "rollback", "manifest_apply", "project_deletion" ] },
          status: { type: "string", enum: [ "pending", "running", "succeeded", "failed", "cancelled" ] },
          project_id: { type: "string", nullable: true },
          service_id: { type: "string", nullable: true },
          subject: {
            type: "object",
            nullable: true,
            properties: {
              type: { type: "string" },
              id: { type: "string" }
            },
            additionalProperties: true
          },
          created_at: { type: "string", format: "date-time" },
          started_at: { type: "string", format: "date-time", nullable: true },
          completed_at: { type: "string", format: "date-time", nullable: true },
          error: { type: "string", nullable: true },
          result: { type: "object", nullable: true, additionalProperties: true }
        },
        required: [ "id", "kind", "status", "created_at" ],
        additionalProperties: true
      },
      OperationEnvelope: {
        type: "object",
        properties: { operation: { "$ref" => "#/components/schemas/Operation" } },
        required: [ "operation" ],
        additionalProperties: false
      },
      PlanCreateRequest: {
        type: "object",
        properties: {
          plan: {
            type: "object",
            properties: {
              project_id: { type: "string" },
              content: { type: "string", description: "Manifest content. Defaults to the project's stored manifest." },
              format: { type: "string", description: "raildock.toml, raildock.json, railway.toml, railway.json or app.json." }
            },
            required: [ "project_id" ],
            additionalProperties: false
          }
        },
        required: [ "plan" ],
        additionalProperties: false
      },
      PlanApplyRequest: {
        type: "object",
        properties: {
          plan: { type: "string", description: "The signed plan token from POST /plans." },
          confirm_removals: { type: "boolean" },
          removal_token: { type: "string", description: "Required when the plan removes services." },
          force_destroy_data: { type: "boolean", description: "Proceed without a verified pre-destroy snapshot. Destructive scope." }
        },
        required: [ "plan" ],
        additionalProperties: false
      },
      DeployRequest: {
        type: "object",
        properties: {
          branch: { type: "string" },
          commit_sha: { type: "string" },
          commit_message: { type: "string" }
        },
        additionalProperties: false
      },
      RollbackRequest: {
        type: "object",
        properties: { deployment_id: { type: "string" } },
        required: [ "deployment_id" ],
        additionalProperties: false
      }
    }
  end
end

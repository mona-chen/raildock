# RailDock Agent API

Token-scoped HTTP and MCP access to RailDock. The API is additive to the
dashboard surface under `/api`; the agent contract lives under `/api/v1` and is
served by dedicated presenters, never by the dashboard serializers.

- Human-readable contract: this document.
- Machine-readable contract: `GET /api/v1/openapi` (OpenAPI 3.1).
- MCP transport: `POST /mcp` (Streamable HTTP, JSON-RPC 2.0).

## Authentication

```http
Authorization: Bearer rd_...
```

An API token is a **delegated user**, not a new principal. It resolves to its
owner and organization; the member's role still decides what is allowed, and the
token narrows it with scopes plus an optional project/environment binding.

- The secret is shown once at creation. Only a SHA-256 digest is stored; the
  public `prefix` identifies the token in Settings and logs.
- Tokens can be revoked, never deleted, so audit rows keep resolving.
- Tokens carry their organization. A different `X-Organization-ID` is refused
  with `403`, never silently ignored.
- API tokens are delegated users but cannot change the owner's account profile
  (`PATCH /api/profile`); that endpoint requires a user JWT. Agent tokens also
  cannot change organization profiles without a member role, and never through
  `/api/v1` or MCP.
- User JWTs also work, but require `X-Organization-ID` to select the
  organization.

Failures are specific so an agent can stop retrying:

| Status | `code` | Meaning |
| --- | --- | --- |
| 401 | `token_invalid` | Unknown secret |
| 401 | `token_revoked` | Revoked token |
| 401 | `token_expired` | Expired token |
| 403 | `membership_revoked` | The token owner left the organization |

## Scopes and binding

| Scope | Minimum role | Allows |
| --- | --- | --- |
| `read` | member | Context, projects, services, logs, diagnosis, operations, plans |
| `deploy` | member | Deploy, restart, rollback |
| `config:write` | admin | Apply a reviewed plan (manifest, services, variables, domains) |
| `destructive` | admin/owner | Service removals, `force_destroy_data`, project deletion |

`read` is implicit and always included. A token bound to a project only sees
that project; a token bound to an environment only sees services in it.
Out-of-binding ids are `404`, not `403`, so a token cannot probe for existence.

Missing scope returns the same payload on REST and MCP:

```json
{
  "error": "This token lacks the deploy scope",
  "code": "scope_denied",
  "required_scope": "deploy",
  "granted_scopes": ["read"]
}
```

## Review, then apply

Manifests are never applied directly from an agent-supplied string. The flow is
plan → review → apply:

1. `POST /api/v1/plans`

   ```json
   {
     "plan": {
       "project_id": "12",
       "content": "[[services]]\nname = \"web\"\ncategory = \"app\"\nsubtype = \"web\"\n",
       "format": "raildock.toml"
     }
   }
   ```

   `content` may be omitted to plan the project's stored manifest. The response
   is a signed, 15-minute plan carrying the exact content, its digest, the base
   digest, the removals and the issuing token. Nothing is applied.

2. `POST /api/v1/plans/apply`

   ```json
   { "plan": "<plan token>", "confirm_removals": true, "removal_token": "<token>" }
   ```

   - The stored manifest must still match the plan's base digest, or the request
     returns `409 plan_drifted`. Create a new plan.
   - Expired plans return `422 plan_expired`.
   - A plan that removes services returns `428 removals_required` with the
     removal list and `removal_token` until `confirm_removals: true` and that
     token are supplied. `destructive` scope is also required.
   - A replay of the same plan returns the operation already created.

`force_destroy_data: true` skips the pre-destroy snapshot. It requires
`destructive` scope and is logged as a warning.

## Operations and idempotency

Deploy, restart, rollback and plan apply are asynchronous. Each returns an
operation:

```json
{
  "operation": {
    "id": "91",
    "kind": "deploy",
    "status": "running",
    "project_id": "12",
    "service_id": "34",
    "subject": { "type": "Deployment", "id": "77" },
    "created_at": "2026-11-19T10:00:00Z",
    "started_at": "2026-11-19T10:00:00Z",
    "completed_at": null,
    "error": null,
    "result": {
      "deployment_id": "77",
      "deployment_kind": "deploy",
      "deployment_status": "building"
    }
  }
}
```

Poll `GET /api/v1/operations/{id}`. Status is derived from the authoritative
deployment, manifest operation or deleting project, so it never disagrees with
the deployment UI.

`POST /api/v1/services/{id}/deploy`, `/restart` and `/rollback` require an
`Idempotency-Key` header (1–140 characters). Repeating the same key returns the
original operation with `200` and starts no second deployment. Reusing a key for
a different request returns `422 idempotency_key_reused`. Plan applies are keyed
by the plan itself.

## Redaction guarantees

Agent responses never contain:

- environment variable values,
- service config values,
- SSH keys or recovery keys,
- webhook tokens.

Callers get variable and config **names**, `webhook_configured`, and resolved
non-secret settings. Logs and build-log tails pass through the log redactor.
Diagnosis reads only stored deployments, metrics and activity and performs no
SSH. Missing metric samples are `available: false`, never zero usage.

Container metrics cover the primary container. They are not aggregated service
usage, HTTP analytics, traces or intrusion detection.

## Errors

All errors use `{ "error": "…", "code": "…" }` plus context where useful.

| Status | `code` | Meaning |
| --- | --- | --- |
| 400 | `organization_required` | JWT request without `X-Organization-ID` |
| 400 | `idempotency_key_required` | Missing `Idempotency-Key` header |
| 403 | `scope_denied` | Token lacks the required scope |
| 404 | `not_found` | Missing or outside the token binding |
| 409 | `plan_drifted` | The stored manifest changed after the plan was issued |
| 409 | `resource_busy` | Another operation holds the service/project lock |
| 422 | `plan_expired` | The signed plan expired |
| 422 | `invalid_plan` | Malformed or tampered plan token |
| 422 | `idempotency_key_reused` | The key belongs to a different request |
| 422 | `not_deployable` | Databases are managed by Dokku directly |
| 422 | `rollback_not_precise` | The target has no commit SHA |
| 428 | `removals_required` | Confirm the exact services to destroy |
| 428 | `snapshot_required` | No verified pre-destroy snapshot is available |
| 429 | `rate_limited` | Per-token budget exhausted; honor `Retry-After` |

## Rate limits

Each token gets 120 requests per minute (set `AGENT_RATE_LIMIT_PER_MINUTE` to
change it). The counter lives in the shared cache and expires with the window.
A `429` response includes `Retry-After` seconds. A cache failure disables
limiting rather than failing the request.

## MCP

`POST /mcp` speaks MCP Streamable HTTP (JSON-RPC 2.0). It is stateless: no
`Mcp-Session-Id` is issued, and `GET`/`DELETE` are not supported (405). Use the
same `Authorization: Bearer rd_...` header.

Supported methods: `initialize`, `ping`, `tools/list`, `tools/call`,
`resources/list`, `resources/templates/list`, `resources/read`. Notifications
(no `id`) return `202` with no body. Batch requests are rejected.

### Tools

| Tool | Scope | Purpose |
| --- | --- | --- |
| `get_context` | read | Organization, actor, capabilities, servers, projects, services |
| `list_services` | read | Services, optionally filtered by project/environment |
| `get_service` | read | Configuration, domains, mounts, links, variable names |
| `diagnose_service` | read | Stored deployments, metrics, activity (no SSH) |
| `query_logs` | read | Recent logs, with stored fallback and a reason |
| `plan_change` | read | Diff a manifest and return a signed plan |
| `apply_plan` | config:write (+ destructive for removals) | Apply a reviewed plan |
| `get_operation` | read | Poll asynchronous work |
| `deploy` | deploy | Start a deployment |
| `rollback` | deploy | Deploy an earlier commit |

`deploy` and `rollback` take an `idempotency_key` argument instead of a header.
Expect a tool result with `isError: true` and the same `code` payload as the
REST surface for expected failures. Unknown tools and malformed arguments are
JSON-RPC errors (`-32602`).

### Resources

- `raildock://context/{organization}` — the same payload as `GET /api/v1/context`.
- `raildock://openapi` — the OpenAPI document.

## Not implemented yet

- `POST /api/v1/projects/{id}/deployments` (bulk deploy).
- `DELETE /api/v1/projects/{id}` — use the dashboard's queued deletion for now;
  it records the same operation and typed confirmation protocol.

## SDK and examples

Any MCP client works. For plain HTTP, send the token header and poll operations:

```bash
curl -sS https://raildock.example.com/api/v1/context \
  -H "Authorization: Bearer $RAILDOCK_TOKEN"

curl -sS https://raildock.example.com/api/v1/services/34/deploy \
  -H "Authorization: Bearer $RAILDOCK_TOKEN" \
  -H "Idempotency-Key: deploy-2026-11-19-1" \
  -H "Content-Type: application/json" -d '{}'
```

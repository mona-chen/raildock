---
title: "Agent Access API"
type: feat
date: 2026-11-19
status: active
---

# Agent Access API

## Problem Frame

Coding agents can already operate a RailDock installation — by shelling into the
host, calling Dokku, and reading the dashboard's network traffic. That is the
worst of both worlds: the agent gets no structured context, and every safety
property RailDock implements is bypassed.

The dashboard API is not a substitute. `Authenticatable` accepts one HS256 JWT
holding a `user_id`, valid for 30 days, with no scopes, no revocation and no
attribution. `/api` is the dashboard's private contract: bodies are wrapped
(`wrapBody`), camelCase happens in `app/src/lib/apiTransforms.ts`, ids are
normalized client-side, and the model serializers are built for that client:
`Service#as_json` includes `environment_variables.value` (and, before this
change, the raw `webhook_token`), and `Project#as_json` emits every column.

What is missing is not a deployment engine. RailDock already has one, plus a
destructive-operation protocol that is unusually well suited to machines:

| Property | Where it already exists |
| --- | --- |
| Plan before change | `ManifestReconciler#diff`, `POST /api/projects/:id/manifest/preview` |
| Signed approval of an exact change | `RemovalConfirmation` (project + digest + removals, 30 min) |
| Durable async work | `ManifestApplyJob`, `Deployment`, `ProjectDeletionJob` (`202` + status) |
| Serialized mutations | `ServiceOperationLock` → `409 resource_busy` |
| Machine-readable refusal | `428 precondition_required` + `code` |
| Evidence for diagnosis | `logs`, `metrics`, `container_status`, `deployments`, `ActivityEvent` |
| Scope boundaries | `Environment` per project, `Authorizable::PERMISSIONS` |

The gap is an identity for the agent, a stable envelope around those
capabilities, and composition so an agent does not need ten calls to answer one
question.

## Scope Boundaries

### In Scope

- Organization-scoped API tokens with explicit scopes, optional project and
  environment binding, expiry, revocation and last-used tracking.
- A versioned, additive `/api/v1` surface for agents. `/api` keeps serving the
  dashboard unchanged.
- Read-only context and diagnosis endpoints built on existing models, with a
  dedicated presenter that never returns secret values.
- Plan/apply for changes, reusing `ManifestReconciler` and the
  `RemovalConfirmation` token pattern instead of a second reconciler.
- A uniform operation handle over existing durable records.
- Attribution of agent actions in `ActivityEvent`.
- A thin MCP adapter exposing a curated subset of the same service objects.

### Deferred to Follow-Up Work

- OAuth 2.1 authorization server and third-party client registration. The token
  model keeps `client_id` and `audience` so it can be added without a rewrite.
- An approvals UI and policy engine beyond scopes and environment binding.
- Generated SDKs, webhooks, and streaming operation events.
- Multi-agent coordination and automatic remediation.

### Outside This Product's Identity

- A tool that executes arbitrary SSH or Docker commands. That would bypass typed
  confirmations, pre-destruction snapshots and project locks in one step.
- A second deployment engine, or agent-only resource state.
- An in-product LLM assistant. That is a separate product with separate risk.

## Current State

Verified against the repository at `010a55e`:

- `backend/app/controllers/concerns/authenticatable.rb` — Bearer JWT only,
  `user_id` claim, 30-day expiry, organization resolved from `X-Organization-ID`.
- `backend/app/controllers/concerns/authorizable.rb` — role checks per resource
  action; `AuthorizationDenied` is re-raised by broad rescues.
- `backend/app/controllers/api/base_controller.rb` — maps
  `ServiceOperationLock::Busy` to `409` with `code: "resource_busy"`.
- `backend/app/services/removal_confirmation.rb` — stateless signed token bound
  to project, manifest digest and the exact removal list.
- `backend/app/controllers/api/manifests_controller.rb` — preview is synchronous
  and returns `changes`, `severity` and `removal_token`; apply enqueues
  `ManifestApplyJob` and returns an ActiveJob `job_id` that no endpoint can poll.
- `backend/app/models/manifest_operation.rb` — durable record for the destructive
  finalizer only; created for applies that have removals.
- `backend/db/schema.rb` — `deployments.idempotency_key` already has a unique
  index; `activity_events` has `action`, `message`, `service_name`, `metadata`
  and no actor.
- `backend/app/models/service.rb` — `as_json` embeds `environment_variables`
  with `:value` and every column, including `webhook_token`.
- `backend/app/models/project.rb` — `as_json` serializes every column plus
  `environments`; neither serializer is suitable for an agent-facing payload.

## Key Technical Decisions

**D1. A token is a delegated user, not a new principal type.** `ApiToken`
belongs to a `user` and an `organization`. The effective permission is the
intersection of that user's membership role, the token's scopes, and the token's
project/environment binding. This reuses every existing authorization helper
instead of forking the permission model.

**D2. `/api/v1` is additive and presenter-based.** No controller in `Api::`
changes shape. v1 controllers own their serializers (`Api::V1::Presenters::*`),
return snake_case JSON with string ids, and never call `as_json` on a model that
holds secrets.

**D3. A plan is a signed token, not a row.** `plan_id` is an opaque signed
payload: project, environment, manifest digest, requested change digest, token
id, expiry (15 minutes). It cannot be forged, it cannot be replayed against a
different manifest, and it needs no cleanup job. `RemovalConfirmation` is the
same pattern and already proven.

**D4. Operations point at the authoritative record.** A small `operations` table
stores `id`, `kind`, `subject_type`, `subject_id`, `api_token_id`,
`idempotency_key` and `created_at`. Status is read through to `Deployment`,
`ManifestOperation` or `Project` on every request, so it cannot drift. The
`idempotency_key` is unique, which is what stops an agent loop from deploying
twice.

**D5. MCP is a transport, not an architecture.** One authenticated `/mcp`
endpoint calls the same Ruby services as v1. No controller-to-controller HTTP,
no duplicated validation.

**D6. Secrets never leave the server.** Context and diagnostics return variable
names and `set: true`, never values, never SSH keys, never recovery keys.
`AGENTS.md` already requires diff labels to name fields rather than values; the
agent surface follows the same rule.

**D7. Destructive operations keep the 428 protocol.** An agent receives
`428 precondition_required` with `code: "snapshot_required"` or
`"removals_required"`, an impact summary and a signed token. It retries with
that token and the typed name. There is no agent-only bypass, and `destructive`
scope is required in addition to the confirmation.

## Data Model

`api_tokens`:

| Column | Notes |
| --- | --- |
| `organization_id` | required, scopes the token |
| `user_id` | delegated owner; membership still checked per request |
| `name` | shown in Settings → Agent access |
| `token_digest` | SHA-256 of the secret, unique |
| `prefix` | first 8 characters after `rd_`, for identification and secret scanning |
| `scopes` | `jsonb`, subset of `read`, `deploy`, `config:write`, `destructive` |
| `project_id`, `environment_id` | nullable binding; environment implies project |
| `expires_at`, `last_used_at`, `revoked_at` | nullable |
| `client_id`, `audience` | nullable, reserved for OAuth |

`activity_events` gains a nullable `api_token_id`. A helper records
`actor: token ? "token:<prefix>" : "user:<id>"` in `metadata` so existing rows
stay valid.

## API Surface

| Method | Path | Scope | Notes |
| --- | --- | --- | --- |
| GET | `/api/v1/context` | `read` | servers → projects → environments → services → links, plus `allowed_actions` |
| GET | `/api/v1/projects/:id` | `read` | manifest summary, environments, services, drift flag |
| GET | `/api/v1/services/:id` | `read` | config names, domains, mounts, links; values redacted |
| GET | `/api/v1/services/:id/logs` | `read` | cursor pagination, `limit` ≤ 500 |
| GET | `/api/v1/services/:id/diagnose` | `read` | last deployments, build-log tail, container status, health, 1h metrics, recent events |
| POST | `/api/v1/plans` | `read` | manifest content or change request; returns `plan_id`, changes, severity, `expires_at` |
| POST | `/api/v1/plans/apply` | `config:write` (+ `destructive` for removals) | validates the base digest and removal token, enqueues the existing job, returns an operation |
| POST | `/api/v1/projects/:id/deployments` | `deploy` | planned: bulk deploy for an environment; requires `Idempotency-Key` |
| POST | `/api/v1/services/:id/deploy` | `deploy` | requires `Idempotency-Key`; returns an operation |
| POST | `/api/v1/services/:id/restart` | `deploy` | requires `Idempotency-Key`; returns an operation |
| GET | `/api/v1/operations/:id` | `read` | `{id, kind, status, subject, result, error, timestamps}` |
| DELETE | `/api/v1/projects/:id` | `destructive` | planned: typed `confirmation`; `428` on a missing snapshot, `202` when queued; records an operation |

Errors use the existing shape plus a stable `code`: `confirmation_required`,
`snapshot_required`, `removals_required`, `plan_expired`, `plan_drifted`,
`scope_denied`, `resource_busy`, `idempotency_conflict`.

`scope_denied` includes `required_scope` and the token's binding so an agent can
report precisely what it lacks instead of retrying.

## Permission Model

Effective permission for a request is:

```
membership role  ∩  token scopes  ∩  token binding
```

- `read` — any member role. Context, services, logs, metrics, diagnosis.
- `deploy` — `member` or above. Deploy, restart, scale, rollback.
- `config:write` — `admin` or above. Variables, domains, mounts, manifest edits
  and applying a reviewed plan.
- `destructive` — `owner`/`admin` plus the typed confirmation and snapshot
  protocol. Delete a project, remove a service, restore a backup.

A token bound to an environment may only touch services in that environment;
the existing bulk endpoints already accept `environment_id`, so this is a
predicate, not a new code path. Tokens are revoked, never deleted, so audit rows
keep resolving.

## Implementation Status

- **U1 implemented**: `ApiToken` (digest-only secrets, scopes, project and
  environment binding, expiry, revocation, throttled `last_used_at`),
  `Bearer rd_…` authentication in `Authenticatable`, and
  `GET/POST/DELETE /api/api-tokens` for owner/admin.
- **U2 implemented**: `/api/v1/context`, `/api/v1/projects/:id`,
  `/api/v1/services/:id`, `/api/v1/services/:id/logs` and
  `/api/v1/services/:id/diagnose`, with presenters that never serialize
  variable values, config values or the webhook token. Diagnosis reads stored
  evidence only and performs no SSH.
- **Security fix shipped with U1**: `Service#as_json` no longer emits the raw
  `webhook_token`; the dashboard only needs `webhook_url`.
- **Settings pane shipped**: Settings → Agent Access lists tokens with prefix,
  scopes, binding and last use, creates tokens (name, scopes, project and
  environment binding, expiry) and shows the secret once in a copy dialog.
  Revoking goes through the app confirm dialog.
- **U3 implemented**: `AgentPlan` issues a signed, 15-minute plan carrying the
  exact content, its digest, the stored-manifest base digest, the removal list
  and the issuing token. `POST /api/v1/plans` diffs the stored manifest or a
  supplied `content`; `POST /api/v1/plans/apply` refuses when the stored
  manifest moved (`409 plan_drifted`), requires `confirm_removals` + the
  reviewed `removal_token` + the `destructive` scope when the plan removes
  services, and attaches a replay to the operation already started. The plan
  token travels in the body, not the URL, so a multi-kilobyte manifest does not
  have to fit in a path segment.
- **U4 implemented**: `Operation` is a thin pointer to the authoritative record
  (`Deployment`, `ManifestOperation`, or the deleting `Project`) and derives its
  status from it. `GET /api/v1/operations/:id` returns the uniform envelope.
  `POST /api/v1/services/:id/deploy` and `/restart` require `Idempotency-Key`;
  a repeat returns the original operation with `200` and starts no second job.
  Plan applies are keyed by the plan's `jti`, and project deletion (queued
  through the existing dashboard path) records an operation whose status follows
  `deletion_status` and is finished by the host job. Agent writes record the
  token on `ActivityEvent#api_token_id`.
- **Pending**: U5 (MCP) and U6 (OpenAPI).

## Implementation Units

### U1. Token model, Bearer authentication, management API

- `backend/db/migrate/*_create_api_tokens.rb`, `backend/app/models/api_token.rb`.
- `backend/app/controllers/concerns/authenticatable.rb`: accept `Bearer rd_…`,
  set `@current_token`, keep the JWT path unchanged, reject revoked/expired
  tokens with `401` and `code: "token_revoked"`.
- `backend/app/controllers/api/api_tokens_controller.rb`: list, create (secret
  returned once), revoke. Owner/admin only.
- `ActivityEvent` actor column and helper.
- Tests: `spec/requests/api/api_tokens_spec.rb`, `spec/models/api_token_spec.rb`.

Acceptance: a token authenticates against an existing endpoint, a revoked token
returns 401, a token never appears in logs, and `last_used_at` advances.

### U2. v1 presenters, context and diagnosis

- `backend/app/controllers/api/v1/base_controller.rb` (token required,
  scope check, cursor pagination helper).
- `backend/app/serializers/api/v1/{context,project,service,diagnosis}_presenter.rb`.
- `GET /context`, `/projects/:id`, `/services/:id`, `/services/:id/logs`,
  `/services/:id/diagnose`.
- Diagnosis composes existing data only; no new collection work.

Acceptance: context for a project with two services and one link returns in one
call; no `config` value, SSH key or recovery key appears anywhere in the
response; a token bound to `staging` sees only `staging` services.

### U3. Plans and apply

- `backend/app/services/agent_plan.rb` — wraps `ManifestParser`,
  `ManifestReconciler#diff`, `ChangeClassifier` and `RemovalConfirmation`
  semantics; issues and verifies the signed `plan_id`.
- `POST /plans` and `POST /plans/apply`; apply re-reads the stored manifest and
  refuses when the digest moved (`409 plan_drifted`).
- Removals require the reviewed removal token, `confirm_removals: true` and the
  `destructive` scope; a plan whose removals are unconfirmed returns
  `428 removals_required` with the removal list and a freshly issued token.

Acceptance: applying an unchanged manifest is a no-op with a successful
operation; a plan applied after an edit returns `409 plan_drifted`; a plan with
removals returns `428 removals_required` until the token is supplied.

### U4. Operations envelope and idempotency

- `backend/db/migrate/*_create_operations.rb`, `backend/app/models/operation.rb`.
- `GET /operations/:id` resolves the subject and returns a uniform body.
- `Idempotency-Key` required on deploy/restart writes; a repeat with the same
  key returns the original operation with `200` instead of starting new work.
  Plan applies use the plan's `jti`, and project deletion records an operation
  from the queued dashboard path.
- Deploy, restart, plan apply and project deletion all record an operation.
  Status is derived from the `Deployment`/`ManifestOperation`/`Project` when
  that record can report it; an additive apply and a post-destroy deletion keep
  the terminal outcome on the operation because no record survives to report it.

Acceptance: two identical deploy requests with one key produce one
`Deployment`; polling an operation while the job runs returns `running`, then
the terminal status; a cancelled deployment reports `cancelled`.

### U5. MCP adapter

- `backend/app/controllers/mcp_controller.rb`, mounted at `/mcp`, Streamable
  HTTP, bearer token or `X-Organization-ID` + token.
- Tools: `get_context`, `list_services`, `get_service`, `diagnose_service`,
  `query_logs`, `plan_change`, `apply_plan`, `get_operation`, `deploy`,
  `rollback`. Each maps to a v1 service object, not an HTTP call.
- Resource: `raildock://context/{organization}` returning the same presenter.

Acceptance: an MCP client lists the ten tools, a `plan_change` followed by
`apply_plan` deploys, and every tool rejects an out-of-scope token with the same
`scope_denied` payload as v1.

### U6. Documentation and OpenAPI

- `docs/agents-api.md`: authentication, scopes, error codes, the 428 flow,
  redaction guarantees, and the limits of diagnosis.
- OpenAPI 3.1 document generated from the v1 serializers.
- `AGENTS.md` gets one paragraph so future changes keep the surfaces aligned.

## Test Plan

- Authentication: missing, malformed, expired, revoked, wrong organization,
  token whose user lost membership.
- Scope: each scope against each endpoint, including environment-bound tokens
  and `scope_denied` payloads.
- Secrets: assert no `config` value, `LOCKBOX` key, SSH key or recovery key in
  context, service, diagnosis or MCP responses.
- Plans: expiry, digest drift, removal token mismatch, replay after apply.
- Operations: idempotent replay, concurrent deploys on one service
  (`409 resource_busy`), cancellation, worker interruption recovery.
- Destructive: typed name, missing snapshot (`428`), queued deletion (`202`),
  duplicate request attaches.
- Audit: every agent write produces an `ActivityEvent` with a token actor.
- Regression: the existing 1548 backend examples and 174 frontend tests stay
  green; `/api` contracts are unchanged.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Token leakage in logs or responses | Store a digest, show the secret once, never log `Authorization`, redact `token` fields in error reporting |
| An agent loop deploys continuously | Required `Idempotency-Key`, unique index, operation dedupe, per-token rate limit |
| Scope confusion grants too much | Deny by default; the token's binding is applied in `Authorizable`, not in each controller |
| Diagnostics leak secrets | Dedicated presenters, values never serialized, a spec that greps the response for known fixture secrets |
| Stale plan applied to changed state | Signed digest, 15-minute expiry, `409 plan_drifted` |
| Two agents change one service | Existing `ServiceOperationLock`; v1 does not add a bypass |
| Audit cannot name the actor | `api_token_id` on `ActivityEvent`, `last_used_at` on the token, revocation instead of deletion |

## Rollout

1. Ship U1 + U2 behind an owner/admin-only settings pane (Settings → Agent
   access). Read-only tokens cannot change anything, so the blast radius is a
   leaked read token.
2. Add U3 + U4 once token scoping has been exercised against a real project.
3. Publish `/mcp` and the OpenAPI document last; by then the tools are thin
   wrappers over proven endpoints.

## Decisions on Open Questions

- **Additive manifest applies have a durable operation now.** Plan apply
  always creates an `Operation`; the host job marks it running/succeeded/failed,
  and an apply that defers removals points the operation at the existing
  `ManifestOperation` so its status keeps coming from the finalizer. The
  reconciler still does not create a second status source; the operation is the
  pointer the caller polls.
- **Scope granularity stays at four.** `config:write` covers variables, domains
  and mounts for now. Splitting it into `variables:write` and `routing:write`
  waits for a real agent that needs routing without variables; four scopes are
  easier to reason about and to audit.
- **Binding is project + environment only.** Per-service tokens are not worth
  the matrix yet; a token bound to an environment already covers the
  "staging only" case that makes delegation useful.
- **Rate limits are per token**, enforced in U5 before `/mcp` is published. The
  database is not the place for the counter.

## Open Questions

- Does an additive manifest apply need its own durable record, or is
  project-level manifest status enough for agents in practice? U4 will answer
  this with real usage.
- Should `config:write` split once agents manage routing? Revisit after the
  first routing request.
- Which rate-limit window fits agent retries: per minute with bursts, or a
  token budget per hour? Needed before `/mcp` is public.

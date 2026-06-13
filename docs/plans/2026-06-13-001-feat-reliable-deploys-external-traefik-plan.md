---
title: Reliable deploy orchestration and external Traefik integration
type: feat
status: active
date: 2026-06-13
---

# Reliable Deploys and External Traefik

## Problem Frame

RailDock has several deployment entry points that converge on `DeploymentJob`, but they do not yet share reliable orchestration invariants. Manifest changes can fail to diff, links can lose direction, deployments can start before links and runtime values exist, rollback ignores the selected commit, and queued deployments can expose misleading service status.

RailDock also assumes it should configure and run Dokku's proxy. On hosts that already run a Traefik instance, such as a Matrix deployment, starting another proxy creates port and ownership conflicts. RailDock needs an opt-in external proxy mode that leaves the existing Traefik lifecycle untouched, attaches Dokku app containers to an explicitly selected Docker network, and applies compatible HTTP and HTTPS labels.

## Scope

### Included

- Repair the correctness issues in the reviewed deployment paths.
- Preserve intentional deploy requeueing while making status transitions queue-aware.
- Add stale deployment reconciliation.
- Add a server-level external Traefik mode.
- Discover candidate Traefik containers and Docker networks through authenticated server APIs.
- Require explicit external network selection and validate that selection.
- Generate global default HTTP/HTTPS labels with per-service overrides.
- Attach deployed application containers to both their private project network and the external proxy network.
- Keep existing managed Dokku proxy behavior as the default.
- Update installer behavior and `AGENTS.md` for the new proxy mode.

### Deferred

- Importing `railway.json` or `railway.toml`.
- Managing or restarting the external Matrix Traefik container.
- Editing the external Traefik static configuration, entrypoints, certificate resolvers, or middleware definitions.
- Automatically moving an existing live app between proxy modes without an explicit redeploy.
- Enforcing only one pending deployment per service; explicit requeueing remains supported.

## Requirements

1. Existing installations continue using RailDock-managed Dokku proxy behavior unless external mode is explicitly enabled.
2. External mode never starts, stops, upgrades, or reconfigures the existing Traefik process.
3. Network discovery returns enough metadata to identify which networks contain a Traefik container.
4. The user explicitly selects the external proxy network; discovery may recommend but must not silently persist a choice.
5. Each externally routed app receives:
   - `traefik.enable=true`
   - `traefik.docker.network=<selected network>`
   - an HTTP router rule and entrypoint
   - an HTTPS router rule, entrypoint, TLS setting, and optional certificate resolver
   - a load-balancer service port label
6. Global server defaults are overridable per service without deleting unrelated custom labels.
7. Manifest and template deployments finish resource, link, network, and runtime preparation before application deployments are enqueued.
8. Rollback deploys the selected commit, not merely the selected deployment's branch.
9. Service status reflects whether another deployment is queued or running after the current deployment finishes.
10. Pending or deploying records that no longer have viable queue execution are eventually marked failed with an actionable message.

## Key Decisions

### Server-owned external proxy configuration

Store proxy integration settings on `Server`, because the external Traefik instance and Docker network are host-level resources shared by projects:

- `proxy_mode`: `managed` or `external`
- `external_proxy_network`
- `external_proxy_http_entrypoint`
- `external_proxy_https_entrypoint`
- `external_proxy_cert_resolver`
- `external_proxy_redirect_middleware`
- `external_proxy_default_labels` as JSON

`default_proxy` remains the detected Dokku proxy plugin and is not overloaded with lifecycle mode.

### Docker labels through Dokku docker options

External Traefik reads labels directly from application containers. Apply labels as Dokku `docker-options` for deploy and run phases, not through Dokku's `traefik:labels:*` plugin commands. This avoids coupling external mode to Dokku's managed Traefik plugin.

Label reconciliation must remove previously RailDock-managed label options before adding the current generated set. Persist the generated set in service configuration so removal is deterministic and custom user labels remain intact.

### Two-network model

Project networks remain responsible for private service discovery. External mode adds a second attach-post-create network for the proxy. Network management should accept injected `DokkuEngine` and `HostEngine` instances so session reuse remains effective.

### Deploy orchestration barrier

Manifest and template preparation jobs should collect deployment records first but enqueue application deployments only after all synchronous preparation phases succeed. Dependencies require completion ordering, not only enqueue ordering; deploy dependent services after prerequisite deployment jobs have succeeded or use a dedicated orchestration job that advances the graph.

### Queue-aware service state

After a deployment completes, derive service status from remaining active deployments:

- another pending/building/deploying record exists: `deploying`
- no active deployment and current succeeded: `running`
- no active deployment and current failed: `error`

## Implementation Units

### U1: Correct manifest diffing, links, and deployment batching

**Files**

- `backend/app/services/manifest_reconciler.rb`
- `backend/app/jobs/manifest_apply_job.rb`
- `backend/spec/services/manifest_reconciler_spec.rb`
- `backend/spec/jobs/manifest_apply_job_spec.rb`

**Changes**

- Use symbol keys consistently when diffing desired and actual service state.
- Preserve directed `(from, to)` link identity.
- Group redeploy changes per service and update every changed field before creating one deployment.
- Apply links before enqueueing newly created or changed application deployments.
- Resolve all runtime markers after links exist, including general linked variables.
- Sync canonical datastore URLs consistently for PostgreSQL, MySQL/MariaDB, Redis, and MongoDB.
- Wrap manifest application in shared Dokku and host SSH sessions and inject those engines into helpers.
- Mark manifest apply success only after preparation completed and deployments were successfully queued.

**Test scenarios**

- A changed branch produces one redeploy change and one deployment.
- Multiple redeploy-class fields on one service produce one deployment containing all updates.
- `web -> postgres` remains directed and calls the PostgreSQL link command with database then app.
- A new app deployment is not enqueued until its database link and runtime variables are applied.
- A failed link leaves the app deployment failed/not queued and reports manifest failure.
- Reapplying an unchanged manifest creates no services, links, or deployments.

### U2: Make template deployment scoped, failure-safe, and dependency-aware

**Files**

- `backend/app/controllers/api/templates_controller.rb`
- `backend/app/jobs/template_deploy_job.rb`
- `backend/spec/requests/api/templates_spec.rb`
- `backend/spec/jobs/template_deploy_job_spec.rb`

**Changes**

- Pass created service IDs and deployment IDs to `TemplateDeployJob`.
- Operate only on services created by that template invocation.
- On setup failure, mark the invocation's pending deployments failed and affected app services error.
- Enqueue application deployments only after resources, links, networks, and runtime resolution succeed.
- Replace enqueue-order-only dependency handling with completion-aware orchestration.
- Make retry behavior idempotent by finding the invocation's records rather than arbitrary pending records.

**Test scenarios**

- Deploying a template into a project with existing services does not modify or redeploy existing services.
- Retrying the setup job does not create duplicate services, links, or deployments.
- A datastore/link failure transitions all invocation deployments out of pending.
- A dependent app is not deployed until its prerequisite app succeeds.

### U3: Fix rollback, commit pinning, deployment status, and stale cleanup

**Files**

- `backend/app/jobs/deployment_job.rb`
- `backend/app/controllers/api/services_controller.rb`
- `backend/app/models/deployment.rb`
- `backend/app/jobs/reconcile_stale_deployments_job.rb`
- `backend/config/recurring.yml`
- `backend/spec/jobs/deployment_job_spec.rb`
- `backend/spec/jobs/reconcile_stale_deployments_job_spec.rb`
- `backend/spec/requests/api/services_spec.rb`

**Changes**

- Make git deployment honor `deployment.commit_sha`; fetch/sync the branch, then deploy the requested revision using a Dokku-supported pinned-ref flow.
- Reject rollback targets without a usable revision instead of presenting a false rollback.
- Reuse the existing host session throughout database readiness and post-deploy helpers.
- Check critical Dokku configuration results and fail deployment when routing, environment, storage, or required scaling setup fails.
- Compute final service status from remaining active deployments.
- Add recurring stale-record reconciliation with separate queue-wait and execution-age thresholds.
- Record actionable stale failure messages and broadcast/invalidate status.
- Treat `building` and `cancelled` as either implemented states across backend/frontend or remove them in a separate migration; initially use `building` during rebuild and support it in frontend types.

**Test scenarios**

- Rollback to a known SHA issues a pinned deploy command for that SHA.
- A failed required configuration operation marks deployment failed.
- Deployment A finishing while B is pending leaves the service deploying.
- A stale pending job becomes failed while a recently queued job remains pending.
- A stale deploying job becomes failed and the service status is recomputed.

### U4: Add webhook idempotency and deployment provenance

**Files**

- `backend/db/migrate/*_add_idempotency_key_to_deployments.rb`
- `backend/app/models/deployment.rb`
- `backend/app/controllers/api/webhooks_controller.rb`
- `backend/app/controllers/api/github_apps_controller.rb`
- `backend/spec/requests/api/webhooks_spec.rb`
- `backend/spec/requests/api/github_apps_spec.rb`

**Changes**

- Add an optional idempotency key with a partial unique index scoped appropriately.
- Use GitHub delivery ID and service ID for GitHub App deduplication.
- Derive a stable key from provider, repository, ref, commit, and service for generic webhook requests when a delivery identifier is absent.
- Reject per-service webhook deploys for database services.
- Keep explicit UI requeue operations unrestricted.

**Test scenarios**

- Repeated GitHub delivery creates one deployment.
- Different commits create separate deployments.
- Generic duplicate payloads do not create duplicate deployments.
- Manual Deploy All still creates a new deployment each time.

### U5: Model and API for external Traefik settings and discovery

**Files**

- `backend/db/migrate/*_add_external_proxy_settings_to_servers.rb`
- `backend/app/models/server.rb`
- `backend/app/controllers/api/servers_controller.rb`
- `backend/app/controllers/api/networks_controller.rb`
- `backend/app/services/host_engine.rb`
- `backend/config/routes.rb`
- `backend/spec/models/server_spec.rb`
- `backend/spec/requests/api/servers_spec.rb`
- `backend/spec/requests/api/networks_spec.rb`

**Changes**

- Add and validate server proxy mode/settings.
- Replace the unauthenticated stub network endpoint with a server-scoped, authorized discovery endpoint.
- List Docker networks and inspect connected containers.
- Identify candidate Traefik containers from image/name/labels and return recommended networks without auto-selecting one.
- Add a validation endpoint that confirms the selected network exists and contains the selected/candidate proxy.
- Avoid exposing sensitive container environment or label values.

**Test scenarios**

- Unauthorized callers cannot enumerate host networks.
- Discovery marks a network containing a Traefik image as recommended.
- Bridge/host/none networks are not offered as normal external selections.
- Validation fails for missing networks and succeeds for an existing Traefik-connected network.
- Managed-mode servers do not require external settings.

### U6: Generate and reconcile external Traefik labels

**Files**

- `backend/app/services/traefik_label_builder.rb`
- `backend/app/services/external_proxy_configurator.rb`
- `backend/app/services/service_settings_sync.rb`
- `backend/app/jobs/deployment_job.rb`
- `backend/app/controllers/api/domains_controller.rb`
- `backend/spec/services/traefik_label_builder_spec.rb`
- `backend/spec/services/external_proxy_configurator_spec.rb`
- `backend/spec/requests/api/domains_spec.rb`

**Changes**

- Generalize label generation for standard and wildcard domains.
- Generate separate HTTP and HTTPS routers with configurable entrypoints, resolver, and redirect middleware.
- Use stable sanitized router/service names.
- Merge server defaults, generated domain labels, and per-service overrides with per-service values winning.
- In external mode disable Dokku's per-app proxy, clear public port mappings, apply container labels, and configure external network attachment.
- On domain deletion remove obsolete managed labels.
- Preserve unrelated custom docker options and labels.

**Test scenarios**

- Standard domain produces correct HTTP, HTTPS, TLS, service-port, enable, and network labels.
- HTTPS works without a certificate resolver when the external proxy handles certificates another way.
- Per-service labels override global defaults.
- Removing a domain removes only labels owned by that domain.
- Managed mode continues using current Dokku proxy/domain commands.

### U7: External proxy network attachment during every deploy path

**Files**

- `backend/app/services/project_network_manager.rb`
- `backend/app/jobs/deployment_job.rb`
- `backend/app/jobs/template_deploy_job.rb`
- `backend/app/services/manifest_reconciler.rb`
- `backend/spec/services/project_network_manager_spec.rb`
- `backend/spec/jobs/deployment_job_spec.rb`

**Changes**

- Inject the shared `HostEngine` into `ProjectNetworkManager`.
- Attach external-mode app containers to the configured proxy network before startup where Dokku permits, then verify post-deploy attachment.
- Keep database containers off the external proxy network unless explicitly exposed in future work.
- Fail deployment when external mode is enabled but the configured proxy network is unavailable.
- Keep project-network aliases independent from proxy-network attachment.

**Test scenarios**

- External-mode app is attached to both project and proxy networks.
- Database service is attached only to the project network.
- Missing external network fails before reporting deployment success.
- Session reuse is preserved across network operations.

### U8: Installer and UI configuration

**Files**

- `install.sh`
- `docker-compose.yml`
- `app/src/pages/ServerPage.tsx`
- `app/src/lib/api.ts`
- `app/src/types/index.ts`
- `app/src/hooks/useServers.ts`
- `app/src/__tests__/components.test.tsx`
- `AGENTS.md`

**Changes**

- Add installer mode `PROXY_MODE=managed|external`.
- In external mode skip `dokku proxy:set --global traefik`, skip `dokku traefik:start`, and never stop host nginx/Traefik services.
- Allow optional initial external network/entrypoint/resolver values in `.env` and local server creation.
- Add server UI controls for mode, discovery, explicit network selection, HTTP/HTTPS entrypoints, resolver, redirect middleware, and default labels.
- Show validation results and warn that RailDock does not manage the external Traefik lifecycle.
- Document Matrix/existing-Traefik installation and rollback to managed mode.

**Test scenarios**

- Managed installer behavior remains unchanged.
- External installer mode never invokes Dokku Traefik start/global proxy setup.
- UI requires a validated network before saving external mode.
- Switching back to managed mode retains external settings but stops applying them.

## Sequencing

1. U1 and U2 establish preparation-before-enqueue invariants.
2. U3 establishes reliable universal deployment behavior.
3. U4 adds event-level idempotency after queue semantics are stable.
4. U5 introduces external proxy configuration and discovery without changing deploy behavior.
5. U6 adds label generation and reconciliation.
6. U7 integrates network attachment into deployment paths.
7. U8 exposes and documents the feature.

## Operational Rollout

1. Deploy database migrations with `proxy_mode` defaulting to `managed`.
2. Release discovery and validation APIs before enabling external behavior.
3. Configure the Matrix host's Traefik Docker provider to watch the selected network if it does not already.
4. Select and validate the existing Traefik network in RailDock.
5. Redeploy one test app with a non-critical hostname.
6. Verify HTTP redirect, HTTPS certificate behavior, routing, and network membership.
7. Move remaining apps after the canary succeeds.

## Verification

- Backend request, service, and job specs cover each deployment entry path.
- Deployment integration tests assert command ordering: resources, links, runtime values, labels/network, then deployment.
- Frontend tests cover external-mode configuration and validation states.
- A host-level smoke test uses a pre-existing Traefik container and network, deploys a sample app, and verifies routing without starting Dokku Traefik.
- Existing managed-proxy smoke tests remain green.

## Risks

- Dokku versions differ in support for multiple `attach-post-create` networks; implementation must verify commands against the installed version and retain a post-deploy Docker network connect fallback.
- Docker labels added through docker options require rebuild/redeploy to affect replacement containers.
- Existing Traefik entrypoint, middleware, and resolver names are installation-specific, which is why they must be configurable.
- External Traefik may constrain routing to a specific Docker network; the generated `traefik.docker.network` label must match the selected network exactly.
- Matrix deployments may use Compose-generated network names. Discovery must return the actual Docker network name, not only the Compose logical name.

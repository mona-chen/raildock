# Agent Guide for RailDock

This file contains conventions and operational details for agents working on RailDock.

## Project layout

- `app/` — React 19 + Vite frontend (TypeScript, Tailwind, shadcn/ui)
- `backend/` — Rails 8 API (Ruby 3.4+)
- `docker/` — nginx, supervisor, and entrypoint for the single production image
- `scripts/` — Operational helpers (`backup.sh`, `restore.sh`, `setup-dev.sh`, etc.)
- `dokku/` — Dokku source as a gitignored reference checkout (not actively modified)

## Build & run

### Local development

```bash
make setup-dev   # First time: .env, local base image, dev image, credentials
make start       # Dev stack with live reload (Vite on :5173, Rails on :3001)
make test        # Frontend tests (in the frontend container)
make test-backend  # Backend RSpec (in the backend container)
make start-sim     # Dev stack + the Dokku simulator (macOS preview)
make seed-demo     # Demo organization, projects, services and history
```

Dev runs from `docker-compose.dev.yml` (standalone, not layered on
`docker-compose.yml`): the `backend` service builds `Dockerfile.dev` on top of a
locally-built production image and mounts `./backend` at `/rails`; the
`frontend` service runs Vite with HMR and mounts `./app` at `/app`.
`scripts/dev-entrypoint.sh` seeds the bundle volume, installs dev/test gems,
runs `db:prepare`, then starts Puma with the Solid Queue supervisor in-process
(`SOLID_QUEUE_IN_PUMA`).

### Previewing without a Linux host

Dokku is Linux-only, so a Mac cannot host a real one. `make start-sim` layers
`docker-compose.dev.dokku.yml` on top of the dev stack and runs the in-repo
simulator (`test/dokku-sim`) as an SSH-reachable server: the `dokku` shim answers
app, datastore, config, domain, proxy, checks and `ps` commands, and raw `docker`
commands are forwarded to the host daemon (the socket is mounted), so container
inventory and host metrics see real containers. The simulator authorizes its key
for both `dokku` and `root`, matching what `install.sh` does on a real host.
`make seed-demo` then creates an admin (`admin@raildock.local` /
`changeme123`), an organization, a server pointed at the simulator, two projects
with apps, a database, a cache, domains, a volume, and deployment/activity/metric
history. `git:sync` prints a build log but builds nothing, so a "deployed"
service is state in the database rather than a running container — use a Linux
host or VM when a real URL is needed.

### Production install

```bash
curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
```

The installer:
1. Checks for Docker on the host; installs it automatically if missing.
2. Checks for Dokku on the host; installs it automatically if missing.
3. Generates an SSH key in `data/dokku-ssh/` and registers it with Dokku.
4. Clones the repo into the install directory.
5. Generates `.env` and `backend/config/master.key`.
6. Creates a fresh `backend/config/credentials.yml.enc` using the pulled Docker image.
7. Pulls `ghcr.io/mona-chen/raildock/raildock:${RAILDOCK_VERSION:-latest}` and starts the stack.
8. Binds the web UI to port `8888` by default so port `80` stays free for Dokku's Traefik.
9. Creates the "Local Dokku" server record automatically via `DOKKU_HOST`.

The installer also provisions Nixpacks and Railpack. Railpack uses a managed,
restartable BuildKit container and configures Dokku's `BUILDKIT_HOST`; deployment
preflight reports a clear error when a selected external builder is unavailable.

Team invitations require outgoing SMTP. Set `SMTP_ADDRESS`, `SMTP_PORT`,
`SMTP_USERNAME`, `SMTP_PASSWORD`, and `MAIL_FROM` in `.env` (or configure SMTP
in `SystemSetting` after install). Until SMTP is configured, invitations are
still created but the UI warns that the invite link must be shared manually.

Use `BUILD_FROM_SOURCE=1` to build the image locally. Use `INSTALL_DOKKU=0` to
skip Dokku installation when managing only remote hosts. Use `SKIP_DOKKU_CHECK=1`
to bypass the Dokku presence check entirely.

To use an existing Traefik instance on the Dokku host instead of Dokku's
managed proxy, install with `PROXY_MODE=external` and set
`EXTERNAL_PROXY_NETWORK` to the existing Traefik Docker network. Optional
entrypoint, certificate resolver, and redirect middleware names can be set via
`EXTERNAL_PROXY_HTTP_ENTRYPOINT`, `EXTERNAL_PROXY_HTTPS_ENTRYPOINT`,
`EXTERNAL_PROXY_CERT_RESOLVER`, and `EXTERNAL_PROXY_REDIRECT_MIDDLEWARE`.
External mode stops Dokku's managed Traefik and sets the global proxy to
`none` so it does not conflict with the external Traefik. RailDock applies
process-scoped Docker labels directly through Dokku's `docker-options` plugin.
A service is reached by either a `loadbalancer.server.port` or a
`loadbalancer.server.url` label, never both — Traefik rejects a service that
defines both and silently drops every router for the app. RailDock strips any
stale backend label before applying the resolved one, so a port label written
before the container was running cannot linger and shadow the url label.
The external Traefik itself is never started, stopped, or reconfigured by RailDock.

When piping the installer through `curl | bash`, either `export` the variables
before the command or pass them as CLI flags. The installer also auto-detects
an existing Coolify or Traefik proxy container and switches to external mode
automatically:

```bash
export PROXY_MODE=external
export EXTERNAL_PROXY_NETWORK=proxy
curl -sSL .../install.sh | bash -s -- /opt/raildock
```

or

```bash
curl -sSL .../install.sh | bash -s -- \
  --proxy-mode external \
  --external-proxy-network proxy \
  --external-proxy-http-entrypoint web \
  --external-proxy-https-entrypoint websecure \
  --external-proxy-cert-resolver letsencrypt \
  /opt/raildock
```

## Remote server setup

Remote hosts are bootstrapped via the script returned by
`GET /api/organizations/:id/server_bootstrap`. Run it as root; it installs
Docker, Dokku, the datastore plugins, and the Nixpacks/Railpack builders,
authorizes the organization's public key for both `root` and `dokku`, and
raises `sshd` connection limits. For fully automated provisioning, add the
organization public key to an admin user's `~/.ssh/authorized_keys` first so
`ProvisionServerJob` can connect and run the bootstrap for you.

## Credentials & secrets

- `backend/config/credentials.yml.enc` is **not committed**. It is generated per install.
- `backend/config/master.key` is **not committed**.
- All production secrets live in `.env`.
- The Docker entrypoint creates a fresh `credentials.yml.enc` if it is missing.

When changing code that touches Rails credentials, ensure fresh installs still work without a pre-existing `credentials.yml.enc`.

## Backups

- Service backup artifacts are stored under `${BACKUPS_DIR:-./data/backups}` and mounted at `/rails/storage/backups` in production.
- `RunDueBackupsJob` scans due schedules every minute through Solid Queue recurring tasks. A
  schedule can be paused (`enabled = false`) without losing its next-run bookkeeping; the job uses
  the `BackupSchedule.due` scope so paused schedules are skipped. Retention defaults follow the
  cadence (daily 7, weekly 4, monthly 6) and the cap is 90.
- `PATCH /api/services/:id/backup_schedules/:schedule_id` edits frequency, retention, `enabled` and
  destinations. Destination ids are only rewritten when the request includes the key, so toggling a
  schedule can never silently drop its destinations.
- A backup is only marked completed after its artifact is persisted and SHA-256 verified.
- A backup is only marked completed once at least one copy exists. Remote copies are verified with `head_object` (size match) right after upload; request a destination that cannot be written and the run fails loudly instead of reporting success.
- `BackupDestination.reachable_from(server)` resolves both the server's own destinations and its organization's, so a destination selectable in the UI is always writable by scheduled backups.
- Where a backup goes by default is a service choice that falls back to an organization default: `services.default_backup_destination_ids` → `organizations.default_backup_destination_ids` → local only. The service column must stay **nullable** — `nil` means "inherit" and `[]` means a deliberate local-only choice, so a `[]` default would make inheritance unrepresentable. `PATCH /api/services/:id/recovery/preferences` is where the destination picker persists itself, `GET /api/services/:id/recovery` returns the resolved list so the picker never renders "Local only" first, and `BackupDestination#forget_from_backup_defaults` prunes a deleted destination out of both defaults.
- `VerifyBackupDestinationsJob` re-proves every destination older than `MAX_AGE` (7 days) every 6 hours via `config/recurring.yml`. Verification writes, `head_object`-checks, then deletes a probe object, so a rotated key or tightened bucket policy is caught on a schedule instead of at restore time. `DataSafetyReport` reads the same `status`/`last_verified_at`/`last_error` fields.
- `Backup` rows outlive their `Service` (`dependent: :nullify`, nullable `service_id`) and carry `service_name`/`project_name` in `metadata`, so a destroyed service can still be restored from its last artifact.
- S3-compatible and Cloudflare R2 destinations encrypt artifacts with AES-256-GCM before multipart upload; save the one-time recovery key off-host. `BackupDestinationClient` retries transient S3 errors with backoff, supports custom endpoints with path-style addressing (MinIO/R2), and does not retry bad credentials.
- `aws-sdk-s3` (1.206+) removed `FileUploader`'s `thread_count` and injection of the multipart executor became the caller's job. `BackupDestinationClient#upload` passes an `executor:` built for one upload and shuts it down afterwards — without it the multipart path raises on the first part, and passing `thread_count` leaks into `put_object` ("unexpected value at params[:thread_count]") for anything below the multipart threshold. Do not swap it for a process-wide memoized pool: Puma can be started with `WEB_CONCURRENCY`, and a thread pool does not survive a fork.
- Keep the backup directory on durable storage and include it in host-level disaster recovery.
- Docker named volumes and host-path mounts support snapshots, destructive verified restores, and isolated restore drills.
- PostgreSQL PITR uses daily physical base backups plus continuous WAL archiving. `RunPostgresPitrJob` uploads WAL every minute and applies the configured retention window. `PostgresBaseBackupJob` runs `pg_basebackup -D - -Ft -z -X fetch`: tar output on stdout cannot stream WAL, and `-X stream` is the default, so it has to be turned off explicitly.
- `RunRecoveryDrillsJob` restores the latest artifacts into disposable databases/volumes each week and always removes the isolated resource afterward.
- Surfaces: Settings → Backups (organization destinations) and `GET /api/admin/data-safety` (`DataSafetyReport`) list datastores without a verified destination, volumes without snapshots, destinations that stopped verifying, backups that only exist on this host, and PITR configs whose WAL archiving stalled or errored.

## Environments

Each project owns environments; `production` is created with the project, is marked `is_default`,
and cannot be deleted. This mirrors Railway, Coolify and Dokploy — see
`docs/reviews/2026-09-18-003-environments-and-backup-schedules.md` for the comparison.

- `Service belongs_to :environment` and is assigned to the project's default environment on create.
  The canvas filters the already-loaded service list by the active environment (`?env=<id>`), and
  `AddServiceModal` passes the active `environment_id` so a service is never created in the wrong
  environment by accident.
- Creating a service while viewing `staging` creates it in `staging`. Never drop `environment_id`
  from `ServicesController#service_params`.
- `Environment#before_destroy` refuses the default environment and refuses any environment that
  still owns services (matching Dokploy's `deleteEnvironment`). Do not weaken either guard: a
  switcher must never be able to orphan a running app.
- Deleting an environment is refused with `422 environment_guarded`, not a silent success.
- `projects.environment` is a **display label** kept in sync with the default environment's name so
  the projects list keeps working. Rename the environment through `Api::EnvironmentsController`,
  which syncs the label — do not treat the column as the source of truth.
- `Project#as_json` serializes `environments` (id, name, slug, is_default, service_count). Without
  it the environment switcher renders empty even though the settings pane is populated.
- **Duplication is staged, never live.** `EnvironmentDuplicator` copies every service and its
  configuration into a new environment, but every copy starts `stopped` with no deployment and
  nothing is created on the Dokku host. Railway stages a duplicate for review before it can reach
  anyone; keep it that way. `EnvironmentSync` adds and updates, never deletes — services that exist
  only in the target are reported (`plan.removed`) so they can be removed through the guarded
  destroy endpoint instead of a sync silently deleting a database. Do not add a delete path to
  `EnvironmentSync`.
- **A copy must never inherit an instance identity.** `ServiceCopier` (used by both the duplicator
  and the sync) builds from `ServiceBlueprint`, which deliberately excludes `dokku_app_name`,
  `webhook_token`, `status`, `last_deployed`, canvas coordinates, backups, deployments, PITR and
  process types. `Service#generate_dokku_app_name` only fills a *nil* attribute, so a `dup` would
  carry the original app name and collide on the host. A copied Docker volume likewise gets a fresh
  name (`StorageMount.volume_name_for`) — sharing one would let two services write the same data.
- **`ServiceBlueprint#differences_from` is directional on purpose.** It reports what the target is
  missing or has drifted on, so a staging-only variable or an extra build setting is not "drift".
  Sync merges `config`/`config_overrides`/`external_networks` instead of replacing them, and never
  removes a variable, mount, schedule or link. Diff labels name fields, never values, because
  environment variable values are secrets and those labels are rendered in the UI.
- Duplication does not copy domains: two Dokku apps cannot serve one hostname. A copy of a publicly
  reachable service gets its own temporary domain, and skipped custom domains are reported back in
  `summary[:warnings]`.
- Not implemented yet: PR environments and environment-scoped variables (`shared_vars` remain
  project-level).

## Destructive operations

Anything that deletes production data has to be explicit and recoverable. Keep these invariants when adding or changing endpoints:

- **Manifest applies never delete by default.** Services missing from a manifest are kept and reported (`skipped_removals`); destroying them requires `allow_removals: true` plus a `RemovalConfirmation` token bound to the project, manifest revision, and the exact service list.
- **Removals run only after every earlier phase succeeded.** A failed create/link/deploy must never cascade into a deletion (`blocked_removals`).
- **Repository imports keep unrelated services.** `RepositoryImportsController#apply` passes `allow_removals: false` unless the user confirmed the exact removal list for the reviewed commit.
- **A repository import never replaces the project's manifest with one that drops services.** `adopt_manifest!` stores the imported manifest only when it still describes every service the project owns, or when the user confirmed the removals. Otherwise the existing `manifest_content` is kept, `manifest_drift_detected` is set, and an `ActivityEvent` names the services that were kept — the response reports `manifest_adopted: false`. `ManifestApplyJob` likewise clears the drift flag only when the applied content matches the stored manifest and no removals were withheld.
- **Data-bearing services are snapshotted before destruction.** `DestructionSnapshot` exports every datastore and persistent volume to a *verified* destination first and refuses the destroy when that is impossible; `force_destroy_data: true` is the only way past it and is logged as an `ActivityEvent` warning.
- **Destructive endpoints require a typed name.** `DELETE /api/services/:id` needs `confirm=<service name>`; `DELETE /api/projects/:id` needs `confirmation=<project name>`; deleting the last backup needs `force=true`. All reply `428 precondition_required` with a `code` (`confirmation_required`, `snapshot_required`, `last_backup`, `removals_required`) and an impact summary instead of acting.
- **`Project` destruction is opt-in.** `destroy_services_dokku` runs `prepend: true` before the association cascade and raises unless `allow_resource_destruction` is set, so a bare `project.destroy!` cannot wipe apps and datastores. Use `Project#destroy_with_resources!(confirmed: true)`, and if Dokku refuses, nothing is deleted so the operation can be retried.
- **Restores are destructive too.** `POST /api/services/:id/backups/:backup_id/restore` requires `confirm=<service name>` and takes a `DestructionSnapshot` with `trigger: "pre_restore"` of the *current* data before importing, so the restore itself is reversible. It replies `428 snapshot_required` when no safety snapshot can be taken; `force_destroy_data: true` is the only way past that.
- **Backup destinations are never removed as a side effect.** `Server`/`Organization` declare `has_many :backup_destinations, dependent: :restrict_with_error`, and `BackupDestination` restricts its `backups`/`backup_copies`/`postgres_pitr_configs`. A destination owns off-host artifacts that outlive both the server and RailDock, so delete the destination deliberately (it must be empty) before deleting its owner.
- **Retention can never empty a service.** `BackupRetention` keeps the newest artifact of every `backup_kind`, never expires `pre_destroy`/`pre_restore` safety nets, clamps `keep` to a minimum of 1, and logs rather than raising when `Backup#remove_file!` refuses the last copy. `BackupSchedule#enforce_retention!` scopes expiration to its own `backup_kind` **and** its own `metadata["schedule_id"]` — a short volume window must never delete database artifacts.
- **PITR retention keeps the newest base backup and WAL segment** even when the whole window has aged past `retention_days`, so a stalled archive cannot leave the datastore with zero recovery points.
- **`uninstall.sh` dumps the RailDock database before removing volumes.** The Postgres volume holds the per-destination recovery keys, which are the only way to decrypt artifacts already in object storage; `preserve_state()` writes a `pg_dump` next to the install directory and refuses to delete the volumes when that fails unless the operator explicitly confirms (`--force` does, by design, skip that prompt).

## CI / release

- `.github/workflows/ci.yml` — lint, test, security audits (Brakeman, bundler-audit, npm audit).
- `.github/workflows/release-main.yml` — builds and pushes `edge` image on every push to `main`.
- `.github/workflows/build.yml` — builds and pushes image on git tags.
- `.github/workflows/release.yml` — creates GitHub release on git tags.
- `.github/workflows/deploy.yml` — manual deploy to a server via SSH with rollback.

## Working with Dokku

Dokku is the deployment engine; RailDock is a multi-host control plane that
drives it over SSH. **Prefer Dokku's own declarative mechanisms over
reimplementing them in Rails.** The exceptions below are deliberate and were
verified against Dokku v0.38.1 — `dokku/` is a gitignored reference checkout
(`git clone https://github.com/dokku/dokku.git dokku`); read it and check the
version the target servers run before assuming a behavior.

- **Managed proxy mode: let Dokku own routing.** Use its native commands
  (`proxy:set`, `ports:set`, `domains:add`, `traefik:labels:*`) instead of
  writing labels by hand.
- **External proxy mode: RailDock owns the routing labels.**
  `ExternalProxyConfigurator` writes process-scoped `docker-options` labels
  because Dokku's `traefik-vhosts` plugin only ever runs *its own* Traefik
  container (`network_mode: bridge`, hardcoded `80:80`/`443:443`) and has no
  supported way to front an external Traefik. Its label hook also fails closed:
  disabling the per-app proxy means the custom labels file is never read, while
  enabling it injects Dokku's own routers (with a `leresolver` that does not
  exist on the external proxy). Do not try to reconfigure the plugin to reach
  someone else's Traefik.
- **Deploy scripts live in Dokku's `app.json` for git deploys.** Dokku runs
  `scripts.dokku.predeploy` during the release phase (before traffic) and
  `scripts.dokku.postdeploy` after deploy; both fire under `git:sync` +
  `ps:rebuild`, which is the path RailDock uses. Persisted scripts therefore
  carry their provenance (`source` = `repository`/`manifest`, plus `format`),
  and `DeploymentJob#run_deploy_scripts` skips any phase Dokku will run itself
  so a repository `app.json` is never executed twice. RailDock runs a script
  itself only for manifests that are not in the deployed repo: UI/DB/template
  manifests, `git:from-image` deploys, and subdirectory deploys. Keep it that
  way.
- **Static sites are built by a static-capable builder and served by Caddy.**
  A service with `config["staticSite"]["publishDirectory"]` (manifest
  `publish_directory`) is a static bundle. `StaticSiteConfigurator` forces
  railpack (else nixpacks), merges `RAILPACK_SPA_OUTPUT_DIR` /
  `RAILPACK_NODE_VERSION` or `NIXPACKS_SPA_OUT_DIR` / `NIXPACKS_NODE_VERSION`
  into the build env, and writes the Caddy command to
  `ps:set <app> dockerfile-start-cmd`. The command has to be supplied because
  Dokku's railpack and nixpacks build stages set `ENTRYPOINT`, which clears the
  image `CMD` railpack put the serve command in, and nixpacks otherwise defaults
  to the removed Node 18. An explicit `start_command` or a `dockerfile` builder
  passes through untouched. `StaticSiteDetector` records this automatically when
  importing a recognized Vite/CRA/Angular/Astro/Gatsby/Next-export repo.
- **Reconcile, do not track.** Apply the desired state and diff it against what
  is actually on the host (`docker-options:report`, `ports:report`), removing
  anything stale. Never rely only on the labels RailDock *thinks* it wrote —
  `_externalProxyLabels` missed a stale `loadbalancer.server.port` and left
  Traefik rejecting every router for the app. Check `docker_option_add`/`remove`
  results instead of ignoring them. A Traefik service takes a
  `loadbalancer.server.port` or a `loadbalancer.server.url`, never both.
  `ProxyDriftCheckJob` re-checks running containers every 6 hours and raises a
  warning `ActivityEvent` when routing is actually broken (a service defining
  both backend labels, routers with no backend, or a missing host rule) — not
  for a benign pending change such as a container still on the `port` label
  that the next deploy turns into `url`.
- **Drift merge is review-first and never destructive.** `ManifestDrift`
  (surfaced at `GET /api/projects/:id/manifest/drift` and
  `POST /api/projects/:id/manifest/merge`) reports how the stored manifest
  differs from live services and proposes a manifest that folds accepted live
  values back in. It never persists anything: the proposed content goes back
  into the editor and is saved through the normal `PATCH /manifest` path, so
  validation and the removal-confirmation flow still run. A service the
  manifest declares but that no longer exists is never merged away, and
  services the manifest does not own (`managed_by: ui`) are never adopted.
  Only native `raildock.toml`/`raildock.json` can be regenerated; compatibility
  formats (railway.toml, railway.json, app.json) report `supported: false`.
- **A static frontend is a builder decision, not a Procfile.** Dokku's railpack
  and nixpacks builder stages set `ENTRYPOINT []`, which clears the image `CMD`
  that carries the builder's start command, so a static site has no process for
  the docker-local scheduler to run and the deploy dies with
  `Error response from daemon: no command specified`. `StaticSiteConfigurator`
  owns that decision: an explicit `config["staticSite"]` wins, `StaticSiteProbe`
  fills in the publish directory from the repo at the deployed revision when the
  service declares none, and a deploy that still reaches an image with no
  command reads the Caddy serve command back out of the built image, saves the
  publish directory, and retries once (the rebuild is cached). A repo
  `Dockerfile` or `Procfile` always passes through untouched — it declares its
  own process — and a herokuish app with no `start` script (`Missing script:
  "start"`) is sent to the same static-site settings.
- **`restart_policy` is stored hyphenated.** Rails' enum reader returns the
  label (`on_failure`) while the database, manifests and the JSON API use the
  stored value (`on-failure`). Use `Service#restart_policy_value` (as `as_json`
  and `ManifestReconciler#build_actual_state` do) rather than the bare reader
  whenever a value is compared against or written to a manifest.

## Making changes

- Keep changes minimal and focused.
- Follow existing Rails/React style.
- Frontend ids are strings. Rails serializes integer ids, so any resource the UI compares ids for needs a normalizer in `app/src/lib/apiTransforms.ts`. A raw numeric id never equals a stored or typed string id — that silently broke `environmentId` on the canvas and `BackupDestination#id` in the default-destination picker (the star and the checkboxes read as "off" no matter what was saved).
- Run tests before committing.
- Update this file if you change install, release, backup, or credentials flow.
- Do not commit `.env`, `master.key`, or `credentials.yml.enc`.

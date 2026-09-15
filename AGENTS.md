# Agent Guide for RailDock

This file contains conventions and operational details for agents working on RailDock.

## Project layout

- `app/` — React 19 + Vite frontend (TypeScript, Tailwind, shadcn/ui)
- `backend/` — Rails 8 API (Ruby 3.4+)
- `docker/` — nginx, supervisor, and entrypoint for the single production image
- `scripts/` — Operational helpers (`backup.sh`, `restore.sh`, `setup-dev.sh`, etc.)
- `dokku/` — Dokku source as a submodule/reference (not actively modified)

## Build & run

### Local development

```bash
make setup-dev   # First time: .env, local base image, dev image, credentials
make start       # Dev stack with live reload (Vite on :5173, Rails on :3001)
make test        # Frontend tests (in the frontend container)
make test-backend  # Backend RSpec (in the backend container)
```

Dev runs from `docker-compose.dev.yml` (standalone, not layered on
`docker-compose.yml`): the `backend` service builds `Dockerfile.dev` on top of a
locally-built production image and mounts `./backend` at `/rails`; the
`frontend` service runs Vite with HMR and mounts `./app` at `/app`.
`scripts/dev-entrypoint.sh` seeds the bundle volume, installs dev/test gems,
runs `db:prepare`, then starts Puma with the Solid Queue supervisor in-process
(`SOLID_QUEUE_IN_PUMA`).

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
- `RunDueBackupsJob` scans due schedules every minute through Solid Queue recurring tasks.
- A backup is only marked completed after its artifact is persisted and SHA-256 verified.
- A backup is only marked completed once at least one copy exists. Remote copies are verified with `head_object` (size match) right after upload; request a destination that cannot be written and the run fails loudly instead of reporting success.
- `BackupDestination.reachable_from(server)` resolves both the server's own destinations and its organization's, so a destination selectable in the UI is always writable by scheduled backups.
- `VerifyBackupDestinationsJob` re-proves every destination older than `MAX_AGE` (7 days) every 6 hours via `config/recurring.yml`. Verification writes, `head_object`-checks, then deletes a probe object, so a rotated key or tightened bucket policy is caught on a schedule instead of at restore time. `DataSafetyReport` reads the same `status`/`last_verified_at`/`last_error` fields.
- `Backup` rows outlive their `Service` (`dependent: :nullify`, nullable `service_id`) and carry `service_name`/`project_name` in `metadata`, so a destroyed service can still be restored from its last artifact.
- S3-compatible and Cloudflare R2 destinations encrypt artifacts with AES-256-GCM before multipart upload; save the one-time recovery key off-host. `BackupDestinationClient` retries transient S3 errors with backoff, supports custom endpoints with path-style addressing (MinIO/R2), and does not retry bad credentials.
- Keep the backup directory on durable storage and include it in host-level disaster recovery.
- Docker named volumes and host-path mounts support snapshots, destructive verified restores, and isolated restore drills.
- PostgreSQL PITR uses daily physical base backups plus continuous WAL archiving. `RunPostgresPitrJob` uploads WAL every minute and applies the configured retention window.
- `RunRecoveryDrillsJob` restores the latest artifacts into disposable databases/volumes each week and always removes the isolated resource afterward.
- Surfaces: Settings → Backups (organization destinations) and `GET /api/admin/data-safety` (`DataSafetyReport`) list datastores without a verified destination, volumes without snapshots, destinations that stopped verifying, backups that only exist on this host, and PITR configs whose WAL archiving stalled or errored.

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

## Making changes

- Keep changes minimal and focused.
- Follow existing Rails/React style.
- Run tests before committing.
- Update this file if you change install, release, backup, or credentials flow.
- Do not commit `.env`, `master.key`, or `credentials.yml.enc`.

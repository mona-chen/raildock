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
make setup-dev   # First time
make start       # Dev stack with live reload
make test        # Frontend tests
cd backend && bundle exec rspec
```

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
- Keep the backup directory on durable storage and include it in host-level disaster recovery.
- S3-compatible and Cloudflare R2 destinations encrypt artifacts with AES-256-GCM before multipart upload; save the one-time recovery key off-host.
- Docker named volumes and host-path mounts support snapshots, destructive verified restores, and isolated restore drills.
- PostgreSQL PITR uses daily physical base backups plus continuous WAL archiving. `RunPostgresPitrJob` uploads WAL every minute and applies the configured retention window.
- `RunRecoveryDrillsJob` restores the latest artifacts into disposable databases/volumes each week and always removes the isolated resource afterward.

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

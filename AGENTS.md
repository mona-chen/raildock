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

Use `BUILD_FROM_SOURCE=1` or `INSTALL_DOKKU=0` (to skip Dokku install) as needed.

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

## Credentials & secrets

- `backend/config/credentials.yml.enc` is **not committed**. It is generated per install.
- `backend/config/master.key` is **not committed**.
- All production secrets live in `.env`.
- The Docker entrypoint creates a fresh `credentials.yml.enc` if it is missing.

When changing code that touches Rails credentials, ensure fresh installs still work without a pre-existing `credentials.yml.enc`.

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

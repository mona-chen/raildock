# RailDock

> A self-hosted PaaS for deploying apps and databases to your own servers.

<p align="center">
  <video controls src="./media/dashboard-demo.mp4" width="800">
    <a href="./media/dashboard-demo.mp4">Download demo video</a>
  </video>
</p>

[![Stack](https://img.shields.io/badge/React_19-20232A?logo=react)](https://react.dev)
[![Stack](https://img.shields.io/badge/Rails_8-CC0000?logo=ruby-on-rails)](https://rubyonrails.org)
[![Stack](https://img.shields.io/badge/Dokku-0.38.1-5c9e6b?logo=docker)](https://dokku.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## What this is

RailDock is a self-hosted PaaS. You deploy and manage apps, databases, and servers from a web UI and API on hardware you own — with declarative manifests, dependency-aware deploys, per-project network isolation, teams, backups, and recovery. No managed provider, no Kubernetes.

It is **not** a thin wrapper around another tool. RailDock is a platform in its own right:

| RailDock gives you... |
|---|
| A web UI + API for the whole lifecycle: servers, apps, databases, teams, backups |
| Declarative manifests (`raildock.toml`, `railway.toml`, `app.json`) with topological dependency ordering and cross-service variable references |
| A reconciliation engine that diffs desired state against actual state and applies only what changed |
| A severity-tiered apply pipeline — env var changes are hot-pushed without a deploy, image changes trigger a full rebuild |
| Per-project Docker networks with DNS-based service discovery |
| Teams, roles, invitations, deploy keys, activity events, and one-click templates |
| Scheduled backups, PITR, recovery drills, and encrypted off-site destinations |

Under the hood, deploys are executed by a hardened SSH-driven deployment engine based on Dokku — the battle-tested runtime behind git-push deploys, buildpacks, database plugins, and Let's Encrypt. You interact with RailDock, not the engine:

```
Your browser / API client
        │
        ▼
┌───────────────────┐
│  RailDock          │  The platform
│  ─ Manifest recon  │  Desired-state → actual-state reconciliation
│  ─ Dep ordering    │  Topological sort, failure cascading
│  ─ Secret lifecycle│  Cross-service credential resolution
│  ─ Net isolation   │  Per-project networks + DNS aliases
│  ─ External proxy  │  Existing Traefik integration
└────────┬──────────┘
         │ SSH
         ▼
┌───────────────────┐
│  Deployment engine│  Dokku (apps, databases,
│  (Dokku)          │  buildpacks, plugins, SSL)
└────────┬──────────┘
         │ Docker
         ▼
┌───────────────────┐
│  Server / VPS      │  Your hardware
└───────────────────┘
```

The name "RailDock" is a double pun: it "rails" *on top of* its deployment engine (as in a guardrail), and it is built with Rails.

---

## Features

### Servers

- Add local and remote servers by providing SSH credentials.
- Validate connections, view host metrics, and manage many servers from one place.
- Fully automated remote provisioning: a bootstrap script (returned by the API) installs Docker, the deployment engine, the datastore plugins, and the Nixpacks/Railpack builders on a fresh host — or let `ProvisionServerJob` do it end-to-end.
- Import containers from remote registries as apps.

### Projects

- Group apps and databases into projects with shared project-level environment variables.
- Pan/zoom canvas with draggable service cards and real connection lines.
- Deploy, restart, or stop everything in a project at once.
- Per-project Docker networks with DNS aliases for service discovery.

### Apps

- Create an app from the UI.
- Deploy from a git repo or a Docker image.
- Start, stop, restart, rebuild, scale, and roll back.
- Manage env vars, custom domains, Let's Encrypt SSL, and persistent storage — including an in-UI volume file browser.
- Stream logs and open an interactive terminal over WebSockets.
- App locking to prevent accidental changes, and live container status.

### Databases and services

- Provision PostgreSQL, MySQL, Redis, and MongoDB out of the box.
- Link databases to apps so `DATABASE_URL` is injected automatically; sync credentials when they drift.
- Read-only data browser (tables and rows) straight from the UI.
- Back up and restore databases, with scheduled backups that run automatically.

### Backups and recovery

- Automatic scheduled backups via Solid Queue (checked every minute).
- S3-compatible and Cloudflare R2 backup destinations with AES-256-GCM encryption before multipart upload.
- PostgreSQL PITR: daily physical base backups plus continuous WAL archiving.
- Docker named-volume / host-path snapshots with destructive verified restores.
- Weekly recovery drills that restore the latest artifacts into disposable resources and always clean up.

### Manifests

- Edit `raildock.toml`, `railway.toml`, or `app.json` per project (or import one from a git repository).
- Preview the diff before applying.
- The reconciler figures out what changed and applies only the deltas, ordered by dependency, with failure cascading.

### Integrations and teams

- Git sources via personal access token or GitHub App (including a one-click GitHub App manifest setup).
- Webhooks that trigger deploys on push.
- One-click deploy templates.
- Organizations with roles, SMTP-based invitations, and per-organization deploy keys.
- Activity events for every project and server.
- A plugin registry with install/enable/disable for datastores and builders.

### Operations

- Real server and container metrics with a 30-day history.
- Malware scanning of containers, and SSL certificate status checks.
- Automatic detection of in-app RailDock updates with optional auto-update.

---

## What is missing or half-built

Trying to keep this honest so nobody is surprised.

- **No password reset flow.** If you forget your password, an admin resets it from the Rails console.
- **No preview environments.** On the roadmap, not implemented.
- **No multi-host orchestration for a single project.** You can manage and provision many servers, but each project lives on one server. The deployment engine is single-server by design.
- **The data browser is read-only.** You can browse tables and rows, but not run arbitrary queries or write.
- **No built-in database query console beyond the data browser.** For advanced work you still use `psql`, pgAdmin, or TablePlus.

---

## How it compares

| | RailDock | Coolify | Dokploy | Railway | Dokku (engine) |
|---|---|---|---|---|---|
| Engine | Dokku | Docker/Traefik | Docker/Traefik | Proprietary | — |
| Hosting | Your server | Your server | Your server | Managed | Your server |
| Deploy model | Declarative + imperative | Imperative UI | Imperative UI | Imperative UI | CLI only |
| Manifest reconciliation | Full diff/apply (3 severity tiers) | Limited | Limited | No | `app.json` only |
| Dep-aware deployment orchestration | Yes (topological sort + fail cascade) | No | No | No | Manual |
| Cross-service secret resolution | Yes (`${{ linked.SERVICE.XXX }}`) | Manual | Manual | No | Manual |
| Per-project network isolation | Yes (DNS aliases, auto-inject) | Docker networks | Docker networks | No | No |
| External reverse proxy integration | Yes (auto Traefik labels) | Manual | Manual | No | No |
| Web UI + API | Yes | Yes | Yes | Yes | No |
| Teams, roles, deploy keys | Yes | Partial | Partial | Yes | No |
| Automated server provisioning | Yes (bootstrap script) | Partial | Partial | N/A | No |
| Git-push deploys | Yes | Yes | Yes | Yes | Yes |
| Database plugins | Yes | Yes | Yes | Yes | Yes |
| Real-time logs / terminal | Yes (WebSocket SSH) | Yes | Yes | Yes | CLI |
| Managed multi-server | Manage many, deploy per-project to one | Yes | Yes | Yes | No |
| Preview environments | No | Yes | Yes | Yes | Manual/plugin |

**Use RailDock if:** you want a self-hosted PaaS with declarative infrastructure-as-code on your own VPS without the complexity of Kubernetes. You want to define your stack in a manifest, change env vars without redeploying, have the system resolve database URLs and cross-service credentials automatically, integrate with an existing reverse proxy, and automate the provisioning of new servers — all on hardware you own.

**Do not use RailDock if:** you need one project spanning multiple servers today, you want fully managed hosting, or you prefer imperative click-to-deploy workflows over a reconciliation model.

---

## Architecture

RailDock ships as a single Docker image that runs nginx, Puma, and background workers under supervisor. The Rails backend talks to the deployment engine over SSH. The React frontend talks to Rails over a same-origin `/api` path and WebSocket `/cable`.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────────────────┐
│   React 19  │────▶│  Rails 8    │────▶│     Dokku (SSH or local)    │
│   (Vite)    │◀────│  PostgreSQL │◀────│   postgres/redis/mysql/     │
│             │ WS  │  Solid Q/C  │ SSH │        mongo plugins        │
└─────────────┘     └─────────────┘     └─────────────────────────────┘
       │                  │                       │
       ▼                  ▼                       ▼
  Traefik (80/443)   PostgreSQL         User App Containers
```

Key backend pieces, all real code:

- `DokkuEngine` + `HostEngine` — the SSH-driven deployment engine: a dual connection pool (restricted `dokku` user + `root` user) with thread-local session reuse, automatic retry, and keepalive.
- `ManifestReconciler` — desired-state vs. actual-state diff-and-apply loop in 6 ordered phases, using 3 severity tiers (reload/restart/redeploy) and topological dependency ordering.
- `ManifestParser` / `ManifestGenerator` — two-phase variable resolution (parse-time secrets + runtime infrastructure references) with round-trip export support for `raildock.toml`.
- `DeploymentSequenceJob` — orchestrates multi-service deploys by dependency order, cancelling dependents of failed deployments.
- `DeploymentJob` — full lifecycle with port auto-detection, external proxy label injection, post-deploy credential propagation across linked services, and real-time log streaming.
- `ProjectNetworkManager` — per-project Docker networks with DNS alias-based service discovery and automatic env var injection.
- `ExternalProxyConfigurator` + `TraefikLabelBuilder` — disables the engine's managed proxy and generates Traefik HTTP/HTTPS router labels with configurable entrypoints and cert resolvers.
- `LogsChannel`, `DeploymentsChannel`, `TerminalChannel` — real-time SSH streaming over ActionCable.
- `RunDueBackupsJob`, `RunPostgresPitrJob`, `RunRecoveryDrillsJob` — scheduled backups, WAL archiving, and recovery drills via Solid Queue recurring tasks.

---

## Quick start

### Requirements

- A Linux server. Docker and the deployment engine are installed automatically by the installer if missing.
- Port 8888 available (RailDock defaults here so port 80 stays free for Dokku's Traefik).
- `curl`.

### Install

```bash
curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
```

The installer:

1. Checks for Docker and installs it if missing.
2. Checks for Dokku and installs it if missing.
3. Generates an SSH key in `data/dokku-ssh/` and registers it with Dokku.
4. Clones the repo into the install directory.
5. Generates `.env` and `backend/config/master.key`, and creates a fresh Rails credentials file.
6. Pulls the image and starts the stack on port 8888.
7. Creates the "Local Dokku" server record automatically via `DOKKU_HOST`.

Open `http://<your-server-ip>:8888` and create the first user.

Options:

```bash
# Build the image from source instead of pulling
BUILD_FROM_SOURCE=1 ./install.sh

# Skip installation of the deployment engine (when managing only remote hosts)
INSTALL_DOKKU=0 ./install.sh

# Bypass the engine presence check
SKIP_DOKKU_CHECK=1 ./install.sh

# Reuse an existing Traefik instance (set the network your Traefik is attached to)
PROXY_MODE=external EXTERNAL_PROXY_NETWORK=proxy ./install.sh
```

External proxy mode supports optional `EXTERNAL_PROXY_HTTP_ENTRYPOINT`,
`EXTERNAL_PROXY_HTTPS_ENTRYPOINT`, `EXTERNAL_PROXY_CERT_RESOLVER`, and
`EXTERNAL_PROXY_REDIRECT_MIDDLEWARE`. It stops Dokku's managed Traefik and sets
the global proxy to `none`; RailDock applies process-scoped labels directly
through Dokku's `docker-options` plugin. The installer also auto-detects an
existing Coolify or Traefik proxy container and switches to external mode
automatically.

Team invitations require outgoing SMTP. Set `SMTP_ADDRESS`, `SMTP_PORT`,
`SMTP_USERNAME`, `SMTP_PASSWORD`, and `MAIL_FROM` in `.env` (or configure SMTP
in Settings after install). Until SMTP is configured, invitations are still
created but the UI warns that the invite link must be shared manually.

### Upgrade

```bash
cd /opt/raildock
RAILDOCK_VERSION=latest ./install.sh
```

> [!IMPORTANT]
> Back up `.env` and `backend/config/master.key` after install. Losing them means losing access to encrypted credentials and secrets.

---

## Remote server setup

Remote hosts are bootstrapped via the script returned by
`GET /api/organizations/:id/server_bootstrap`. Run it as root; it installs
Docker, Dokku, the datastore plugins, and the Nixpacks/Railpack builders,
authorizes the organization's public key for both `root` and `dokku`, and
raises `sshd` connection limits. For fully automated provisioning, add the
organization public key to an admin user's `~/.ssh/authorized_keys` first so
`ProvisionServerJob` can connect and run the bootstrap for you.

---

## Development

### Requirements

- Docker (with Docker Compose v2)

### Start the dev stack

The dev stack runs in Docker with the entire project bind-mounted, so both the
Rails API and the Vite frontend hot-reload as you edit code.

```bash
make setup-dev   # one-time: .env, keys, image build, migrations
make start       # full stack with live reload
```

Then open **http://localhost:5173** (Vite) — the API is at
**http://localhost:3001**.

### Useful commands

```bash
make stop           # stop all containers
make logs           # tail all logs
make logs-backend   # tail Rails logs
make logs-frontend  # tail Vite logs
make db             # psql console
make console        # Rails console
make test           # frontend Vitest tests (in the frontend container)
make test-backend   # backend RSpec tests (in the backend container)
```

---

## Backing up RailDock itself

Back up RailDock's own database:

```bash
cd /opt/raildock
./scripts/backup.sh
```

Restore:

```bash
./scripts/restore.sh backups/raildock_production-20260101-120000.sql.gz
```

Service backups are stored under `${BACKUPS_DIR:-./data/backups}` and mounted
at `/rails/storage/backups` in production. A backup is only marked completed
after its artifact is persisted and SHA-256 verified. Keep the directory on
durable storage and include it in host-level disaster recovery.

---

## Security and operations

- Secrets are generated per install and live in `.env` and `backend/config/master.key`. Do not commit them.
- SSH keys for managed servers are stored in `./data/dokku-ssh/`.
- JWT tokens expire after 30 days.
- Auth endpoints are rate-limited.
- Production runs with CSP, CORS restrictions, and other security headers.
- CI runs Brakeman, bundler-audit, and npm audit.
- Set `FORCE_SSL=true` when running behind a TLS-terminating proxy.

---

## Roadmap

This is what I am working toward, roughly in order.

### Now

- [ ] Add password reset.
- [ ] Branch-based preview environments.
- [ ] Multi-host orchestration for a single project (without becoming Kubernetes).

### Next

- [ ] Write-capable database console / query runner.
- [ ] Better resource metrics and alerting hooks.
- [ ] Finer permissions and team audit logs.

### Later

- [ ] CLI companion for terminal-first users.
- [ ] More one-click deploy templates.

---

## Why not just use X?

**Dokku** is the runtime that powers RailDock's deployment engine, but it is a terminal tool at heart. If you are comfortable working from the CLI and never need a UI, manifests, or dependency ordering, plain Dokku is a fine choice. RailDock wraps that proven runtime in a full platform so you get the same reliability without living in a terminal.

**Coolify** is the most complete self-hosted PaaS. Its Docker/Traefik stack is heavier than Dokku's, and its reconciliation model is imperative — it applies what you click, not what you declare. If you want a mature all-in-one platform with built-in multi-server, use Coolify.

**Dokploy** has a polished UI and Docker-native workflows. It is younger and its template library is smaller. It does not have a manifest reconciliation engine or dependency-aware deployment orchestration.

**Railway** has the best deploy experience in the world — if you do not mind managed hosting. RailDock aims for a similar UX, but on your own hardware, with a declarative control plane that Railway does not offer.

RailDock sits in a different gap: a proven deployment engine's reliability + Kubernetes-style reconciliation + Railway-caliber UX, on a server you own.

---

## Contributing

This is a solo project right now, but feedback and focused pull requests are welcome.

1. Open an issue before making large changes.
2. Keep changes minimal and follow the existing style.
3. Make sure tests pass.

```bash
cd app && npm test
cd backend && bundle exec rspec
```

---

## License

MIT License — see [LICENSE](LICENSE)

Copyright (c) 2026 RailDock Contributors

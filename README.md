# RailDock

> A declarative self-hosted PaaS control plane for Dokku.

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

RailDock is a control plane that turns Dokku from a collection of shell commands into a **declarative infrastructure platform with dependency-aware orchestration, config-drift reconciliation, and per-project network isolation** — all accessible through a web UI and API.

It is **not** a "Dokku UI." The engineering model is fundamentally different:

| Dokku is... | RailDock adds... |
|---|---|
| A CLI tool that manages containers, databases, and SSL via plugins | A reconciliation engine that diffs desired state against actual state and applies only what changed |
| Manual `postgres:link`, `config:set`, `ports:set` | Declarative manifests (`raildock.toml`) with topological dependency ordering and cross-service variable references |
| A single bridge network for all apps | Per-project Docker networks with DNS-based service discovery |
| Manual `git:sync` + `ps:rebuild` every time | A severity-tiered apply pipeline — env var changes are hot-pushed without a deploy, image changes trigger a full rebuild |
| sshd directly — one connection per command, rate-limited under load | Thread-local SSH session pooling with automatic retry and keepalive |
| Managed proxy only (nginx or bundled Traefik) | External Traefik mode with auto-generated router labels for existing reverse proxy infrastructure |

RailDock uses Dokku as its **container runtime**, not its management model. The architecture sits above Dokku, not beside it:

```
Your browser / API client
        │
        ▼
┌───────────────────┐
│  RailDock          │  Declarative orchestration layer
│  ─ Manifest recon  │  Desired-state → actual-state reconciliation
│  ─ Dep ordering    │  Topological sort, failure cascading
│  ─ Secret lifecycle│  Cross-service credential resolution
│  ─ Net isolation   │  Per-project networks + DNS aliases
│  ─ External proxy  │  Existing Traefik integration
└────────┬──────────┘
         │ SSH (dokku user + root user)
         ▼
┌───────────────────┐
│  Dokku             │  Container runtime (apps, databases,
│                    │  buildpacks, plugins, SSL)
└────────┬──────────┘
         │ Docker
         ▼
┌───────────────────┐
│  Server / VPS      │  Your hardware
└───────────────────┘
```

Why Dokku? Because Dokku is boring in the best way — git-push deploys, buildpacks, database plugins, Let's Encrypt, and over a decade of stability. What Dokku does not provide is the orchestration layer that makes infrastructure declarative, dependency-aware, and accessible to someone who does not live in a terminal.

The name "RailDock" is a double pun: it "rails" *on top of* Dokku (as in a guardrail), and it is built with Rails.

---

## What actually works today

This is early software. I would not run your payment processor on it yet. But the core loop is real and I use it myself.

**Servers**

- Add a Dokku server by providing SSH credentials.
- RailDock connects over SSH and runs Dokku commands for you.
- Validate the connection, view host metrics, and manage multiple servers from one place.

**Projects**

- Group apps and databases into projects.
- Pan/zoom canvas with draggable service cards and connection lines.
- Shared project-level environment variables.
- Deploy, restart, or stop everything in a project at once.

**Apps**

- Create a Dokku app from the UI.
- Deploy from a git repo (`git:sync`) or a Docker image (`git:from-image`).
- Start, stop, restart, rebuild, scale, and roll back.
- Manage env vars, custom domains, Let's Encrypt SSL, and persistent storage.
- Stream logs in real time over WebSockets.
- Open an interactive terminal session straight into the container.

**Databases and services**

- Provision PostgreSQL, MySQL, Redis, and MongoDB through Dokku plugins.
- Link databases to apps so `DATABASE_URL` is injected automatically.
- Backup and restore databases.

**Manifests**

- Edit a `raildock.toml` or `app.json` manifest per project.
- Preview the diff before applying.
- The reconciler figures out what changed and applies only the deltas.

**Integrations**

- Connect Git sources via personal access token or GitHub App.
- GitHub App webhooks can trigger deploys on push.
- Organizations with basic role-based access control.
- Per-organization deploy keys.

---

## What is missing or half-built

I am trying to keep this honest so nobody is surprised.

- **Backup schedules are stored but not executed automatically.** You can back up a database manually; scheduled backups need a cron hook that is not wired up yet.
- **No built-in database query UI.** You provision and link databases, but you still use pgAdmin, TablePlus, or `dokku postgres:enter` to query them.
- **No password reset flow.** If you forget your password, you reset it from the Rails console for now.
- **No multi-server orchestration.** You can add multiple servers, but each project lives on one server. Dokku is single-server by design.
- **No preview environments.** This is on the roadmap but not implemented.
- **The integrations "modules" list in settings is a stub.** It returns an empty array.

---

## How it compares

| | RailDock | Dokku | Coolify | Dokploy | Railway |
|---|---|---|---|---|---|
| Engine | Dokku | Dokku | Docker/Traefik | Docker/Traefik | Proprietary |
| Hosting | Your server | Your server | Your server | Your server | Managed |
| Deploy model | Declarative + imperative | CLI only | Imperative UI | Imperative UI | Imperative UI |
| Manifest reconciliation | Full diff/apply (3 severity tiers) | `app.json` only | Limited | Limited | No |
| Dep-aware deployment orchestration | Yes (topological sort + fail cascade) | Manual | No | No | No |
| Cross-service secret resolution | Yes (`${{ linked.SERVICE.XXX }}`) | Manual | Manual | Manual | No |
| Per-project network isolation | Yes (DNS aliases, auto-inject) | No | Docker networks | Docker networks | No |
| External reverse proxy integration | Yes (auto Traefik labels) | No | Manual | Manual | No |
| Dual SSH engine (dokku + root) | Yes | N/A | No | No | No |
| Git-push deploys | Yes | Yes | Yes | Yes | Yes |
| Database plugins | Yes | Yes | Yes | Yes | Yes |
| Real-time logs / terminal | Yes (WebSocket SSH) | CLI | Yes | Yes | Yes |
| Multi-server | No | No | Yes | Yes | Yes |
| Preview environments | No | Manual/plugin | Yes | Yes | Yes |

**Use RailDock if:** you want declarative infrastructure-as-code on your own VPS without the complexity of Kubernetes. You want to define your stack in a manifest, change env vars without redeploying, have the system resolve database URLs and cross-service credentials automatically, and integrate with an existing reverse proxy — all on top of Dokku's proven runtime.

**Do not use RailDock if:** you need multi-server orchestration today, you want fully managed hosting, or you prefer imperative click-to-deploy workflows over a reconciliation model.

---

## Architecture

RailDock ships as a single Docker image that runs nginx, Puma, and background workers under supervisor. The Rails backend talks to Dokku over SSH. The React frontend talks to Rails over a same-origin `/api` path and WebSocket `/cable`.

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

- `DokkuEngine` + `HostEngine` — dual SSH connection pool (restricted `dokku` user + `root` user) with thread-local session reuse, automatic retry, and keepalive.
- `ManifestReconciler` — desired-state vs. actual-state diff-and-apply loop in 6 ordered phases, using 3 severity tiers (reload/restart/redeploy) and topological dependency ordering.
- `ManifestParser` / `ManifestGenerator` — two-phase variable resolution (parse-time secrets + runtime infrastructure references) with round-trip export support for `raildock.toml`.
- `DeploymentSequenceJob` — orchestrates multi-service deploys by dependency order, cancelling dependents of failed deployments.
- `DeploymentJob` — full lifecycle with port auto-detection, external proxy label injection, post-deploy credential propagation across linked services, and real-time log streaming.
- `ProjectNetworkManager` — per-project Docker networks with DNS alias-based service discovery and automatic env var injection.
- `ExternalProxyConfigurator` + `TraefikLabelBuilder` — disables Dokku proxy and generates Traefik HTTP/HTTPS router labels with configurable entrypoints and cert resolvers.
- `LogsChannel`, `DeploymentsChannel`, `TerminalChannel` — real-time SSH streaming over ActionCable.

---

## Quick start

### Requirements

- A Linux server with Docker and Docker Compose.
- [Dokku](https://dokku.com/) installed on the same server (or let the installer install it).
- Port 8888 available (RailDock defaults here so port 80 stays free for Dokku's Traefik).
- `curl`.

### Install

```bash
curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
```

The installer:

1. Checks for Dokku on the host (installs it automatically with `INSTALL_DOKKU=1`).
2. Generates an SSH key and registers it with Dokku.
3. Clones the repo, generates secrets, and creates a fresh Rails credentials file.
4. Pulls the image and starts the stack on port 8888.
5. Creates the "Local Dokku" server record automatically.

Open `http://<your-server-ip>:8888` and create the first user.

If Dokku is not installed and you want the installer to set it up:

```bash
INSTALL_DOKKU=1 curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
```

To use a remote Dokku server instead of a local one:

```bash
SKIP_DOKKU_CHECK=1 curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
```

To build from source instead:

```bash
BUILD_FROM_SOURCE=1 ./install.sh
```

### Upgrade

```bash
cd /opt/raildock
RAILDOCK_VERSION=latest ./install.sh
```

> [!IMPORTANT]
> Back up `.env` and `backend/config/master.key` after install. Losing them means losing access to encrypted credentials and secrets.

---

## Development

### Requirements

- Ruby 3.4+
- Node.js 20+
- PostgreSQL 14+
- Docker

### Start the dev stack

```bash
make setup-dev   # env, keys, migrations
make start       # full stack with live reload
```

### Useful commands

```bash
make stop           # stop all containers
make logs           # tail all logs
make logs-backend   # tail Rails logs
make db             # psql console
make console        # Rails console
make test           # frontend Vitest tests
cd backend && bundle exec rspec  # backend tests
```

---

## Roadmap

This is what I am working toward, roughly in order.

### Now

- [ ] Replace the old template-based "Add Service" flow with realistic app/database creation.
- [ ] Finish wiring the service panel tabs so every tab reflects live Dokku state.
- [ ] Draw real connection lines between linked services on the canvas.
- [ ] Add automatic execution of backup schedules.
- [ ] Add password reset.

### Next

- [ ] One-click deploy templates that generate real manifests.
- [ ] Branch-based preview environments.
- [ ] Better resource metrics and alerting hooks.
- [ ] Built-in database query browser.

### Later

- [ ] Multi-server / agent-based remote hosts without turning into Kubernetes.
- [ ] CLI companion for terminal-first users.
- [ ] Team audit logs and finer permissions.

---

## Security and operations

- Secrets are generated per install and live in `.env` and `backend/config/master.key`. Do not commit them.
- SSH keys for Dokku hosts are stored in `./data/dokku-ssh/`.
- JWT tokens expire after 30 days.
- Auth endpoints are rate-limited.
- Production runs with CSP, CORS restrictions, and other security headers.
- CI runs Brakeman, bundler-audit, and npm audit.
- Set `FORCE_SSL=true` when running behind a TLS-terminating proxy.

### Backups

Back up RailDock's own database:

```bash
cd /opt/raildock
./scripts/backup.sh
```

Restore:

```bash
./scripts/restore.sh backups/raildock_production-20260101-120000.sql.gz
```

---

## Why not just use X?

**Dokku alone** is great if you are comfortable in a terminal. RailDock is not competing with it — it layers on top. If you never need a UI, manifest reconciliation, or dependency ordering, stick with Dokku.

**Coolify** is the most complete self-hosted PaaS. Its Docker/Traefik stack is heavier than Dokku, and its reconciliation model is imperative — it applies what you click, not what you declare. If you want a mature all-in-one platform with multi-server support, use Coolify.

**Dokploy** has a polished UI and Docker-native workflows. It is younger and its template library is smaller. It does not have a manifest reconciliation engine or dependency-aware deployment orchestration.

**Railway** has the best deploy experience in the world — if you do not mind managed hosting. RailDock aims for a similar UX, but on your own hardware, with a declarative control plane that Railway does not offer.

RailDock sits in a different gap: Dokku's runtime reliability + Kubernetes-style reconciliation + Railway-caliber UX, on a server you own.

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

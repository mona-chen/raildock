# RailDock

> A web UI for Dokku that tries to feel like Railway.

[![Stack](https://img.shields.io/badge/React_19-20232A?logo=react)](https://react.dev)
[![Stack](https://img.shields.io/badge/Rails_8-CC0000?logo=ruby-on-rails)](https://rubyonrails.org)
[![Stack](https://img.shields.io/badge/Dokku-0.38.1-5c9e6b?logo=docker)](https://dokku.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## What this is

I run most of my side projects and a few production workloads on self-hosted infrastructure. Over the years I have used Coolify, Dokploy, CapRover, and still do for some things. They are good tools. But I kept hitting moments where I needed something slightly custom and ended up reading docs for three hours to figure out how the platform wanted me to do it.

Then I watched my co-founder at Ruut — who had just learned Rails — deploy a full-stack app by himself without asking me a single server question. When I asked how, he said he used Railway. I tried it and the experience was almost annoying in how simple it was. Connect repo, add env vars, deploy. Done.

I wanted that same calm, "it just works" feeling, but on a server I actually own and pay for directly. Dokku already provides the engine: git-push deploys, buildpacks, SSL plugins, database plugins, and over a decade of stability. What Dokku does not provide is the user experience layer that makes it accessible to someone who does not live in a terminal.

So I started building RailDock. It is a web UI and API layer on top of Dokku. The goal is not to replace Dokku or to become the next Coolify. It is to make Dokku feel as approachable as Railway for small teams and solo developers.

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
- **Home and pricing landing pages exist in the repo but are not routed.** The app redirects straight to the dashboard.
- **The integrations "modules" list in settings is a stub.** It returns an empty array.

---

## How it compares

| | RailDock | Dokku | Coolify | Dokploy | Railway |
|---|---|---|---|---|---|
| Engine | Dokku | Dokku | Docker/Traefik | Docker/Traefik | Proprietary |
| Hosting | Your server | Your server | Your server | Your server | Managed |
| Interface | Web UI | CLI only | Web UI | Web UI | Web UI |
| Server overhead | Low | Very low | Medium | Medium | N/A |
| Git-push deploys | Yes | Yes | Yes | Yes | Yes |
| Database plugins | Yes | Yes | Yes | Yes | Yes |
| Manifest reconciliation | Yes | `app.json` only | Limited | Limited | No |
| Real-time logs / terminal | Yes | CLI | Yes | Yes | Yes |
| Multi-server | No | No | Yes | Yes | Yes |
| Preview environments | No | Manual/plugin | Yes | Yes | Yes |

**Use RailDock if:** you like Dokku but want a web UI, or you want Railway-level simplicity on your own VPS.

**Do not use RailDock if:** you need multi-server orchestration today, you never want a UI anyway, or you want fully managed hosting.

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

- `DokkuEngine` — SSH wrapper that translates UI actions into Dokku commands.
- `DeploymentJob` — handles git-sync and image deploys with streamed output.
- `ManifestReconciler` / `ManifestDiff` — preview and apply config changes without blind redeploys.
- `LogsChannel`, `DeploymentsChannel`, `TerminalChannel` — real-time SSH streaming over ActionCable.

---

## Quick start

### Requirements

- A Linux server with Docker and Docker Compose.
- Ports 80 and 443 available.
- `curl`.

### Install

```bash
curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
```

The installer clones the repo, generates secrets, creates a fresh Rails credentials file, pulls the image, and starts the stack. Open `http://<your-server-ip>` and create the first user.

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

**Dokku alone** is great if you are comfortable in a terminal. I am not trying to replace it.

**Coolify** is the most complete self-hosted PaaS I have used. It is also heavier and has a steeper learning curve when you step off the paved path.

**Dokploy** has a clean, modern UI and good Docker-native workflows. It is younger and the template library is smaller.

**Railway** is the best deploy experience I have seen. I want that experience, but on a server I control and pay for directly.

RailDock sits in the gap: Dokku's reliability and simplicity, with a UI that does not require explaining SSH to your teammate.

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

# RailDock

> [!NOTE]
> RailDock is a self-hosted PaaS management UI for Dokku. While it is now packaged for production-style deployments, you should still review the security and backup sections below before running it with sensitive workloads.

A Railway-inspired PaaS management UI for [Dokku](https://dokku.com/). Deploy and manage apps, databases, and services on your own servers through a visual canvas interface.

[![Stack](https://img.shields.io/badge/React_19-20232A?logo=react)](https://react.dev)
[![Stack](https://img.shields.io/badge/Rails_8-CC0000?logo=ruby-on-rails)](https://rubyonrails.org)
[![Stack](https://img.shields.io/badge/Dokku-0.38.1-5c9e6b?logo=docker)](https://dokku.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Project Status](https://img.shields.io/badge/status-experimental-orange)](https://github.com/mona-chen/raildock)

---

## Table of Contents

- [Features](#features)
- [Built With](#built-with)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [API Reference](#api-reference)
- [Environment Variables](#environment-variables)
- [Deployment](#deployment)
- [Development](#development)
- [Testing](#testing)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

---

## Features

### Visual Project Canvas
- **Infinite pan-and-zoom canvas** with draggable service cards
- **SVG connection lines** showing service dependencies and data flow
- **Auto-layout & fit-to-view** for organizing complex architectures
- **Filtering & search** by service type (app, database, cache, queue, search)

### Application Lifecycle
- **Git-backed deploys** via `git:sync` or direct image deploys
- **Process scaling** (web, worker, etc.) with +/- controls
- **Environment variables** synced bidirectionally with Dokku
- **Custom domains** with automatic Let's Encrypt TLS
- **Storage mounts** for persistent volumes
- **One-click rollback** to previous deployments

### Database & Data Services
- **One-click provisioning** of PostgreSQL, MySQL, Redis, and MongoDB
- **Auto-generated connection URLs** with copy-to-clipboard
- **Database backups & restores** with downloadable dumps
- **Backup scheduling** (daily/weekly/monthly) with retention policies
- **Service linking** — connect apps to databases via the canvas

### Observability
- **Real-time log streaming** via WebSocket with search, filtering, and ANSI handling
- **Deployment tracking** with live status and log chunks
- **Container metrics** (CPU, memory) polled from Dokku
- **Activity feed** tracking every deploy, scale, start, and stop event

### Multi-Tenancy & Access
- **Organizations** with role-based access (owner/admin/member)
- **Git source integrations** — GitHub, GitLab, Bitbucket, Gitea
- **GitHub App support** with automatic deploy-on-push via webhooks
- **SSH deploy keys** auto-generated per organization

---

## Built With

| Layer | Technology |
|-------|------------|
| **Frontend** | React 19 + Vite + TypeScript + Tailwind CSS + shadcn/ui + Framer Motion |
| **State** | Zustand (client) + TanStack Query (server) |
| **Real-time** | ActionCable (Solid Cable) |
| **Backend** | Rails 8.1 + PostgreSQL + Solid Queue + Solid Cache |
| **Auth** | JWT (HS256) + Lockbox encryption |
| **SSH** | net-ssh + net-scp |
| **Proxy** | Traefik v3 |
| **Container** | Docker + Docker Compose |
| **PaaS** | Dokku 0.38.1 |

---

## Quick Start

### Prerequisites

- Docker & Docker Compose
- A server with SSH access (for connecting to Dokku hosts)
- curl for the one-line installer

### One-Line Installer

```bash
curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
```

This generates secrets, starts the full Docker Compose stack, and opens RailDock on `http://<your-server-ip>:8090`.

### Manual Setup

```bash
# 1. Clone the repo
git clone https://github.com/mona-chen/raildock.git && cd raildock

# 2. One-command dev setup
make setup-dev

# 3. Open the dashboard
open http://localhost:8090
```

`make setup-dev` generates `.env`, builds images, runs migrations, and auto-configures the local Dokku server.

---

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────────────────┐
│   React 19  │────▶│  Rails 8    │────▶│     Dokku (in container)    │
│   (Vite)    │◀────│  (PostgreSQL│◀────│   postgres/redis/mysql/     │
│             │ WS  │   Solid Q/C)│ SSH │        mongo plugins        │
└─────────────┘     └─────────────┘     └─────────────────────────────┘
       │                  │                       │
       ▼                  ▼                       ▼
  Traefik (80/443)   PostgreSQL         User App Containers
  (reverse proxy)    (primary DB)       (on raildock network)
```

---

## Project Structure

```
raildock/
├── app/                          # React 19 + Vite frontend
│   ├── src/
│   │   ├── pages/               # Route pages (Canvas, ServicePanel, etc.)
│   │   ├── components/          # shadcn/ui + custom components
│   │   ├── hooks/               # TanStack Query hooks
│   │   ├── stores/              # Zustand stores (auth, canvas)
│   │   ├── lib/                 # api.ts, apiTransforms.ts, utils
│   │   └── __tests__/           # Vitest test suite
│   ├── Dockerfile               # Dev image (node:20-alpine)
│   ├── Dockerfile.prod          # Production image (nginx)
│   └── nginx.conf               # SPA fallback routing
│
├── backend/                      # Rails 8 API
│   ├── app/
│   │   ├── controllers/api/     # REST API controllers
│   │   ├── models/              # ActiveRecord models
│   │   ├── services/            # DokkuEngine, GithubAppService, SshKeyService
│   │   ├── jobs/                # DeploymentJob, GithubSyncReposJob
│   │   └── channels/            # ActionCable (DeploymentsChannel, LogsChannel)
│   ├── config/
│   │   ├── routes.rb            # API routes
│   │   ├── recurring.yml        # Solid Queue recurring jobs
│   │   └── initializers/        # CORS, rack-attack, lockbox
│   ├── spec/                    # RSpec test suite
│   ├── Dockerfile               # Production image (ruby:3.4.4-slim + Thruster)
│   └── Dockerfile.dev           # Development image
│
├── scripts/
│   ├── dokku-init.sh            # Dokku container bootstrap
│   └── setup-dev.sh             # One-click local dev environment
│
├── traefik/dynamic/             # Traefik dynamic config
├── docker-compose.yml           # Production stack
├── docker-compose.dev.yml       # Dev overrides
├── install.sh                   # Production one-line installer
└── Makefile                     # Dev commands
```

---

## API Reference

The frontend and backend communicate via a REST API at `/api`. The frontend uses **camelCase**; the backend uses Rails conventions (**snake_case**). A transformation layer handles conversion automatically.

### Key Endpoints

| Resource | Endpoints |
|----------|-----------|
| **Auth** | `POST /api/login`, `GET /api/me`, `POST /api/users` (setup) |
| **Projects** | `GET|POST|PATCH|DELETE /api/projects`, shared vars, activity |
| **Services** | Full CRUD + `deploy`, `start`, `stop`, `restart`, `rebuild`, `scale`, `rollback` |
| **Service Sub-resources** | `env-vars`, `domains`, `storage`, `deployments`, `backups`, `backup_schedules` |
| **Servers** | `GET|POST|DELETE /api/servers`, `POST .../validate` |
| **Organizations** | CRUD, members, git-sources, deploy-keys |
| **GitHub Apps** | `GET /api/github-apps/callback`, `POST /api/github-apps/webhook` |
| **Templates** | `GET /api/templates`, `POST /api/templates/:id/deploy` |

### Real-Time (WebSocket)

| Channel | Path | Purpose |
|---------|------|---------|
| `DeploymentsChannel` | `/cable` | Live deployment status + log chunks |
| `LogsChannel` | `/cable` | Live container log streaming |

### Authentication

RailDock uses **JWT Bearer tokens** (HS256) with:
- **30-day token expiry**
- **Organization scoping** via `X-Organization-ID` header
- **Role-based access** within organizations (owner / admin / member)

---

## Environment Variables

> [!IMPORTANT]
> Generate secure values for secrets. Never commit `.env` files or expose secrets.

### Required for Production

| Variable | Description | Required |
|----------|-------------|----------|
| `RAILS_MASTER_KEY` | Rails credentials encryption key | Yes |
| `JWT_SECRET_KEY` | JWT signing secret (min 64 chars) | Yes |
| `POSTGRES_PASSWORD` | PostgreSQL password | Yes |
| `RAILDOCK_DOMAIN` | Domain for Traefik routing | No |

### Backend (Optional)

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | Auto-configured |
| `FRONTEND_URL` | Allowed CORS origin | `http://localhost:8090` |
| `RAILS_ENV` | Environment | `production` |
| `DOKKU_LIB_HOST_ROOT` | Dokku plugin bind mount path | Docker volume path |
| `DOKKU_HOST_ROOT` | Dokku app home directory | Docker volume path |

### Frontend

| Variable | Description | Default |
|----------|-------------|---------|
| `VITE_API_BASE_URL` | Rails backend URL | Same-origin |

---

## Deployment

### Deploy RailDock (Docker Compose)

The recommended way to run RailDock itself:

```bash
# One-line installer
curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash

# Or install to a specific directory
curl -sSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash -s -- /opt/raildock
```

The installer clones the repo, generates secrets, creates a fresh Rails credentials file, pulls the pre-built GHCR image, and starts the stack on port 80.

**Back up these files after install:**
- `.env`
- `backend/config/master.key`

### Upgrade RailDock

```bash
cd /opt/raildock
./install.sh update
```

### Deploy Your Apps (RailDock manages Dokku)

RailDock is a UI layer on top of Dokku. Once RailDock is running, use the web UI to connect to your Dokku servers and deploy your apps through the visual canvas.

### Building from Source

```bash
BUILD_FROM_SOURCE=1 ./install.sh
```

### Release Process

- Push to `main` → builds and pushes `ghcr.io/mona-chen/raildock/raildock:edge`.
- Push a tag `v*.*.*` → builds image, creates GitHub release, tags `latest`.
- Deploy manually via `.github/workflows/deploy.yml`.

---

## Development

### Prerequisites

- Ruby 3.4+
- Node.js 20+
- PostgreSQL 14+
- Docker

### Start Dev Stack

```bash
make start          # Start full stack with live reload
make setup-dev      # First-time setup (env, keys, migrations)
```

### Common Commands

```bash
make stop           # Stop all containers
make logs           # View all logs
make logs-backend   # View backend logs only
make db             # Open psql console
make console        # Open Rails console
make test           # Frontend Vitest tests
cd backend && bundle exec rspec  # Backend RSpec tests
```

---

## Testing

### Frontend (Vitest)

```bash
cd app && npm test
```

Framework: Vitest + jsdom + React Testing Library

### Backend (RSpec)

```bash
cd backend && bundle exec rspec
```

Framework: RSpec Rails + Factory Bot + Faker + Shoulda Matchers

---

## Security

- **Secrets** are generated per-install and stored in `.env` and `backend/config/master.key`. Never commit these.
- **SSH keys** for connecting to Dokku servers are stored in `./data/dokku-ssh/` (never committed).
- **Sensitive data** is encrypted at rest via the Lockbox gem.
- **JWT tokens** expire after 30 days.
- **Rate limiting** is enabled for auth endpoints (`rack-attack`).
- **CORS** is restricted to the configured `FRONTEND_URL`.
- **Security headers** (CSP, HSTS opt-in, X-Frame-Options, etc.) are applied in production.
- **Brakeman**, **bundler-audit**, and **npm audit** run in CI.
- Set `FORCE_SSL=true` to enforce HTTPS when running behind a TLS-terminating proxy.

## Backups

RailDock uses PostgreSQL for its own data. Back up the RailDock databases regularly:

```bash
# On-demand backup (uses the postgres container)
cd /opt/raildock
docker compose run --rm backup raildock-backup

# Or run the script directly on the host
cd /opt/raildock
./scripts/backup.sh
```

Backups are written to `./backups` by default. Set `BACKUPS_DIR` and `BACKUP_RETENTION_DAYS` to customize.

```bash
# Add to host cron for daily backups
0 3 * * * cd /opt/raildock && ./scripts/backup.sh >> /var/log/raildock-backup.log 2>&1
```

Restore from a backup:

```bash
./scripts/restore.sh backups/raildock_production-20260101-120000.sql.gz
```

---

## Contributing

Contributions are welcome! Please open an issue first to discuss changes.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

Ensure tests pass before submitting:

```bash
cd app && npm test
cd backend && bundle exec rspec
```

---

## License

MIT License - see [LICENSE](LICENSE)

Copyright (c) 2026 RailDock Contributors
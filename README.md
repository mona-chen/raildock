# RailDock

> A Railway-inspired PaaS management UI for [Dokku](https://dokku.com/). Deploy and manage apps, databases, and services on your own servers through a beautiful visual canvas interface.

[![Stack](https://img.shields.io/badge/React_19-20232A?logo=react)](https://react.dev)
[![Stack](https://img.shields.io/badge/Rails_8-CC0000?logo=ruby-on-rails)](https://rubyonrails.org)
[![Stack](https://img.shields.io/badge/Dokku-0.38.1-5c9e6b?logo=docker)](https://dokku.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

RailDock gives you the deployment experience of a modern managed platform — visual architecture diagrams, one-click database provisioning, real-time logs, automatic TLS, and Git-integrated deploys — while keeping you in full control of your own infrastructure via Dokku.

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

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | React 19 + Vite + TypeScript + Tailwind CSS + shadcn/ui | Dashboard UI, canvas, log viewer |
| **State** | Zustand (client) + TanStack Query (server) | Auth, canvas view, API caching |
| **Real-time** | ActionCable (Solid Cable) | Deployment logs, live container logs |
| **Backend** | Rails 8.1 API + PostgreSQL + Solid Queue | REST API, background jobs, ORM |
| **SSH Engine** | net-ssh + DokkuEngine service | Remote Dokku command execution |
| **Proxy** | Traefik v3 | Auto-routing, TLS, load balancing |
| **PaaS** | Dokku 0.38.1 | App builds, container orchestration |
| **Datastores** | Postgres, Redis, MySQL, Mongo plugins | Managed database services |

---

## Quick Start

### Production (One-Line Installer)

```bash
curl -sSL https://raw.githubusercontent.com/yourname/raildock/main/install.sh | bash
```

This generates secrets, starts the full Docker Compose stack, and opens RailDock on your server's IP.

### Development (Docker Compose)

```bash
# 1. Clone the repo
git clone https://github.com/yourname/raildock.git && cd raildock

# 2. One-command dev setup
make setup-dev

# 3. Open the dashboard
open http://localhost:8090
```

`make setup-dev` generates `.env`, builds images, runs migrations, and auto-configures the local Dokku server.

### Manual Development Setup

If you prefer running services directly on your machine:

**Prerequisites:** Ruby 3.4.4, Node.js 20+, PostgreSQL 14+, Docker

```bash
# Backend
cd backend
bin/setup                    # installs gems, creates DB, runs migrations
bin/rails server             # http://localhost:3000

# Frontend (in another terminal)
cd app
npm install
npm run dev                  # http://localhost:5173
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
│   │   ├── lib/
│   │   │   ├── api.ts           # Typed REST client
│   │   │   └── apiTransforms.ts # snake_case ↔ camelCase bridge
│   │   └── __tests__/           # Vitest test suite
│   ├── Dockerfile               # Dev image (node:20-alpine)
│   ├── Dockerfile.prod          # Production image (nginx)
│   └── nginx.conf               # SPA fallback routing
│
├── backend/                      # Rails 8 API
│   ├── app/
│   │   ├── controllers/api/     # REST API controllers
│   │   ├── models/              # Active Record models (19 models)
│   │   ├── services/            # DokkuEngine, GithubAppService, SshKeyService
│   │   ├── jobs/                # DeploymentJob, GithubSyncReposJob
│   │   └── channels/            # ActionCable (DeploymentsChannel, LogsChannel)
│   ├── config/
│   │   ├── routes.rb            # API routes
│   │   ├── recurring.yml        # Solid Queue recurring jobs
│   │   └── initializers/        # CORS, auto-setup Dokku server
│   ├── spec/                    # RSpec test suite (53 files)
│   ├── Dockerfile               # Production image (ruby:3.4.4-slim + Thruster)
│   └── Dockerfile.dev           # Development image
│
├── scripts/
│   ├── dokku-init.sh            # Dokku container bootstrap (plugins, SSH keys)
│   └── setup-dev.sh             # One-click local dev environment
│
├── traefik/dynamic/             # Traefik dynamic config
├── docker-compose.yml           # Production stack
├── docker-compose.dev.yml       # Dev overrides (live reload)
├── install.sh                   # Production one-line installer
├── Makefile                     # Dev commands (start, stop, test, etc.)
└── .env                         # Generated secrets (not committed)
```

---

## API Architecture

The frontend and backend communicate via a typed REST API at `/api`. The frontend uses **camelCase**; the backend uses Rails conventions (**snake_case**). A thin transformation layer (`apiTransforms.ts`) handles conversion automatically.

### Key Endpoints

| Resource | Endpoints |
|----------|-----------|
| **Auth** | `POST /api/login`, `GET /api/me`, `POST /api/users` (setup) |
| **Projects** | `GET|POST|PATCH|DELETE /api/projects`, shared vars, activity |
| **Services** | Full CRUD + `deploy`, `start`, `stop`, `restart`, `rebuild`, `scale`, `rollback` |
| **Service Sub-resources** | `env-vars`, `domains`, `storage`, `deployments`, `backups`, `backup_schedules` |
| **Servers** | `GET|POST|DELETE /api/servers`, `POST .../validate` (SSH + proxy detection) |
| **Organizations** | CRUD, members, git-sources, deploy-keys |
| **GitHub Apps** | `GET /api/github-apps/callback`, `POST /api/github-apps/webhook` |
| **Webhooks** | `POST /api/webhooks/deploy` (generic Git push webhook) |
| **Templates** | `GET /api/templates`, `POST /api/templates/:id/deploy` |

### Real-Time (WebSocket)

| Channel | Path | Purpose |
|---------|------|---------|
| `DeploymentsChannel` | `/cable` | Live deployment status + log chunks |
| `LogsChannel` | `/cable` | Live container log streaming |

---

## Authentication

RailDock uses **JWT Bearer tokens** (HS256). On login, the backend returns a token stored in `localStorage` and sent with every API request via the `Authorization` header.

- **30-day token expiry**
- **Organization scoping** via `X-Organization-ID` header
- **Role-based access** within organizations (owner / admin / member)
- The `AuthGuard` component protects all dashboard routes

### First-Time Setup

On a fresh install, visit `/setup` to create the first admin user. No seed data is required.

---

## Development Commands

```bash
# Start the full dev stack (uses docker-compose.dev.yml)
make start

# One-click dev setup (env, keys, migrations, Dokku config)
make setup-dev

# Stop everything
make stop

# View logs
make logs               # all services
make logs-backend       # Rails only
make logs-frontend      # Vite only

# Database
make db                 # psql console
make console            # Rails console
make reset-db           # wipe and recreate (destructive!)

# Testing
make test               # frontend Vitest tests
cd backend && bundle exec rspec   # backend RSpec tests

# Hot reload fixes
make fix-hmr            # restart frontend container
make restart-backend    # copy backend code + restart
```

---

## Testing

### Frontend (Vitest)

```bash
cd app
npm test        # 29 tests — hooks, components, WebSocket lifecycle
```

- **Framework:** Vitest + jsdom + React Testing Library
- **Coverage:** Hooks (`useProjects`, `useServices`, `useBackupService`, etc.), `ServicePanel`, `AuthPage`, `ServerPage`, WebSocket channels

### Backend (RSpec)

```bash
cd backend
bundle exec rspec    # 375+ examples — models, requests, channels, jobs, services
```

- **Framework:** RSpec Rails + Factory Bot + Faker + Shoulda Matchers
- **Coverage:** 53 spec files covering all models, API controllers, ActionCable channels, background jobs, and the Dokku SSH engine

---

## Deployment

### As a Dokku App (Self-Hosting)

Since RailDock manages Dokku hosts, the most natural deployment is as a Dokku app itself:

```bash
dokku apps:create raildock
dokku postgres:create raildock-db
dokku postgres:link raildock-db raildock
dokku config:set raildock RAILS_MASTER_KEY=$(cat config/master.key)

git push dokku main
```

### With Kamal

The backend includes Kamal configuration for Docker-based deployment anywhere:

```bash
cd backend
kamal setup
```

### Docker Production Build

```bash
# Frontend
docker build -t raildock-frontend -f app/Dockerfile.prod ./app

# Backend
docker build -t raildock-backend ./backend
```

---

## Environment Variables

### Required (`install.sh` generates these automatically)

| Variable | Description |
|----------|-------------|
| `RAILS_MASTER_KEY` | Required for production; encrypts Rails credentials |
| `POSTGRES_PASSWORD` | PostgreSQL superuser password |
| `RAILDOCK_DOMAIN` | Domain for Traefik routing (default: `localhost`) |

### Backend

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `FRONTEND_URL` | Allowed CORS origin(s) |
| `RAILS_ENV` | `production` or `development` |

### Frontend (`app/.env`)

| Variable | Description |
|----------|-------------|
| `VITE_API_BASE_URL` | Rails backend URL (e.g. `http://localhost:3000`). Omit to use same-origin. |

### Dokku Plugin Overrides (advanced)

| Variable | Description |
|----------|-------------|
| `DOKKU_LIB_HOST_ROOT` | Host path for Dokku plugin bind mounts (default: Docker volume path) |
| `DOKKU_HOST_ROOT` | Host path for Dokku app home directory |

---

## Datastore Plugins

RailDock's Dokku container auto-installs and patches the following plugins on first boot:

| Plugin | Service | Image | Notes |
|--------|---------|-------|-------|
| `postgres` | PostgreSQL | `postgres:16-alpine` | Patched from broken `postgres:18.3` |
| `redis` | Redis | Dockerfile default | Config bind-mount compatible |
| `mysql` | MySQL | Dockerfile default | — |
| `mongo` | MongoDB | `mongo:7.0` | Patched from corrupted `mongo:8.2.7` arm64 layer |
| `letsencrypt` | TLS | — | Automatic Let's Encrypt certificates |
| `redirect` | Redirects | — | Domain redirect rules |
| `maintenance` | Maintenance mode | — | Static maintenance pages |

---

## Security

- **SSH keys** are Ed25519, stored in `./data/dokku-ssh/` (never committed)
- **Sensitive data** is encrypted at rest via the `lockbox` gem (SSH keys, Git tokens, deploy key private keys)
- **JWT tokens** expire after 30 days
- **CORS** is restricted to `FRONTEND_URL`
- **Brakeman** and **bundler-audit** run in CI for vulnerability scanning

---

## Contributing

Contributions are welcome! Please open an issue or pull request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please ensure tests pass before submitting:

```bash
cd app && npm test
cd backend && bundle exec rspec
```

---

## License

MIT License

Copyright (c) 2026 RailDock Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

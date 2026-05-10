# RailDock

A Railway-inspired PaaS management UI for [Dokku](https://dokku.com/). Deploy and manage apps, databases, and services on your own servers with a beautiful drag-and-drop canvas interface.

**Stack**: React 19 + Vite frontend · Rails 8 + PostgreSQL backend · Dokku engine

---

## Quick Start (Docker Compose)

The fastest way to get everything running:

```bash
# 1. Clone and enter the project
git clone <repo-url> raildock && cd raildock

# 2. Start the full stack
docker compose up

# 3. In another terminal, create the first admin user
docker compose exec backend bin/rails runner "
  User.create!(name: 'Admin', email: 'admin@raildock.local', password: 'changeme')
"
```

Then open http://localhost:5173 and log in with `admin@raildock.local` / `changeme`.

The Docker Compose stack includes:
- **PostgreSQL** on `:5432`
- **Rails API** on `:3000`
- **Vite dev server** on `:5173` (proxies `/api` to Rails)

---

## Manual Development Setup

If you prefer running services directly on your machine:

### Prerequisites

- Ruby 3.4.4
- Node.js 20+
- PostgreSQL 14+

### Backend

```bash
cd backend
bin/setup                    # installs gems, creates DB, runs migrations
bin/rails server             # runs on http://localhost:3000
```

### Frontend

```bash
cd app
npm install

# Option A: Mock mode (no backend needed)
npm run dev

# Option B: Connected to local backend
VITE_API_BASE_URL=http://localhost:3000 npm run dev
```

In **mock mode**, the app runs with demo data and simulated network delays. This is useful for UI development without a running Rails server.

In **connected mode**, the frontend proxies API requests to the Rails backend and performs real data operations.

---

## Project Structure

```
raildock/
├── app/                     # React 19 + Vite frontend
│   ├── src/
│   │   ├── lib/api.ts       # API client (mock + real)
│   │   ├── lib/apiTransforms.ts  # snake_case ↔ camelCase layer
│   │   ├── stores/          # Zustand state
│   │   ├── hooks/           # TanStack Query hooks
│   │   ├── pages/           # Route pages
│   │   └── features/        # Domain components
│   └── package.json
├── backend/                 # Rails 8 API
│   ├── app/controllers/api/ # REST controllers
│   ├── app/models/          # Active Record models
│   ├── spec/                # RSpec test suite
│   └── Dockerfile.dev
├── docker-compose.yml       # Full-stack orchestration
└── README.md
```

---

## API Architecture

The frontend and backend communicate via a typed REST API. The frontend types use **camelCase**; the backend uses Rails conventions (**snake_case**). A thin transformation layer (`apiTransforms.ts`) handles the conversion automatically.

| Frontend Type | Backend Source | Transform |
|---------------|----------------|-----------|
| `Service.type` | `service_type` column + `type` method | camelize + alias |
| `Service.envVars` | `environment_variables` association | camelize keys |
| `Service.config` | `config` JSONB (nginx, proxy, etc.) | flatten into Service |
| `Server.diskUsage` | `disk_usage` method | camelize |
| `ActivityEvent.timestamp` | `created_at` | alias method |

Request bodies are automatically wrapped for Rails strong params (`{ project: { name: ... } }`) and snakeified on the way out.

---

## Authentication

RailDock uses JWT Bearer tokens. On login, the backend returns a token that is stored in `localStorage` and sent with every API request via the `Authorization` header.

The `AuthGuard` component in the frontend protects dashboard routes and redirects unauthenticated users to `/login`.

---

## Running Tests

### Frontend

```bash
cd app
npm test           # 42 Vitest tests
```

### Backend

```bash
cd backend
bundle exec rspec  # 375+ RSpec examples
```

---

## Deployment

### As a Dokku App (recommended)

Since RailDock manages Dokku hosts, the most natural deployment is as a Dokku app itself:

```bash
dokku apps:create raildock
dokku postgres:create raildock-db
dokku postgres:link raildock-db raildock
dokku config:set raildock RAILS_MASTER_KEY=$(cat config/master.key)

git push dokku main
```

### With Kamal

The backend includes Kamal configuration (`.kamal/`) for Docker-based deployment anywhere:

```bash
cd backend
kamal setup
```

### Docker Production Build

```bash
docker build -t raildock-backend ./backend
docker run -d -p 3000:3000 \
  -e DATABASE_URL=postgres://... \
  -e RAILS_MASTER_KEY=... \
  raildock-backend
```

---

## Environment Variables

### Frontend (`app/.env`)

| Variable | Description |
|----------|-------------|
| `VITE_API_BASE_URL` | Rails backend URL (e.g. `http://localhost:3000`). Omit to run in mock mode. |

### Backend

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `FRONTEND_URL` | Comma-separated list of allowed CORS origins |
| `RAILS_MASTER_KEY` | Required for production; encrypts credentials |

---

## License

MIT

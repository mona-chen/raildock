# RailDock UI Redesign — Dokku-Realistic Deployment Flow

## Research Summary

### Dokku (the engine we actually use)
- **Apps** are created empty: `dokku apps:create <name>`
- **Code arrives via git push** (`git push dokku main`) — not templates
- **Build methods**: Herokuish buildpacks, Cloud Native Buildpacks, Dockerfile
- **Procfile** defines process types (web, worker, release, etc.)
- **Datastores** (postgres, redis, mysql, mongo) are separate plugin-managed services
- **Linking** connects a datastore to an app via env vars (e.g. `DATABASE_URL`)
- No "Rails API template" — you create an app, push your repo, Dokku detects/builds it

### Dokploy / Coolify / Railway (the UX benchmarks)
- **Clear separation**: Applications vs Databases vs Services
- **App creation**: Name → Source (Git repo / Docker image) → Builder → Env vars → Deploy
- **Database creation**: Type → Name → Version → Create (one-click provisioning)
- **Service panel tabs**: Deploy, Logs, Variables, Domains, Storage, Metrics, Settings
- **Real-time deployment logs** streamed during builds
- **Visual links** on canvas between connected resources (app → db)
- **Destroy action** always available in settings

## Current RailDock Problems

1. **"Add Service" shows fake templates** (Rails API, Node.js App, WordPress…) — Dokku has no such templates
2. **No Application vs Database distinction** — everything is a generic "service"
3. **No git source or builder configuration** — the core of Dokku deployment is missing
4. **No destroy/delete action** — services are immortal in the UI
5. **Canvas is decorative** — services float randomly, no connection lines
6. **Deploy button is disconnected from reality** — doesn't show source, branch, or build method

## Redesigned Flow

### Service Types (clearly distinguished)

| Type | Icon | Dokku Command | What it is |
|------|------|---------------|------------|
| **Application** | Code/rocket | `apps:create` + `git:sync` | Code you deploy (git repo or docker image) |
| **Database** | Cylinder | `postgres:create`, `redis:create`... | Plugin-managed datastore |
| **Service** | Box | Docker run or compose | Supporting container (queue, cache, etc.) |

### Create Application Flow

```
[Add Application]
  → Name: "my-api"
  → Source: [Git Repository | Docker Image]
     → Git: Repo URL + Branch + Builder (auto / herokuish / dockerfile)
     → Docker: Image name + Tag
  → [Create]
     → Backend: dokku apps:create my-api
     → dokku git:sync my-api <repo> <branch> (optional)
```

### Create Database Flow

```
[Add Database]
  → Type: [PostgreSQL | MySQL | Redis | MongoDB]
  → Name: "my-api-db"
  → Version: (latest)
  → [Create]
     → Backend: dokku postgres:create my-api-db
```

### Linking (on canvas or in service panel)

```
[my-api] ──link──► [my-api-db]
  → dokku postgres:link my-api-db my-api
  → Sets DATABASE_URL env var on my-api
```

### Service Panel Tabs (right sidebar)

For **Applications**:
- **Overview** — Status, quick actions (Deploy/Start/Stop/Restart), process types, container status
- **Deploy** — Git source, branch, builder, last deployment, deploy history, deploy button
- **Logs** — Real-time application logs
- **Variables** — Environment variables
- **Domains** — Custom domains + SSL
- **Storage** — Persistent volume mounts
- **Metrics** — CPU, memory, network
- **Settings** — General config, destroy

For **Databases**:
- **Overview** — Status, start/stop, connection info
- **Backups** — Backup/restore
- **Logs** — Database logs
- **Variables** — (env vars set on linked apps)
- **Metrics** — Resource usage
- **Settings** — Version, destroy

### Canvas / Project View

- Apps shown as code/rocket icons
- Databases shown as cylinder icons
- **Connection lines** between linked services
- Filter tabs: All | Apps | Databases | Services
- Double-click or click to open service panel

## Implementation Plan

### Phase 1: Fix Add Service Modal (this session)
- Replace template cards with "Add Application" / "Add Database" / "Add Service" choice
- Application form: name, source type (git/docker), repo URL, branch, builder
- Database form: type (postgres/redis/mysql/mongo), name
- Remove fake templates entirely

### Phase 2: Service Panel Redesign
- Reorder tabs: Overview, Deploy, Logs, Variables, Domains, Storage, Metrics, Settings
- Overview tab: status badge, action buttons, process types, quick info
- Deploy tab: source config + deploy button + deployment history
- Settings tab: add Destroy button

### Phase 3: Canvas Improvements
- Different icons for App vs Database vs Service
- Connection lines between linked services
- Filter buttons: All / Apps / Databases / Services

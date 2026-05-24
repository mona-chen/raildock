# Git Deployment: Platform Comparison & RailDock Gap Analysis

> Research conducted 2026-05-24 comparing Railway, Dokploy, Heroku, Coolify, and RailDock.

---

## 1. Git Source & Connectivity

| Feature | Railway | Dokploy | Heroku | Coolify | **RailDock (Current)** |
|---------|---------|---------|--------|---------|------------------------|
| **GitHub App OAuth** | ✅ Full repo browser | ✅ Full repo browser | ✅ Via CLI `heroku create` | ✅ Free: manual URL; Paid: OAuth browser | ✅ App installed, callback handled, repos synced to `GitSource` |
| **GitLab** | ✅ | ✅ Webhook + SSH/HTTPS | ✅ Via buildpacks | ✅ Private Git Source + OAuth | ✅ `GitSource` model supports it; webhook endpoint generic |
| **Bitbucket** | ✅ | ✅ | ✅ | ✅ | ✅ `GitSource` model supports it |
| **Gitea** | ❌ | ✅ | ❌ | ✅ | ✅ `GitSource` model supports it |
| **Private repos** | ✅ OAuth token | ✅ SSH key / PAT | ✅ SSH key | ✅ Deploy key / OAuth | ✅ GitHub App installation token; generic webhook secret |
| **Repo browsing UI** | ✅ Dropdown of repos/branches | ✅ Dropdown of repos/branches | ❌ CLI only | ✅ Dropdown (paid) / manual URL | ⚠️ Backend syncs repos; **frontend UI for browsing not wired up** |
| **Branch selection** | ✅ Per-service branch | ✅ Per-service branch | ✅ `git push heroku branch` | ✅ Per-service branch | ✅ `Service#branch` + `git:set deploy-branch` |
| **Monorepo base dir** | ✅ | ✅ | ❌ | ✅ Base directory path | ❌ **Not supported** |

### RailDock Gap: Repo Browsing UI
The backend has `GithubSyncReposJob` and `GitSource#repos`, but the frontend doesn't expose a repo/branch picker when creating a service. Users must manually paste `git_repo` URLs.

---

## 2. Build System

| Feature | Railway | Dokploy | Heroku | Coolify | **RailDock (Current)** |
|---------|---------|---------|--------|---------|------------------------|
| **Default builder** | Railpack (was Nixpacks) | Nixpacks | Herokuish buildpacks | Nixpacks | Dokku decides: herokuish / pack / dockerfile / nixpacks |
| **Builder selection UI** | ✅ Nixpacks / Dockerfile / Image | ✅ Nixpacks / Buildpacks / Dockerfile / Image | ✅ Buildpack configurable | ✅ Nixpacks / Dockerfile / Static | ✅ `Service#builder` enum stored; **not exposed in deploy flow** |
| **Auto language detect** | ✅ Railpack detects runtime | ✅ Nixpacks detects | ✅ Buildpack detects | ✅ Nixpacks detects | ⚠️ Dokku auto-detects if builder not set; RailDock doesn't surface this |
| **Build config file** | `railway.json` | — | `app.json` | `nixpacks.toml` | `raildock.toml` manifest for templates; **no per-repo build config** |
| **Custom Dockerfile** | ✅ | ✅ | ✅ | ✅ | ✅ Dokku supports Dockerfile builds |
| **Build caching** | ✅ Layer caching (Railpack/BuildKit) | ✅ Docker layer cache | ✅ Build cache dir | ✅ Docker layer cache | ⚠️ Dokku caches; RailDock has **no cache invalidation control** |
| **Build-time secrets** | ✅ BuildKit secrets | ❌ | ❌ | ✅ | ❌ **Not supported** |
| **Multi-stage builds** | ✅ | ✅ | ❌ | ✅ | ✅ Via Dockerfile |
| **Static site builds** | ✅ | ✅ | ❌ | ✅ Nginx static serve | ❌ **Not supported** |

### RailDock Gaps
1. **Builder selection not exposed**: The `builder` column exists on `Service` but the deployment flow doesn't let users pick or override Dokku's auto-detection.
2. **No per-repo build config**: There's no `railway.json` or `nixpacks.toml` equivalent that users can commit to their repo to customize the build.
3. **No build-time secrets**: Env vars are all runtime; BuildKit secrets for private npm registries etc. aren't supported.
4. **No static site builder**: Can't deploy a Jekyll/Hugo/Vite site that just needs `npm run build` + Nginx.

---

## 3. Deployment Trigger

| Feature | Railway | Dokploy | Heroku | Coolify | **RailDock (Current)** |
|---------|---------|---------|--------|---------|------------------------|
| **Manual deploy** | ✅ "Deploy" button | ✅ "Deploy" button | ✅ `git push` | ✅ "Deploy" button | ✅ "Deploy" button + API |
| **Auto-deploy on push** | ✅ GitHub App webhook | ✅ Webhook URL per app | ✅ `git push` is the trigger | ✅ GitHub App / webhook | ✅ Generic webhook + GitHub App push handler |
| **Branch matching** | ✅ | ✅ | ✅ (push any branch) | ✅ | ✅ `service.branch == webhook_branch` |
| **Webhook per app** | ❌ Global project webhook | ✅ Unique URL per app | ❌ | ✅ Unique URL per service | ❌ **Single global webhook endpoint** |
| **Deploy from image** | ✅ Docker Hub / GHCR | ✅ Registry + webhook | ✅ Container Registry | ✅ Registry + webhook | ✅ `docker_image` + `git:from-image` |
| **API trigger** | ✅ Railway CLI + API | ✅ REST API with token | ✅ Heroku CLI + API | ✅ REST API with token | ⚠️ **No deployment API endpoint** |
| **Deploy on config change** | ✅ | ✅ | ✅ Config change = release | ✅ | ❌ **Config changes don't trigger redeploy** |

### RailDock Gaps
1. **No per-app webhook URL**: The single `/api/webhooks/deploy` endpoint requires the global `webhook_secret`. Users can't have separate webhooks per project with separate secrets.
2. **No deployment API**: No public REST API to trigger deployments programmatically from CI.
3. **Config changes don't redeploy**: Changing an env var in the UI doesn't queue a new deployment. Dokku handles this at runtime, but for Dockerfile/Nixpacks builds that bake env vars, a redeploy is needed.
4. **No deploy on branch creation**: Only push events are handled.

---

## 4. Deployment Pipeline

| Feature | Railway | Dokploy | Heroku | Coolify | **RailDock (Current)** |
|---------|---------|---------|--------|---------|------------------------|
| **Release phase** | ❌ | ❌ | ✅ `release` process in Procfile | ❌ | ❌ |
| **Pre-deploy hooks** | ❌ | ❌ | ❌ | ❌ | ❌ Dokku has predeploy/postdeploy via `app.json`; **not exposed** |
| **Zero-downtime deploy** | ✅ Rolling | ✅ Health-check based | ✅ Preboot | ✅ Health-check based | ⚠️ Dokku has zero-downtime; **health checks not configured by default** |
| **Port detection** | ✅ Auto | ✅ Auto | ✅ `$PORT` env var | ✅ Manual / Auto | ✅ `PortDetector` inspects image; works well |
| **Process types / scaling** | ✅ `railway.json` | ✅ Docker Compose | ✅ Procfile | ✅ Docker Compose | ✅ `ProcessType` model + `ps:scale` |
| **Rollback** | ✅ One-click | ✅ One-click | ✅ `heroku releases:rollback` | ✅ One-click + history | ❌ **No rollback UI or API** |
| **Deployment history** | ✅ Full list with diffs | ✅ List with logs | ✅ `heroku releases` | ✅ Full list + rollback | ⚠️ `Deployment` model has status/log; **no diff, no release list UI** |
| **Preview / PR deploys** | ✅ | ✅ (GitHub) | ✅ Review Apps | ❌ | ❌ **Not supported** |

### RailDock Gaps
1. **No rollback**: The `Deployment` model stores logs but there's no way to roll back to a previous deployment. Dokku has `ps:rollback`.
2. **No release phase**: Heroku's `release` Procfile step runs migrations before the new dynos start. RailDock has no equivalent.
3. **No `app.json` support**: Dokku supports `app.json` for predeploy/postdeploy scripts, buildpack config, etc. RailDock doesn't parse or apply it.
4. **No preview deployments**: PR branches can't be auto-deployed to ephemeral URLs.

---

## 5. Logs & Observability

| Feature | Railway | Dokploy | Heroku | Coolify | **RailDock (Current)** |
|---------|---------|---------|--------|---------|------------------------|
| **Real-time build logs** | ✅ Streaming | ✅ Streaming | ✅ `git push` output | ✅ Streaming | ✅ ActionCable `DeploymentsChannel` streaming |
| **Runtime logs** | ✅ | ✅ | ✅ `heroku logs` | ✅ | ⚠️ **Not implemented** — no log tailing UI |
| **Log retention** | ✅ | ✅ | ✅ | ✅ | ❌ **No log storage** |
| **Build artifacts** | ❌ | ❌ | ❌ | ❌ | ❌ |

### RailDock Gaps
1. **No runtime log tailing**: Users can't see `docker logs` output from running containers.
2. **No log retention**: Build logs are stored in `Deployment#deploy_log` but runtime logs aren't captured.

---

## 6. Summary: What RailDock Needs

### Critical (MVP gaps)
| # | Feature | Why It Matters | Effort |
|---|---------|----------------|--------|
| 1 | **Per-app webhook URLs** | Users need unique, securable webhooks per service so CI pipelines can trigger specific deploys | Low |
| 2 | **Deployment trigger API** | CI/CD systems need to trigger deploys via REST API | Low |
| 3 | **Repo/branch picker UI** | The backend already syncs repos; frontend just needs a combobox | Low |
| 4 | **Runtime log tailing** | Essential for debugging — users need to see app logs | Medium |
| 5 | **Rollback button** | Safety net for bad deploys; Dokku already supports `ps:rollback` | Low |

### Important (Competitive parity)
| # | Feature | Why It Matters | Effort |
|---|---------|----------------|--------|
| 6 | **Builder selection UI** | Users need to override Dokku's auto-detection (Dockerfile vs Nixpacks vs herokuish) | Low |
| 7 | **Monorepo base directory** | Many modern repos have frontend/backend in subfolders | Medium |
| 8 | **Static site builder** | Hugo/Jekyll/Vite sites are common; needs build + Nginx serve | Medium |
| 9 | **Build-time secrets** | Private npm registries, API keys needed during build | Medium |
| 10 | **Config change auto-redeploy** | Changing env vars should optionally trigger rebuild for baked vars | Low |
| 11 | **`app.json` / build config support** | Let users commit build config to their repo | Medium |

### Nice to have (Differentiation)
| # | Feature | Why It Matters | Effort |
|---|---------|----------------|--------|
| 12 | **Preview / PR deployments** | Ephemeral deploys for pull requests; huge DX win | High |
| 13 | **Release phase / predeploy hooks** | Run migrations before switching traffic | Medium |
| 14 | **Deploy diff / changelog** | Show what changed between deployments (commits, config) | Medium |
| 15 | **Build caching controls** | Let users clear cache or configure cache keys | Low |

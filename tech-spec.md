# RailDock Declarative Config Architecture Plan

## Executive Summary

RailDock will adopt Dokku's `app.json` as the **foundation** for declarative configuration, then extend it with a `raildock` namespace to cover everything Dokku doesn't natively support (domains, storage, proxy, Traefik labels, resource limits, database provisioning, and inter-service links). This gives us Heroku compatibility *and* full platform coverage.

The system is built around a **reconciliation engine** that reads a manifest, diffs it against current DB + Dokku state, and applies minimal deltas — no blind re-pushes, no unnecessary redeploys.

---

## 1. The Manifest Format

### 1.1 File Discovery

The system looks for config in this priority order:

1. `raildock.json` (RailDock-native, full feature set)
2. `raildock.toml` (TOML variant for developer ergonomics)
3. `app.json` (Dokku/Heroku compatible, limited to Dokku-native features)

Only **one** file is processed per service. If `raildock.json` exists, `app.json` is ignored.

### 1.2 Schema

```json
{
  "buildpacks": [
    { "url": "heroku/ruby" },
    { "url": "heroku/nodejs" }
  ],

  "env": {
    "RAILS_ENV": { "value": "production" },
    "SECRET_KEY_BASE": { "generator": "secret", "description": "Session encryption key" },
    "FEATURE_FLAGS": { "value": "new_ui", "sync": true }
  },

  "cron": [
    { "command": "rake cleanup", "schedule": "0 4 * * *" }
  ],

  "formation": {
    "web": { "quantity": 2, "max_parallel": 1 },
    "worker": { "quantity": 1 }
  },

  "healthchecks": {
    "web": [
      {
        "type": "startup",
        "name": "ready check",
        "path": "/health/ready",
        "attempts": 3,
        "wait": 5
      }
    ]
  },

  "scripts": {
    "dokku": {
      "predeploy": "bundle exec rails assets:precompile",
      "postdeploy": "curl -X POST https://monitoring.internal/deploy"
    },
    "postdeploy": "bundle exec rails db:seed"
  },

  "raildock": {
    "databases": [
      {
        "name": "postgres",
        "type": "postgres",
        "version": "16"
      },
      {
        "name": "redis",
        "type": "redis",
        "version": "7.2"
      }
    ],

    "links": [
      { "from": "postgres", "to": "web", "env_var": "DATABASE_URL" },
      { "from": "redis", "to": "web", "env_var": "REDIS_URL" }
    ],

    "domains": [
      {
        "hostname": "api.myapp.com",
        "port": 80,
        "ssl": true,
        "letsencrypt": true
      }
    ],

    "storage": [
      {
        "host_path": "/var/lib/dokku/data/storage/myapp-uploads",
        "container_path": "/app/public/uploads"
      }
    ],

    "proxy": {
      "enabled": true,
      "proxyType": "traefik",
      "portMappings": [
        { "scheme": "http", "hostPort": 80, "containerPort": 3000 }
      ]
    },

    "traefik": {
      "labels": {
        "traefik.http.routers.myapp.middlewares": "compress",
        "traefik.http.middlewares.compress.compress": "true"
      }
    },

    "dockerOptions": [
      { "phase": "run", "option": "--add-host=host.docker.internal:host-gateway" }
    ],

    "resourceLimits": [
      { "processType": "web", "memory": "512M", "cpu": "1.0" }
    ],

    "checks": {
      "enabled": true,
      "wait": 10,
      "timeout": 60
    },

    "letsencrypt": {
      "enabled": true,
      "email": "admin@myapp.com",
      "autoRenew": true
    },

    "maintenanceMode": false,

    "autoDeploy": true
  }
}
```

### 1.3 Top-Level Keys (Dokku-Native)

These are passed through to Dokku's native `app.json` processor. RailDock does not intercept them — Dokku handles them during build/release.

| Key | Dokku Support | RailDock Role |
|-----|--------------|---------------|
| `buildpacks` | ✅ | Pass-through |
| `env` | ✅ | Pass-through (with `sync` semantics) |
| `cron` | ✅ | Pass-through |
| `formation` | ✅ | Pass-through |
| `healthchecks` | ✅ | Pass-through |
| `scripts` | ✅ | Pass-through |

### 1.4 `raildock` Namespace (RailDock-Extended)

Everything Dokku cannot do natively lives here.

| Key | Purpose | Maps To |
|-----|---------|---------|
| `databases` | Provision plugin datastores | `postgres:create`, `mysql:create`, `redis:create`, `mongo:create` |
| `links` | Connect datastores to apps | `postgres:link`, `redis:link` |
| `domains` | Custom domains + SSL | `domains:add`, `letsencrypt:enable` |
| `storage` | Persistent volume mounts | `storage:mount` |
| `proxy` | Proxy enable/disable, type, ports | `proxy:enable`, `proxy:set`, `ports:add` |
| `traefik` | Custom Traefik labels | `traefik:labels:add` |
| `dockerOptions` | Docker runtime flags | `docker-options:add` |
| `resourceLimits` | Per-process CPU/memory limits | `resource:limit` |
| `checks` | Zero-downtime check config | `checks:enable`, `checks:set` |
| `letsencrypt` | SSL certificate settings | `letsencrypt:enable` |
| `maintenanceMode` | Serve maintenance page | `maintenance:on` |
| `autoDeploy` | Auto-deploy on git push | Stored in DB; triggers deploy job on push |

---

## 2. The Reconciliation Engine

### 2.1 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     ManifestReconciler                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────────┐  │
│  │   Parser    │──▶│   Planner   │──▶│      Executor       │  │
│  │             │   │  (diff)     │   │   (DokkuEngine)     │  │
│  └─────────────┘   └─────────────┘   └─────────────────────┘  │
│         │                  │                    │               │
│         ▼                  ▼                    ▼               │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────────┐  │
│  │ raildock.   │   │ DesiredState│   │   ActualState       │  │
│  │ json / toml │   │   (DB rows) │   │  (Dokku queries)    │  │
│  └─────────────┘   └─────────────┘   └─────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Two Modes of Operation

#### A. Creation-Time Reconciliation
When a service is first created from a manifest (template deploy or import):

1. Parse manifest
2. Create `Service` DB record with `managed_by: 'manifest'`
3. Create related records: `EnvironmentVariable`, `Domain`, `StorageMount`, `ProcessType`
4. Create Dokku app (`apps:create`) or database (`postgres:create`)
5. Run full reconciliation to push all config to Dokku
6. Deploy if `autoDeploy: true`

#### B. Update-Time Reconciliation
When a manifest changes (git push with updated `raildock.json`):

1. Parse new manifest
2. Build `DesiredState` from manifest
3. Query `ActualState` from Dokku + DB
4. Compute diff
5. Apply deltas via targeted Dokku commands
6. Update DB records to reflect new state
7. Redeploy only if source code changed **OR** if deploy-affecting config changed (builder, docker options, etc.)

### 2.3 Diff Engine Detail

For each config category, the diff logic:

```ruby
class ManifestDiff
  def env_vars(desired, actual)
    to_set = desired.reject { |k, v| actual[k] == resolve_value(v) }
    to_unset = actual.keys - desired.keys
    { set: to_set, unset: to_unset }
  end

  def domains(desired, actual)
    desired_set = desired.map { |d| [d['hostname'], d['port']] }.to_set
    actual_set = actual.map { |d| [d['hostname'], d['port']] }.to_set
    {
      add: desired_set - actual_set,
      remove: actual_set - desired_set
    }
  end

  def storage(desired, actual)
    # ... same pattern
  end

  def links(desired, actual)
    desired_set = desired.map { |l| [l['from'], l['to']] }.to_set
    actual_set = actual.map { |l| [l['from'], l['to']] }.to_set
    { add: desired_set - actual_set, remove: actual_set - desired_set }
  end
end
```

### 2.4 What Triggers a Redeploy vs Just Reconfiguration

**Reconfig only (no rebuild/restart):**
- Env vars
- Domains
- Storage mounts
- Proxy settings
- Traefik labels
- Resource limits
- Cron
- Maintenance mode
- Let's Encrypt email

**Reconfig + container restart (ps:restart):**
- Docker options (change runtime flags)
- Port mappings (change exposed ports)

**Full redeploy (git:sync / git:from-image / ps:rebuild):**
- Builder change
- Source change (new commit, new image tag)
- Buildpacks change
- `app.json` scripts change (predeploy/postdeploy are build-time)
- Healthcheck type/path changes (Dokku embeds these in container config)

---

## 3. Change Handling & State Ownership

### 3.1 The Ownership Model

Every service has a `managed_by` field:

| Value | Behavior |
|-------|----------|
| `manifest` | Config is owned by `raildock.json`. UI shows read-only badges. User edits trigger a warning: "This service is manifest-managed. Changes will be overwritten on next deploy." |
| `ui` | Config is owned by the UI/database. Manifest is ignored for this service. |
| `hybrid` *(future)* | Manifest provides baseline; UI edits overlay. Reconciliation merges with UI changes winning for specific fields. |

### 3.2 Drift Detection

A background job (or deploy-time check) can detect drift:

```ruby
class DriftDetector
  def check(service)
    return unless service.managed_by == 'manifest'
    manifest = fetch_manifest(service)
    return unless manifest

    desired = build_desired_state(manifest)
    actual = build_actual_state(service)

    diff = ManifestDiff.new.diff(desired, actual)
    diff.empty? ? :synced : { status: :drifted, diff: diff }
  end
end
```

**Use cases:**
- Admin runs `dokku config:set` manually on the host → drift detected → next deploy reconciles
- User edits env var in UI on a manifest-managed service → drift detected → warning shown

### 3.3 The `sync` Flag for Env Vars

Borrowed from Dokku's `app.json` semantics:

```json
{
  "env": {
    "FEATURE_FLAGS": { "value": "new_ui,dark_mode", "sync": true }
  }
}
```

- `sync: false` (default): Set once on first deploy. Subsequent UI edits are preserved.
- `sync: true`: Overwrite on every deploy. Guarantees the manifest is the source of truth.

This is critical for manifest-managed services where some env vars should be sticky (database URLs) and others should be authoritative (feature flags).

---

## 4. Database & Link Lifecycle

### 4.1 Database Provisioning

```json
{
  "raildock": {
    "databases": [
      { "name": "main-db", "type": "postgres", "version": "16" }
    ]
  }
}
```

**Reconciliation:**
- If `main-db` does not exist → `dokku postgres:create main-db`
- If version differs → warning (Dokku plugins don't support in-place version upgrades; user must migrate manually)
- If removed from manifest → **do not auto-destroy** (too dangerous). Mark as "orphaned" in UI. User manually destroys.

### 4.2 Link Lifecycle

```json
{
  "raildock": {
    "links": [
      { "from": "main-db", "to": "web", "env_var": "DATABASE_URL" }
    ]
  }
}
```

**Reconciliation:**
- If link does not exist → `dokku postgres:link main-db web` (injects `DATABASE_URL`)
- If `env_var` changes → unlink with old var, relink with new var
- If removed from manifest → **unlink** (safe operation, just removes env var)

### 4.3 Cross-Service References

A manifest can reference services in the same project:

```json
{
  "env": {
    "DATABASE_URL": { "value": "${raildock.services.postgres.url}" }
  }
}
```

The reconciler resolves `${raildock.services.<name>.url}` before applying.

---

## 5. Integration with Existing RailDock Components

### 5.1 What Gets Replaced

| Current Component | New Approach |
|-------------------|-------------|
| `DeploymentJob` blind re-push | Replaced with diff-based reconciliation |
| `ServiceSettingsSync` | Merged into `ManifestReconciler#reconcile_config` |
| `TemplatesController` (hardcoded stacks) | Becomes a manifest generator + deployer |
| `AddServiceModal` manual forms | Can optionally import from manifest URL/file |

### 5.2 What Stays

- `DokkuEngine` — the command executor stays; the reconciler calls it
- `Service`, `EnvironmentVariable`, `Domain`, `StorageMount` models — used as the DB cache of desired state
- `DeploymentJob` — still orchestrates git sync / image pull, but config push is handled by reconciler
- `ServiceSettingsSync` — still used for UI-driven updates on `ui`-managed services

### 5.3 New Components Needed

```
backend/app/services/
├── manifest/
│   ├── parser.rb              # raildock.json / raildock.toml / app.json
│   ├── validator.rb           # JSON schema validation
│   ├── diff_engine.rb         # desired vs actual
│   └── reconciler.rb          # orchestrates apply
├── dokku/
│   └── state_reader.rb        # queries Dokku for actual state
└── templates/
    └── manifest_generator.rb  # converts templates to manifests
```

---

## 6. Implementation Phases

### Phase 1: Manifest Parser + Creation-Time Apply (Week 1-2)

- [ ] Add `managed_by` column to `services`
- [ ] Create `ManifestParser` (JSON + TOML)
- [ ] Create `ManifestValidator` (JSON Schema)
- [ ] On `ServicesController#create`, if manifest present:
  - Parse and validate
  - Populate DB records (env vars, domains, storage, process types)
  - Set `managed_by: 'manifest'`
- [ ] Extend `DeploymentJob` to read manifest and apply config before deploy

### Phase 2: Diff-Based Reconciliation (Week 3-4)

- [ ] Create `DokkuStateReader` (queries actual Dokku state)
- [ ] Create `ManifestDiff` engine
- [ ] Create `ManifestReconciler` (applies deltas via `DokkuEngine`)
- [ ] On deploy, diff manifest vs actual state → apply only changes
- [ ] Mark deploy-affecting changes vs reconfig-only changes

### Phase 3: Template → Manifest Migration (Week 5)

- [ ] Rewrite `TemplatesController#deploy` to generate manifests
- [ ] Template deploy creates services with `managed_by: 'manifest'`
- [ ] Remove hardcoded service creation logic; delegate to reconciler

### Phase 4: Drift Detection + UI Integration (Week 6)

- [ ] Drift detection endpoint `/api/services/:id/drift`
- [ ] UI read-only mode for manifest-managed services
- [ ] "Sync from manifest" button in service panel
- [ ] Warning modal when editing manifest-managed config in UI

### Phase 5: Cross-Service References + Advanced Features (Future)

- [ ] `${raildock.services.*}` variable resolution
- [ ] `hybrid` management mode
- [ ] Manifest import/export in UI
- [ ] PR preview environments (deploy manifest to isolated app)

---

## 7. Open Questions

1. **Should `raildock.json` live in the repo root or in a `.raildock/` directory?**
   - Repo root: discoverable, Heroku-like
   - `.raildock/`: can have multiple files (`production.json`, `staging.json`)

2. **Should env vars in the manifest be stored in `EnvironmentVariable` model or only in `config` JSONB?**
   - Model: enables UI queries, search, audit log
   - JSONB only: simpler, but loses relational features

3. **How do we handle secrets in manifests?**
   - Option A: Never commit secrets; use `generator: "secret"` only
   - Option B: Support encrypted values (SOPS, Rails encrypted credentials)
   - Option C: Store secrets in RailDock vault; manifest references by key

4. **Should database services be separate `Service` records or a different model?**
   - Separate `Service` records: consistent with current architecture
   - Different model: cleaner separation, but more complexity

---

## 8. Summary

RailDock's declarative config system builds on Dokku's `app.json` rather than replacing it. The `raildock` namespace extends it to cover the full platform surface. The reconciliation engine diffs desired vs actual state and applies minimal deltas, making deploys fast and predictable. Templates become manifest generators. UI-managed and manifest-managed services can coexist with clear ownership boundaries.

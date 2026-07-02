# Persistent Storage UX Audit & Recommendations

**Goal:** Make RailDock the most approachable deployment platform for persistent storage while doing it the right way (reliable, observable, reversible). This document compares how Railway, Render, Fly.io, and Coolify handle volumes, audits RailDock's current implementation, and recommends concrete UX and manifest changes.

**Implementation status (2026-07-02):** The "quick win" items from section 4 are implemented and tested:
- `storage_mounts.kind` column added with backfill (`volume` | `bind` | `tmpfs`).
- `RAILDOCK_STORAGE_HOST`, `RAILDOCK_STORAGE_CONTAINER_PATH`, `RAILDOCK_STORAGE_COUNT`, and indexed `RAILDOCK_STORAGE_N_*` env vars are auto-synced on mount/unmount.
- Storage API auto-generates Docker volume names from the container path.
- `StorageTab.tsx` redesigned with a storage-type picker, auto-naming, and mount-path guidance.
- Manifest parser/generator/schema support optional `kind`/`type` on storage entries.

---

## 1. Platform research

### 1.1 Railway — the current gold standard for approachable volumes

Railway treats a volume as a first-class resource that is *attached* to a service, not a raw host path.

- **Creation flow:** Right-click the service on the project canvas or use the command palette (`⌘K`) → "Create Volume" → pick the service → enter a mount path. ([Railway docs: Using Volumes](https://docs.railway.com/volumes))
- **Mental model:** One volume per service. The user only names the mount path; Railway provisions and names the backing storage.
- **Runtime contract:** `RAILWAY_VOLUME_NAME` and `RAILWAY_VOLUME_MOUNT_PATH` are injected automatically. ([Railway docs: Provided variables](https://docs.railway.com/volumes))
- **Important constraints:**
  - Volumes are mounted at runtime, not build time.
  - One volume per service.
  - No replicas with volumes.
  - Redeploying a service with a volume causes a small amount of downtime because Railway prevents two containers from mounting the same volume simultaneously. ([Railway docs: Caveats](https://docs.railway.com/volumes/reference))
- **Management:** Live resize on paid plans; CLI file manager (`railway volume browse` / `railway volume files`); manual and automated backups. ([Railway docs: Reference](https://docs.railway.com/volumes/reference))

### 1.2 Render — disk-centric, explicit mount path

Render exposes persistent disks as a separate resource attached to a service.

- **Creation flow:** Create a disk from the service's Disks tab or during service creation (Advanced). Set a mount path and size. ([Render docs: Persistent Disks](https://render.com/docs/disks))
- **Mental model:** A disk is a sized, mounted block of storage. Only filesystem changes under the mount path persist.
- **Constraints:** Only one instance per service can use a disk; zero-downtime deploys are not available; daily snapshots.
- **Common UX pain point:** Users frequently struggle to figure out the correct mount path (e.g. `/opt/render/project/src/uploads` vs `/uploads`). This is exactly the problem RailDock can avoid by auto-injecting paths and documenting the image's expected mount.

### 1.3 Fly.io — volume as regional, named resource

Fly.io volumes are regional, named resources created ahead of time and then referenced in `fly.toml`.

- **Creation flow:** `fly volumes create data --region ewr --size 25` then add `[[mounts]]` to `fly.toml`. ([Fly docs: fly volumes create](https://fly.io/docs/flyctl/volumes-create/))
- **Mental model:** Volumes are tied to a region and a Machine. Fork/extend/snapshots via CLI.
- **Constraints:** Not shared across Machines; apps that need volumes can't scale beyond one Machine per region without forking volumes.

### 1.4 Coolify — volume/bind-mount picker with host-path UX

Coolify is the closest comparison to RailDock because it sits on top of Docker on a user-controlled host.

- **Creation flow:** In the resource UI, choose Volume or Bind Mount, name it, and set destination path. ([Coolify docs: Persistent Storage](https://coolify.io/docs/knowledge-base/persistent-storage))
- **Mental model:** Two distinct types:
  - **Volume** — a named Docker volume; Coolify auto-appends the resource UUID to avoid collisions.
  - **Bind Mount** — a host path. No Docker volume is created.
- **Important guidance they surface:** "The base directory inside the container is `/app`. So if you need to store your files under `storage` directory, you need to define `/app/storage` as the destination path."

---

## 2. RailDock current state

### 2.1 What is implemented today

| Layer | Status | Key files |
|-------|--------|-----------|
| Data model | ✅ Works | `backend/app/models/storage_mount.rb`, `backend/db/migrate/20260424224810_create_storage_mounts.rb` |
| API | ✅ Works | `backend/app/controllers/api/storage_mounts_controller.rb`, `backend/app/controllers/api/recovery_controller.rb` |
| Dokku sync | ✅ Works | `backend/app/services/dokku_engine.rb#storage_mount`, `#storage_unmount`, `#storage_create` |
| Manifest parser/generator | ✅ Works | `backend/app/services/manifest_parser.rb#normalize_storage`, `backend/app/services/manifest_generator.rb` |
| Manifest reconciler | ✅ Works | `backend/app/services/manifest_reconciler.rb#apply_storage_change` |
| Backup/snapshot | ✅ Works | `backend/app/jobs/volume_backup_job.rb`, `HostEngine#volume_export_to` |
| Restore | ✅ Works | `backend/app/controllers/api/services_controller.rb#restore_backup`, `HostEngine#volume_import_from` |
| Restore drills | ✅ Works | `backend/app/jobs/restore_drill_job.rb` |
| UI | ⚠️ Functional but low-level | `app/src/features/service-panel/tabs/StorageTab.tsx` |

### 2.2 Current manifest schema

```toml
[[services]]
name = "pocketbase"
category = "app"

  [[services.storage]]
  host = "pocketbase-data"
  container = "/app/pb_data"
```

- `host` is overloaded: an absolute path means bind mount; a non-absolute name means a named Docker volume.
- `container` is the container mount path.
- This is used by ~250 templates, e.g. `backend/config/templates/pocketbase.toml`, `backend/config/templates/open-webui.toml`.

### 2.3 Current UI flow (StorageTab)

- Two free-text inputs: "Host path or volume name" and "Container path".
- Attach button.
- List shows host → container with snapshot and detach actions.
- Snapshot uses a destination selector (local or S3/R2).
- Warnings about rolling-deploy safety are already present.

### 2.4 Backup/restore model

- `BackupArtifactStore` persists snapshots locally or to an S3-compatible destination with AES-256-GCM encryption. `BackupDestinationClient` handles the upload/download.
- Volume backups store `host_path` and `container_path` in metadata.
- `restore_backup` for `backup_kind == "volume"` calls `HostEngine#volume_import_from`, which replaces the contents of the host path or named volume.
- `RestoreDrillJob` restores volume backups into an isolated Docker volume, verifies readability, then destroys the isolated volume.

---

## 3. Gap analysis

| Area | Railway / Render / Coolify | RailDock today | Gap |
|------|---------------------------|----------------|-----|
| Default storage type | Named volume (Railway auto-provisions) | Free-text `host` field | Users must know Docker volume vs host-path semantics. |
| Auto-naming | Railway auto-names the backing volume | User must type a name | Templates handle this, but UI-created mounts are error-prone. |
| Mount-path guidance | Railway explains `/app/...` relative paths; Coolify warns `/app` base | Placeholder only | Users don't know where the app code lives inside the container. |
| Runtime env vars | `RAILWAY_VOLUME_NAME` / `RAILWAY_VOLUME_MOUNT_PATH` | None | Apps can't be portable across mounts. |
| One-volume-per-service guard | Railway enforces it | No limit | Users can attach multiple mounts and accidentally create unsafe concurrent-writer situations. |
| Size management | Render/Railway expose size, resize, usage | No size field | Users can't cap or monitor storage. |
| File manager | `railway volume browse` | None | Users must SSH to inspect files. |
| Bind-mount warnings | Coolify clearly separates volume vs bind mount | Single input | Users can accidentally use host paths that don't exist or aren't portable. |
| Backup UX | Service-level "Backups" tab with snapshots list | Snapshot icon in Storage tab only; restore is buried in Backups tab | Discoverability is low. |
| Restore UX | One-click restore to service | Restore button on backup row works, but no preview/diff/warning | Users can't see what will be overwritten. |

---

## 4. Recommendations

### 4.1 UI/UX: turn "raw mounts" into "volumes"

**Principle:** The user should think "I want to persist `/app/data`" — not "I want to mount a Docker volume named X to host path Y to container path Z."

Concrete changes to `app/src/features/service-panel/tabs/StorageTab.tsx`:

1. **Storage type picker**
   - Default: **Docker Volume** (named volume, recommended).
   - Advanced: **Host Path Bind Mount**.
   - Hide or de-emphasize the host path for the default case.

2. **Auto-name the volume**
   - If the user picks Docker Volume, generate `{service.dokku_app_name}-{sanitized-container-path}` or `{service.name}-{purpose}` as the volume name.
   - Allow editing, but pre-fill so most users never touch it.

3. **Mount-path helper**
   - Show a contextual hint: "Your app is built into `/app`. If your app writes to `./data`, mount to `/app/data`."
   - Consider a small helper modal or link to per-template recommended paths when deploying from a template.

4. **Per-template mount suggestions**
   - Templates already know the right mount (e.g. `/app/pb_data` for PocketBase). When a service was created from a template, pre-populate or suggest the known mounts.

5. **Soft one-volume-per-service guidance**
   - Railway enforces one volume, but RailDock's multi-mount support is useful (e.g. config + data). Instead of enforcing, show a warning when more than one mount is added: "Multiple mounts increase complexity. Prefer a single mount unless the app requires separate paths."

6. **Better detach/restore warnings**
   - Detach: explain that data is *not* deleted, but the running container loses access and must be redeployed.
   - Restore from snapshot: show a confirmation modal listing the mount path and backup date, with a checkbox "I understand this will overwrite the current contents of `/app/data`."

### 4.2 Runtime: inject standard env vars

Mirror Railway's `RAILWAY_VOLUME_*` pattern with a RailDock namespace:

- `RAILDOCK_STORAGE_HOST_<N>` or `RAILDOCK_STORAGE_<NAME>_HOST`
- `RAILDOCK_STORAGE_<NAME>_CONTAINER_PATH`

A simpler first version: when a service has one storage mount, inject:

```
RAILDOCK_STORAGE_HOST=<host>
RAILDOCK_STORAGE_CONTAINER_PATH=<container_path>
```

This makes app images portable and aligns with how Railway users expect to detect volumes.

**Implementation notes:**
- These should be set by `DokkuEngine#config_set_many` during mount sync (or computed dynamically in `ManifestReconciler#apply_storage_change`).
- Mark them as internal/source=dokku so they are not shown in the env editor unless the user opts in.

### 4.3 Manifest schema: richer but backward-compatible storage block

Keep the existing `[[services.storage]]` shape for backward compatibility, but allow an extended form:

```toml
[[services.storage]]
host = "pocketbase-data"           # existing
container = "/app/pb_data"         # existing
# new optional fields:
type = "volume"                    # "volume" | "bind" | "tmpfs"
read_only = false
size = "10Gi"                      # advisory / quota hint for future host-size management
purpose = "data"                   # used for auto-naming and env vars
```

Also support a simplified, Railway-like form when `host` is omitted:

```toml
[[services.storage]]
container = "/app/data"
# RailDock auto-creates a named volume: {service}-data
```

**Required code changes:**
- `ManifestParser#normalize_storage`: accept optional `type`, `read_only`, `size`, `purpose`.
- `ManifestSchema#validate_service`: allow the new keys and validate `type` enum.
- `ManifestGenerator#service_to_hash`: emit extended fields only when set (keep generated manifests clean).
- `DokkuEngine#storage_mount`: pass `--read-only` when `read_only: true` (Dokku storage:mount supports this).

### 4.4 Backend: safer mount lifecycle

1. **Validate bind mounts before sync**
   - For host paths, warn if the path does not exist on the host. Dokku will create it, but a warning prevents typos.
   - Reject relative host paths in the API (the model already requires absolute or named volume).

2. **Idempotent named-volume creation**
   - Already implemented (`storage_create` is called for named volumes in `DokkuEngine#storage_mount`). Keep it.

3. **Store mount type in the DB**
   - Add `storage_mounts.kind` enum (`volume`, `bind`, `tmpfs`) so the UI can render icons and filters correctly.
   - Migration: backfill existing rows based on whether `host_path` starts with `/`.

4. **Size tracking (future)**
   - Add `storage_mounts.size_bytes` and a background job that runs `docker system df -v` or `du -sb` to update usage. This unlocks quota warnings and live resize later.

### 4.5 Backup/restore UX

1. **Surface snapshot CTA in the Backups tab, not only Storage tab.**
   - A "Snapshot volume" button when viewing a service's backups makes the feature discoverable.

2. **Add restore preview/warning.**
   - Before overwriting a live mount, show:
     - Backup date and checksum
     - Target mount path
     - Estimated size
     - "This will replace the current contents of the mount."

3. **Support restoring to a *new* mount (non-destructive).**
   - Useful for debugging: create a new mount from a snapshot without overwriting the live one.

4. **File manager (future, high value).**
   - A web-based mini file browser for mounted volumes would differentiate RailDock. Start with a read-only view that streams `tar` listings from `HostEngine`.

### 4.6 Documentation

Update `AGENTS.md` and add user-facing docs explaining:

- When to use named volumes vs bind mounts.
- The `/app` base directory convention for built apps.
- How backup/restore works and that volumes are not mounted during build.
- One-volume-per-service recommendation and why redeploys cause brief downtime.

---

## 5. Suggested implementation order

1. **Quick wins (this week)**
   - Redesign `StorageTab.tsx` with type picker + auto-naming + mount-path helper.
   - Inject `RAILDOCK_STORAGE_HOST` / `RAILDOCK_STORAGE_CONTAINER_PATH` env vars on mount sync.
   - Add `kind` column to `storage_mounts` and backfill.

2. **Manifest improvements (next)**
   - Extend `ManifestParser` / `Generator` / `Schema` with optional `type`, `read_only`, `purpose`.
   - Support simplified storage block with only `container`.

3. **Safety & observability**
   - Validate bind-mount host paths exist or warn.
   - Restore preview modal.
   - Size tracking job.

4. **Differentiators**
   - Web-based file manager for volumes.
   - Live resize (depends on host storage backend).

---

## 6. How this makes RailDock better than Railway

Railway is excellent but has hard constraints that come from its managed infrastructure:

- One volume per service.
- No replicas with volumes.
- Downtime on redeploy.

RailDock runs on the user's own Dokku host, so we can be *more flexible* while staying approachable:

- **Multiple named volumes** when an app truly needs them (config, uploads, cache).
- **Bind mounts** for advanced users who want host-level access.
- **Encrypted backups to any S3/R2 destination** with point-in-time recovery for Postgres and isolated restore drills.
- **Template-driven defaults** so users rarely have to think about mount paths.
- **No lock-in:** manifests are plain TOML, and storage is standard Docker volumes / host paths.

The recommended UX keeps the simplicity of Railway's "attach a volume at a path" mental model while exposing the extra power only when needed.

---

## 7. References

- [Railway: Using Volumes](https://docs.railway.com/volumes)
- [Railway: Volumes Reference](https://docs.railway.com/volumes/reference)
- [Render: Persistent Disks](https://render.com/docs/disks)
- [Fly.io: fly volumes create](https://fly.io/docs/flyctl/volumes-create/)
- [Coolify: Persistent Storage](https://coolify.io/docs/knowledge-base/persistent-storage)
- RailDock files: `app/src/features/service-panel/tabs/StorageTab.tsx`, `backend/app/services/dokku_engine.rb`, `backend/app/services/manifest_parser.rb`, `backend/app/services/manifest_generator.rb`, `backend/app/services/manifest_reconciler.rb`, `backend/app/jobs/volume_backup_job.rb`, `backend/app/controllers/api/recovery_controller.rb`.

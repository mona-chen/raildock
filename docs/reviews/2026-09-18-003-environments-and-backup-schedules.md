# Environments and backup schedules — platform research + implementation

Date: 2026-09-18
Companion to: `docs/reviews/2026-09-18-002-railway-ui-ux-benchmark.md`
Scope: how Railway, Coolify and Dokploy model **environments** and **scheduled
backups**, what RailDock did before, and what this pass changed.

## Method / sources

Primary sources only — published docs plus the products' own schema/source:

- **Railway** — `docs.railway.com/environments.md`, `volumes/backups.md`
  (fetched as markdown).
- **Coolify** — `coollabsio/coolify-docs` (`content/docs/databases/backups.mdx`,
  `core/persistent-storage/storage-mounts/backups.mdx`, `core/networking/destinations/overview.mdx`,
  `concepts.mdx`, CLI reference) and the Coolify source
  (`app/Models/Project.php`, `app/Models/Environment.php`).
- **Dokploy** — `Dokploy/docs` (`core/databases/backups.mdx`, API reference) and the Dokploy
  source (`packages/server/src/db/schema/environment.ts`, `project.ts`, `backups.ts`,
  `services/project.ts`, `services/environment.ts`).

## Environments

All three converge on the same shape, which is why RailDock now copies it:

| Concern | Railway | Coolify | Dokploy | RailDock before | RailDock now |
| --- | --- | --- | --- | --- | --- |
| Hierarchy | Project → Environment → Service | Project → Environment → Resource | Project → Environment → Service | Project (services hang off the project) | Project → Environment → Service |
| Default environment | every project starts with `production` | `Project::booted` creates `production` | `createProductionEnvironment` creates `production`, `isDefault: true` | `projects.environment` string column, one of `production/staging/development` | `environments` row created with the project, `is_default`, named after the create-dialog label |
| Create | `+ New Environment` in the env dropdown, or Settings → Environments; **Duplicate** or **Empty** | CLI `project environments create --name` | `duplicateEnvironment` / create | not possible | environment dropdown + Settings → Environments (empty environment; duplication is a follow-up) |
| Delete guard | default cannot be removed | deleting the project cascades environments | `deleteEnvironment` refuses the default and refuses any environment with services | n/a | refuses the default, refuses any environment with services |
| Isolation | changes are scoped to one environment | per-environment resources | services reference `environmentId` | none | `services.environment_id`, canvas filtered to the active environment |
| PR/preview environments | temporary, auto-created per PR, deleted on merge/close | preview deployments (per app) | preview deployments (per app) | none | out of scope (see follow-ups) |

Notable cross-platform details worth keeping in mind:

- Railway's duplicate-environment flow stages every service for deployment and makes you
  review the staged diff before anything deploys; Dokploy's duplicate copies the
  environment's own `env` blob. Both treat "new environment" as an explicit, reviewable action.
- Railway constrains restores to the *same* project **and environment**, which is only meaningful
  once environments exist.
- Dokploy stores project-level `env` **and** environment-level `env`, i.e. variables are scoped to
  the environment. RailDock still has project-level `shared_vars` only.

## Backup schedules

| Concern | Railway | Coolify | Dokploy | RailDock before | RailDock now |
| --- | --- | --- | --- | --- | --- |
| Unit | per **volume** | per **database** (`+ Add` under Scheduled Backups) | per **database** or **compose** (`backupType`) | per **service**, `backup_kind` = `database` \| `volume` | unchanged |
| Cadence | Daily / Weekly / Monthly | cron or named (`every_minute` … `yearly`) | cron string | `daily` / `weekly` / `monthly` | unchanged |
| Multiple schedules per resource | yes | yes | yes | yes | now surfaced together |
| Retention | fixed per cadence: daily 6d, weekly 27d, monthly 89d | three independent limits (count / days / GB), `0` = unlimited | `keepLatestCount` | `retention_count` 1..30, manual | same column, cap raised to 90, defaults per cadence (daily 7, weekly 4, monthly 6) |
| Pause without deleting | not documented | schedule can be edited | `enabled` boolean | **no** | `enabled` boolean, `RunDueBackupsJob` uses a `due` scope |
| Destinations | n/a (managed) | S3 per team, chosen per schedule | S3 destination per schedule | `metadata["destination_ids"]` | unchanged |
| Restore | stages a change for review | restore into a disposable DB first | uses the file + destination | typed-name confirm + pre-restore snapshot | unchanged |
| Run a test now | manual backup button | manual backup | `Test` button | manual "Back up now" | unchanged |

Retention semantics differ on purpose: Railway and Coolify express a *time* window, RailDock
keeps a *count* of artifacts. The invariant that matters — never expire the newest artifact of a
kind, never expire a `pre_destroy`/`pre_restore` safety net, clamp `keep` to ≥ 1 — is asserted by
`BackupSchedule#enforce_retention!` and `BackupRetention`, and now also by specs.

## What this pass changed

Environments (new `environments` table, one default `production` per project):

- `Environment` model with slug normalization, a single-default-per-project database index,
  `restrict_with_error` on services, and destroy guards for the default and for non-empty
  environments (`app/models/environment.rb`).
- `Service belongs_to :environment`, auto-assigned to the project's default environment on create
  and validated to belong to the same project (`app/models/service.rb`).
- Migration backfills a default environment per project and attaches every existing service, so an
  existing install's canvas looks identical after upgrading
  (`backend/db/migrate/20260918000002_create_environments.rb`).
- `Api::EnvironmentsController` (`index`/`create`/`update`/`destroy`) nested under the project;
  renaming the default also relabels `project.environment`, which the projects list still shows.
- The project payload now exposes `environments` (with `service_count`) and `has_deployments`
  (see the onboarding bug below).

Environments in the UI:

- The project toolbar's project name is a real switcher (recent projects, "View all projects",
  "New project") instead of a link back to the dashboard.
- The static environment label is a real switcher listing every environment with its service
  count, plus "New environment" (inline dialog) and "Manage environments".
- The canvas filters the already-loaded service list by the active environment, and the active
  environment lives in the URL (`?env=<id>`) so it is deep-linkable, survives a refresh, and is
  undone by Back →. Switching is instant (no refetch skeleton).
- Adding a service while an environment is active creates it **in that environment**
  (`environment_id` is now permitted in `service_params` and passed by `AddServiceModal`).
- Project Settings → Environments lists environments with rename, delete (guarded), and create.

Backup schedules in the UI + model:

- `backup_schedules.enabled` (default true) with `BackupSchedule.enabled` / `.due` scopes;
  `RunDueBackupsJob` only runs due **and enabled** schedules, so a paused schedule keeps its
  next-run bookkeeping.
- `PATCH /api/services/:id/backup_schedules/:schedule_id` updates frequency, retention, pause and
  destinations. Destination ids are only rewritten when the caller supplies the key, so a
  pause/resume cannot wipe a schedule's destinations.
- The Backups tab now lists **every** schedule (database and volume) with kind badge, mount path,
  retention, a next-run countdown ("in 6h"), last-run, pause/resume, inline edit and delete.
  Previously only database-kind schedules were rendered, with an absolute timestamp.
- The create form offers `Database` or `Volume snapshot` (when the service has mounts), and
  retention defaults per cadence instead of a fixed 7.
- `GET /api/services/:id/backup_schedules` includes the storage mount so a volume snapshot is
  labelled with the path it covers.

## Onboarding checklist bug (found while investigating)

The checklist never completed its "Deploy" step. `Project#has_deployments?` was serialized under
the method name, producing the JSON key `has_deployments?` → camelized `hasDeployments?`, while the
frontend read `hasDeployments`. The step was therefore permanently unsatisfied and the card could
never auto-hide.

Fixed by serializing non-predicate aliases (`has_deployments`, `manifest_synced`) and by rebuilding
the component as a single slim row: it collapses by itself once you have made progress, never
occupies a card-sized block, reads `localStorage` during initialization (no first-paint flash),
and disappears once every step is satisfied.

## Deliberately not done yet

- **Duplicating an environment** (Railway's copy-services-and-variables flow) and **syncing**
  services between environments. RailDock creates empty environments; moving a service between
  environments has no UI yet.
- **PR/preview environments** — needs a GitHub webhook → environment lifecycle and a
  "which environment does this branch deploy to" rule.
- **Environment-scoped variables.** Dokploy and Railway both scope variables to the environment;
  RailDock's `shared_vars` are still project-level, so a `staging` service currently sees the
  production shared variables.
- **Environment RBAC** (Railway restricts production to admins).
- **Cron expressions** and **independent retention limits** (count + days + max size) for schedules.
- **An organization-wide schedule overview.** Schedules are still reached per service; the
  `Settings → Backups` surface lists destinations only.

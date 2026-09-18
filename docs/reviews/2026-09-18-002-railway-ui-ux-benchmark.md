# UI/UX benchmark — RailDock vs Railway

Date: 2026-09-18
Companion to: `docs/reviews/2026-09-18-001-ui-ux-review.md`
Scope: read-only comparison of RailDock's frontend (`app/`) against Railway's documented
dashboard UX. No code changes were made.

## Method / sources

Railway publishes its product docs as clean markdown, so the comparison is anchored to
primary sources rather than screenshots:

- `docs.railway.com/overview/the-basics.md` — core concepts and IA
- `docs.railway.com/overview/keyboard-shortcuts.md` — global/canvas/service shortcuts
- `docs.railway.com/projects.md`, `environments.md`, `services.md`
- `docs.railway.com/deployments.md`, `deployments/staged-changes.md`,
  `deployments/deployment-actions.md`
- `docs.railway.com/build-deploy.md`, `variables.md`, `quick-start.md`,
  `observability/metrics.md`, `overview/advanced-concepts.md`

Railway is a managed PaaS with usage billing; RailDock is a self-hosted, multi-host
Dokku control plane. Patterns that depend on the managed/proprietary bits (usage
metering, Railway-provided domains, the template marketplace) are called out and not
recommended for direct copying.

## Railway's mental model

Railway's IA is a strict four-level hierarchy, and the UI mirrors it:

`Dashboard (projects) → Project/Canvas → Environment → Service → Deployment`

- The **dashboard** lists projects "in the order they were last opened" and is the only
  account-level surface (`the-basics.md`).
- A **project** is a canvas of services joined by a private network; project-level
  settings (transfer, environments, members, Danger) live behind a single `Settings`
  button (`projects.md`).
- **Environments** are a first-class nav element: every project starts with
  `production`, a `+ New Environment` dropdown creates/duplicates one, and changes are
  scoped to an environment (`environments.md`).
- **Services** are deployment targets (GitHub repo, local dir, Docker image, or
  function); variables, backups, metrics and settings are service-scoped tabs
  (`services.md`).
- **Deployments** are the built unit; actions (rollback, redeploy, restart) hang off the
  Deployments tab (`deployment-actions.md`).

## Concept mapping

| Railway | RailDock today | Notes |
| --- | --- | --- |
| Dashboard (projects, last-opened order) | `ProjectsPage` (grid, local search) | RailDock has no workspace/org switcher in the list view (it's in the icon rail). |
| Project canvas | `ProjectCanvas` + `CanvasGrid`/`ConnectionLines` | Equivalent; RailDock adds undo/redo buttons. |
| Environment (production/staging/PR, switchable) | single `Service.environment` **label** (`types/index.ts:13`) | No per-project environments, no switcher, no duplication. |
| Service | Service | Equivalent. |
| Service tabs: Deployments, Variables, Metrics, Settings | Deploy, Variables, Metrics, Settings (+ Logs, Console, Domains, Storage, Backups, Data) | RailDock is broader on ops; ordering differs. |
| Volume (own metrics + settings tabs) | Storage tab + `SnapshotsSubTab` | RailDock volumes are mounts, not standalone entities with their own tabs. |
| Staged changes (review + deploy changeset) | none — config saves apply immediately | Biggest workflow divergence, see below. |
| Config as Code (`railway.toml`) | `raildock.toml`/`.json` + `ManifestEditorPage` + drift detection | RailDock is further along here. |
| Command palette (`Cmd+K`) | none (`components/ui/command.tsx` unused) | See recommendation 1. |
| Deploy actions: rollback / redeploy / restart | rollback (`DeployTab.tsx:188`), rebuild, restart, cancel | Mostly present; surfacing differs. |

## Patterns Railway gets right

### 1. The command palette is the primary "do a thing" affordance
`Cmd+K` opens a palette that can run commands (create service, "Deploy Latest Commit",
restart a deployment), and `Cmd+/` creates a project; results are keyboard-navigable
with `ArrowRight`/`Backspace` for submenus (`keyboard-shortcuts.md`). Escape has one
consistent meaning everywhere: "go back, close a modal, or deselect".

RailDock has no global action surface and no command palette, even though a complete
cmdk primitive already ships unused at `app/src/components/ui/command.tsx`. Escape
semantics are also context-specific today (`ProjectCanvas.tsx:376`, plus three other
handlers — see review 001).

### 2. Staged changes: review before you apply
Every infrastructure edit is collected in a changeset. A banner shows the pending count,
staged changes render purple, `Details` opens a **diff of old vs new**, each change can
be individually discarded with an `x`, a commit message feeds the activity feed, and a
single `Deploy` applies everything at once (diff, deploy). `Alt`+click commits without
redeploying. Caveat they document: networking changes still apply immediately
(`deployments/staged-changes.md`).

RailDock is the opposite: `SettingsPanel.tsx:107` writes on every keystroke and toasts
per mutation. Railway's model — collect, diff, confirm, one apply — is the strongest
single idea to borrow, and RailDock already has the machinery: a manifest, a reconciler
with diffing, and drift detection (`ManifestEditorPage.tsx:163`). Surfacing pending
settings as a reviewable changeset would give users a "what will change on this deploy"
view before it happens, which also de-risks the auto-save problem.

### 3. One Deployments list, rich per-deployment actions
The Deployments tab lists every attempt with a three-dot menu: **Rollback** (restores
image *and* variables), **Redeploy** (same code and config), Restart for crashed
deployments, plus command-palette entries like "Deploy Latest Commit". Status
distinguishes `Crashed` from `Failed`, and a crashed deployment gets an **in-line
Restart button** instead of hiding the recovery behind a menu
(`deployment-actions.md`).

RailDock already has `useRollbackService`, `RollbackConfirmDialog`
(`DeployTab.tsx:188`), rebuild, restart and cancel. The gap is presentation: recovery
actions and the failure taxonomy are less discoverable, and there is no equivalent of
the inline Restart affordance.

### 4. Settings are scoped, and destructive actions are grouped
Project settings, service settings and volume settings are separate surfaces. Project
settings ends with an explicit **Danger** section ("Remove individual services or
delete the entire project"), and volume settings groups destructive actions together
("Wipe Volume — wipes all data in the volume and then redeploys the connected
service") (`the-basics.md`, `projects.md`). Destructive intent is not mixed into
general configuration.

RailDock puts destroy inside `SettingsPanel` (services) and inside `ProjectsPage`
(projects), but other destructive actions are scattered across settings tabs and use
native `confirm()` (review 001). A consistent Danger zone pattern would fix both.

### 5. Metrics tie deployments to resource changes
Railway's metrics graphs draw **dotted lines when new deployments began**, keep a
continuous series across deployments, and offer a **Sum / Replica** toggle for
multi-replica services; volumes get their own metrics and settings tabs
(`observability/metrics.md`).

RailDock's `MetricsTab` (152 lines) has 1h/6h/24h/7d windows and normalizes CPU against
the container limit — good — but shows only CPU and memory, with no deployment markers
and no disk/network. Deploy markers would directly answer "did my last deploy cause
this spike?", which is the question the tab exists for.

### 6. Environments as a first-class switch
Environments are created, duplicated and switched from the top nav, are automatically
created per Pull Request, and scope variable/config changes
(`environments.md`). RailDock models `environment` as one label per project
(`types/index.ts:13`), so there is no way to run the same stack as staging + production
or to spin up a PR environment.

This is the largest *product* gap, but it is also the most expensive to close (it
touches the schema, the manifest, and the deploy pipeline), so it is listed last.

### 7. Onboarding is a single decision point
The quick start reduces the first deploy to "New Project → pick GitHub repo →
**Deploy Now** *or* **Add Variables** → Deploy" (`quick-start.md`), with a link to the
template marketplace as the alternative path.

RailDock's `OnboardingChecklist` (server → project → service → deploy) is a reasonable
task list, but the create flows behind it differ: `AddServiceModal` already has a
type → source → scan → apply flow that is close in spirit. Making the checklist steps
link directly into that flow (rather than the generic project/service screens) would
match Railway's "one decision, then deploy".

### 8. Variables are paste-first
Railway's Variables tab supports a `RAW Editor` for pasting `.env`/JSON, and **suggests
variables** it detects from `.env*` files in the connected repo, one click to import
all (`variables.md`).

RailDock's `VariablesTab.tsx` supports bulk entry but there is no "we found these in
your repo, import them?" affordance, which is a high-leverage onboarding shortcut
during repository import (RailDock already scans the repo for other reasons).

## What RailDock does better (keep these)

- **Breadth of operational tooling.** Backups with verified remote destinations,
  volume snapshots, PostgreSQL PITR, recovery drills and restore safety nets go well
  beyond Railway's volume backups (`BackupsTab`, `SnapshotsSubTab`, `PitrSubTab`).
- **Deploy safety rails.** Typed-name confirmation, pre-destroy snapshots and refusal
  codes (`snapshot_required`, `removals_required`) are stricter than Railway's simple
  confirm dialogs.
- **In-app manifest editing with drift detection.** Railway has `railway.toml` but no
  equivalent editor showing drift; RailDock's `ManifestEditorPage` is ahead.
- **Multi-host from one control plane.** Railway is single-provider; RailDock's
  server inventory and remote bootstrap are a different product surface entirely.
- **Self-hosted, no usage metering.** Cost-control UX is intentionally out of scope.

## Recommended adoption order (Railway-derived)

1. **Command palette** (`Cmd+K`) wired to a handful of real actions: create project,
   add service, deploy/rollback the selected service, jump to a service, toggle
   Projects/Servers/Activity/Settings. Reuses `ui/command.tsx`; also gives the icon-only
   rail a discoverable, labelled alternative.
2. **Settings changeset with diff + one apply**, reusing the existing reconciler diff.
   This is the fix for per-keystroke auto-save *and* a genuinely useful review step.
3. **Deployments list parity**: surface rollback/redeploy/restart inline, distinguish
   `Crashed` from `Failed`, and add a "Deploy latest" action.
4. **Deployment markers on the metrics graphs** (and add disk/network series).
5. **Danger zones** in project/service settings, replacing native `confirm()`.
6. **Suggested variables from `.env*` during repository import.**
7. **Environments** as a first-class project concept — largest effort, do last and only
   if the roadmap wants staging/PR environments.

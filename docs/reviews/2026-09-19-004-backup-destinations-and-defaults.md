# Backup destinations: why they failed, and where a "global" backup config belongs

Date: 2026-09-19
Companion to: `docs/reviews/2026-09-18-003-environments-and-backup-schedules.md`
Scope: three reported backup defects (remote uploads fail, the destination picker
forgets its choice, and the question of an organization-wide backup configuration),
plus the platform research behind the answer.

## Method / sources

Primary sources only, fetched during this pass:

- **Railway** — `docs.railway.com/volumes/backups` (backup model, schedules,
  retention, limits, caveats).
- **Coolify** — `coolify.io/docs/databases/backups` (database schedules,
  execution semantics), `coolify.io/docs/core/s3-storage/overview` (where S3
  storage lives and how it is selected), and
  `coolify.io/docs/core/persistent-storage/storage-mounts/backups` (retention).
- **Heroku** — `devcenter.heroku.com/articles/heroku-postgres-backups`
  (`pg:backups:schedule`).
- **Supabase** — `supabase.com/docs/guides/platform/backups` (tiers, PITR,
  who owns the bucket).
- Plus the SDK and Postgres sources quoted below, read on the target host.

## 1. Remote uploads failed

Two independent defects, both reproduced against the real Postgres container and
the installed gems before changing anything.

**`unexpected value at params[:thread_count]`.** `aws-sdk-s3` 1.226.0 turned the
multipart executor into an injected dependency: `FileUploader#initialize` reads
`options[:executor]` and no longer supplies a default, and `#upload` passes
`**options` straight into `put_object` for anything under the multipart
threshold. So the old `thread_count: 4` was neither honoured for large files nor
stripped for small ones — it was forwarded to the API call, which rejects unknown
parameters. `BackupDestinationClient#upload` now builds an executor for the
single upload and shuts it down afterwards. It is deliberately *not* a
process-wide memoised pool: `puma.rb` documents `WEB_CONCURRENCY`, and a thread
pool does not survive a fork.

**`pg_basebackup: cannot stream write-ahead logs in tar mode to stdout`.**
`PostgresBaseBackupJob` ran `pg_basebackup -D - -Ft -z -X stream`, which can
never succeed: tar output on stdout is incompatible with streaming WAL, and
`-X stream` is pg_basebackup's default, so it has to be turned off explicitly.
Measured on Postgres 16.15:

| Command | Result |
| --- | --- |
| `-D - -Ft -z -X stream` | exit 1, 0-byte file, "cannot stream write-ahead logs in tar mode to stdout" |
| `-D - -Ft -z` (no `-X`) | identical — `stream` is the default |
| `-D - -Ft -z -X fetch` | exit 0, complete 8.2 MB archive with `pg_wal/` inside |

The job now uses `-X fetch`, which writes the required WAL segments into the
archive itself.

## 2. The destination picker forgot its choice

Not a cache bug: there was nowhere to store the answer. In
`BackupsSubTab.tsx` the checkboxes were plain `useState([])`, and the only
persisted records were per-*run* (`Backup.metadata["destination_ids"]`) and
per-*schedule* (`BackupSchedule#destination_ids`) — no service or organization
default existed, so every mount started at "Local only".

## 3. Should there be a global backup configuration?

Yes — but a *default destination*, not a global schedule. How the platforms split
this up:

| Concern | Railway | Coolify | Heroku | Supabase | RailDock (now) |
| --- | --- | --- | --- | --- | --- |
| Unit | per volume | per database resource | per database attachment | per project | per service |
| Cadence | Daily / Weekly / Monthly | cron or named frequency | daily at a time-of-day | daily (platform) | daily / weekly / monthly |
| Retention | fixed per cadence (6d / 27d / 89d) | count **and** days **and** GB, each `0` = unlimited | plan-tiered (7 / 14 / 30 days) | plan-tiered (7 / 14 / 30 days) | count (1–90) |
| Where the bucket lives | platform-owned, not selectable | one **instance/team** S3 storage object, *selected per backup config* | platform-owned | platform-owned S3 | **organization default + per-service override** |
| Inheritance | none | none (chosen per schedule) | none | none | org default → service override |
| PITR | separate feature | not for these schedules | no | yes, the paid upgrade path | `PostgresPitrConfig` |
| "Backup ≠ restore test" | not stated | stated explicitly | not stated | not stated | `RunRecoveryDrillsJob` |

Reading:

- **Nobody** ships a single global "backup" switch. What every platform does
  centralise is the *credentialled destination* (Coolify: an instance/team S3
  storage object you pick per backup config; the rest: a bucket you cannot
  choose). Nobody centralises cadence or retention across resources.
- **Railway's retention is fixed to the cadence** (daily 6d, weekly 27d,
  monthly 89d) and backups hang off volumes, not databases; restores are
  constrained to the same project **and environment**; wiping a volume deletes
  its backups. That is a narrower model than RailDock's.
- **Coolify's retention is the most expressive** — three independent limits
  where `0` means unlimited, with local and S3 retention tracked separately, and
  "Disable Local Backup removes the local file after a successful S3 upload".
  RailDock already behaves that way but did not say so in the UI.
- **Heroku is the odd one out**: a database-level daily schedule with a
  time-of-day and timezone, and no failure notifications — the schedule is lost
  when the plan or attachment changes.

Decision, implemented here: the **organization** owns the default destination
list, and a service may override it. Cadence and retention stay per schedule,
which matches every platform reviewed and keeps a short volume window from
touching database artifacts (the invariant asserted by
`BackupSchedule#enforce_retention!`).

## What this pass changed

- `organizations.default_backup_destination_ids` (jsonb, default `[]`) — the
  organization-wide default, starred per destination in Settings → Backups.
- `services.default_backup_destination_ids` (jsonb, **nullable**) — the service's
  own choice. `nil` means "never chose" (inherit the organization), `[]` means a
  deliberate "local only", which is why the column cannot default to `[]`.
- `Service#resolved_backup_destination_ids` resolves service → organization, and
  `GET /api/services/:id/recovery` returns all three lists
  (`organizationDestinationIds`, `serviceDestinationIds`, `defaultDestinationIds`)
  so the picker renders the real choice on first paint instead of flashing
  "Local only".
- `PATCH /api/services/:id/recovery/preferences` remembers the picker's value;
  `null` clears the override back to inheritance. The picker persists on toggle,
  and offers "Use organization default" once a service has its own choice.
- The picker's always-disabled row no longer claims the host copy is "always
  included". It is only the only copy when no destination is selected — matching
  `BackupArtifactStore#keep_local_copy?`, which drops the local file once a
  verified remote copy exists.
- Deleting a destination prunes it from both defaults
  (`BackupDestination#forget_from_backup_defaults`), so a picker cannot offer a
  destination that no longer exists and fail validation later.

## Deliberately not done

- **A global schedule or retention policy.** No reviewed platform centralises
  cadence; doing so would fight the per-kind retention invariant above.
- **Per-destination failure notifications.** Heroku has none either, and
  RailDock already surfaces the failure in `DataSafetyReport` and the backup list.
- **`allow_removals`-style cascade for defaults.** Deleting a destination still
  refuses while backups or PITR configs reference it
  (`restrict_with_error`); the defaults are pruned only after a successful
  delete.

## Follow-ups

- Coolify lets a schedule choose its S3 storage **and** keep or drop the local
  copy explicitly. RailDock can now express "local only" as a service choice but
  still cannot keep *both* a local and a remote copy for one run; the API
  validates ids against destinations, so `"local"` in `destination_ids` is
  rejected. Lifting that needs `BackupArtifactStore` to treat "local" as a
  first-class entry in the request.
- `VerifyBackupDestinationsJob` already re-proves destinations on a schedule;
  wiring its result into the picker ("this default stopped verifying") would
  close the loop the way Coolify's execution history does.

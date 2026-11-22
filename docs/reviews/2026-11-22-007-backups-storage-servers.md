# Review 007 — Backups, storage destinations, remote servers and UI

Date: 2026-11-22

Scope: backup flow and UI, backup types (compared with Railway), backup
storage destinations, remote server management, and overall dashboard UI/UX.
Every item below marked **Fixed** shipped with tests in the same change.

## Why it looked like "we only support PITR"

RailDock already had three kinds of backup: logical dumps (Postgres, MySQL,
MariaDB, MongoDB, Redis), volume snapshots (named volumes and host paths),
and PostgreSQL PITR (daily base backup plus WAL every minute). In practice,
PITR was the only automated one that worked from the dashboard:

- **Fixed — schedules could not be created from the UI.** `lib/api.ts` sent
  `retentionCount`/`destinationIds`/`storageMountId`, and the controller
  permits only snake_case. With nothing converting the keys, every schedule
  failed validation (`retention_count` nil), and editing a retention window
  showed a success toast but changed nothing.
- **Fixed — schedules with destinations raised even in snake_case.**
  `backup_schedule_params` assigned a plain Hash into permitted `Parameters`,
  which makes it unpermitted again.
- **Fixed — drills always failed except on Postgres.** `RestoreDrillJob` ran
  `pg_isready` in a `dokku.postgres.*` container for every engine, so weekly
  drills reported MySQL/MariaDB/MongoDB/Redis backups as broken.
- **Fixed — Redis could not be backed up by hand.** The endpoint checked
  `service_type_database?`, but Redis is a `cache`. It now checks the
  subtype's backup/restore capabilities.
- **Fixed — apps with volumes landed on a database form.** That form's
  "Create backup" and "Import" buttons answered 422.

## Backup types: RailDock vs Railway

Railway, per its public documentation as of mid-2026 (re-check before
quoting externally):

- backs up **volumes** only;
- offers manual backups plus daily, weekly and monthly schedules with fixed
  retention (about 6 days, 1 month and 3 months);
- keeps the copies inside Railway, with no external bucket or download;
- stages a restore as an environment change you deploy;
- has no first-party PITR; Postgres PITR comes from community WAL-G templates.

| Capability | Railway | RailDock |
|---|---|---|
| Volume snapshots, manual and scheduled | Yes | Yes |
| Logical database dumps (pg_dump etc.) | No (volume-level) | Yes: Postgres, MySQL, MariaDB, MongoDB, Redis |
| PostgreSQL point-in-time recovery | No (community templates) | Yes: base backup plus WAL every minute, 1–90 day window |
| Configurable retention | Fixed per cadence | 1–90 copies per schedule |
| Off-site destinations you own | No | S3, R2, B2, Wasabi, Spaces, Hetzner, MinIO, GCS (HMAC) |
| Client-side encryption, offline decrypt | n/a | AES-256-GCM per destination; `scripts/decrypt-backup.rb` |
| Download artifact | No | Yes |
| Restore-test in an isolated copy | No | Yes, manual and weekly automatic |
| Safety snapshot before restore/delete | Staged restore | Yes, `DestructionSnapshot` |
| PITR restore into the live database | n/a | **Not yet**: drills recover into an isolated instance |

RailDock covers more kinds of backup than Railway. Two gaps remain worth
closing:

- **PITR recovery into the live database.** A "recover to time T" that
  restores into a new service would mirror Railway's staged restore.
- **Incremental volume snapshots.** RailDock takes a full tar each time.

## Backup UI/UX

- **Fixed — volumes were filed under Networking.** The service panel is now:
  - Networking: domains only.
  - Storage (named Backups for datastores): Database backups, Point-in-time
    (Postgres only) and Volumes, with snapshots shown beside the volumes they
    protect.
  - `?tab=storage` is kept as an alias, and `?section=` deep-links a
    sub-section.
- **Fixed — no at-a-glance status.** A protection summary line says whether
  the database is backed up automatically, whether PITR is on, how many
  volumes have a schedule, and whether copies leave the host.
- **Fixed — volume snapshots were listed twice** (under both Backups and
  Snapshots).
- **Fixed — download filenames were wrong.** Every file got `.dump`; the name
  now matches the engine (`.dump`, `.sql`, `.archive`, `.rdb`, `.tar.gz`).
- **Fixed — destructive actions were inconsistent.**
  - Deleting a schedule or an artifact needed no confirmation.
  - Restores used hand-rolled modals, and the force-past-safety prompts used
    `window.confirm`.
  - Snapshot restore copy said "cannot be undone", contradicting the
    pre-restore snapshot that is taken.
  - All of these now use `ConfirmDialog`, with accurate copy.
- **Fixed — destination picker opened on hover only.** It is now a Popover.
  New schedules start from the service's default destinations instead of
  local-only, and an edited schedule can change its destinations.
- **Fixed — every artifact row looked the same.** Rows now show:
  - the trigger (manual, scheduled, before delete, before restore);
  - the restore-test result;
  - the failure reason;
  - a test-restore action for volume snapshots, which the backend already
    supported.
- **Fixed — PITR had gaps:**
  - It could not be turned off.
  - Retention was hardcoded to 7 days.
  - The header showed green in an error state.
  - Unverified destinations were offered, and the API now refuses them.
  - There was no recovery window ("recoverable from"), and no validation of
    the target time.
- **Fixed — changing PITR's destination or retention restarted PostgreSQL**,
  because every save called `enable!`. Postgres now restarts only when
  archiving first turns on. Moving to another destination starts a fresh base
  backup there.
- **Fixed — retention limits disagreed** (UI 90, model 30). Both are now 90.
  The default follows the cadence when a request omits it.
- **Fixed — schedule timing was wrong.** A frequency change kept the old next
  run, and resuming a paused schedule fired immediately for a slot it missed.

## Storage destinations

The fixes here were done in parallel with this review; see
`BackupDestinationsTab.tsx`, `backup_destination_client.rb` and
`backup_destinations_controller.rb`.

- **Fixed — failed checks left rows behind.** A destination that failed its
  check still saved a "failed" row whose recovery key was never shown. This
  happened on both create paths.
- **Fixed — a mistyped edit broke a working destination.** It marked the
  destination failed. Edits are now probed in memory first.
- **Fixed — verification could hang for minutes.** It nested retries around
  SDK retries with a 300s timeout. Permanent errors (bad credentials, missing
  bucket, wrong region) are no longer retried.
- **Fixed — the re-verify job:**
  - ignored its own "stalest first" order;
  - never re-checked `pending` destinations;
  - only logged failures.
  It now raises a warning activity event when a verified destination fails.
- **Fixed — permission gaps.** Members could trigger a verify, which writes
  to the bucket. A service editor could delete an organization-wide
  destination from the service tab.
- **Fixed — limited providers and no edit UI.** Presets added for B2, Wasabi,
  DigitalOcean Spaces, Hetzner, MinIO and GCS. Destinations can now be edited
  (blank secrets keep the current ones), rows show the last verified time and
  last error, and failed or pending destinations cannot be starred as the
  default.
- **Fixed — the recovery key could not be used.** There is now a
  bring-your-own key option on create, and `scripts/decrypt-backup.rb` with
  docs in `docs/operations.md`.
- **Open:**
  - SFTP/rsync destinations;
  - Azure Blob;
  - object-lock (immutable) buckets;
  - per-destination storage usage;
  - server-scoped destinations, which Settings still does not list.

## Remote servers

- **Fixed — the setup wizard never showed progress.** The client subscribed to
  its own setup id, and the server ignored it and generated another. The
  server now issues and binds the id, and progress reads are restricted to
  its owner.
- **Fixed — shell injection.** `external_proxy_network` and `proxy_mode` went
  into the remote shell command unescaped.
- **Fixed — sudo, user and host checks.**
  - The "Deployment User" field was never sent, so it was removed.
  - "Passwordless sudo" was promised but not used; non-root admins now run
    the bootstrap through `sudo -n`.
  - Re-adding a known host failed only after the full bootstrap; it now fails
    up front.
- **Fixed — bootstrap robustness:**
  - The job moved off the `default` queue.
  - `systemctl reload sshd` failed silently on Ubuntu 22.04+; the config is
    now validated with `sshd -t` and whichever of the `ssh`/`sshd` units
    exists is reloaded.
  - Datastore plugin failures are summarised at the end.
- **Fixed — server safety:**
  - Clients could overwrite the pinned host key on update.
  - Deleting a server silently orphaned its projects; it is now refused.
  - "Check connection" gave no feedback.
  - The detail page lacked "Remove server…".
- **Open, compared with Coolify and Dokploy:**
  - SSH port and jump host;
  - per-server keys and key rotation;
  - preflight checks (OS/arch, disk, RAM, ports, outbound reach to
    `bootstrap.sh`);
  - showing the host-key fingerprint before trusting it;
  - firewall, swap and Docker cleanup schedules;
  - build servers;
  - moving a project between servers (today `server_id` is only re-pointed);
  - a server picker when creating a project (currently
    `scoped_servers.first`);
  - a periodic server health job, so status does not go stale.

## Dashboard-wide UI

- **Fixed — decorative icons.** Rocket and Sparkles icons replaced with
  functional ones (Play, GitMerge, Layers, PackageCheck, Plus, Info), as
  AGENTS.md requires.
- **Fixed — the console lost the command on failure.** It is now kept.
- **Fixed — the project delete button** had no accessible name and could not
  be reached by keyboard.
- **Open:**
  - The project Settings view has no Danger Zone; delete is only on the card.
  - About 8 more hand-rolled `fixed inset-0` modals remain (ManifestEditor,
    service delete in SettingsPanel, DeployTab, Docker import, unmanaged
    datastores).
  - Uppercase eyebrow headings remain outside the backup screens.
  - 271 raw `<button>` vs 69 `<Button>`.
  - The integration toggle in `SettingsPage` has no switch role.
  - Settings mixes account, organization and instance scope in one 12-tab
    sidebar.

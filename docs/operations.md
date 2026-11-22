# Operations

## Remote server setup

Remote hosts are bootstrapped via the script returned by
`GET /api/organizations/:id/server_bootstrap`. Run it as root; it installs
Docker, Dokku, the datastore plugins, and the Nixpacks/Railpack builders,
authorizes the organization's public key for both `root` and `dokku`, and
raises `sshd` connection limits. For fully automated provisioning, add the
organization public key to an admin user's `~/.ssh/authorized_keys` first so
`ProvisionServerJob` can connect and run the bootstrap for you.

## Backing up RailDock itself

Back up RailDock's own database:

```bash
cd /opt/raildock
./scripts/backup.sh
```

Restore:

```bash
./scripts/restore.sh backups/raildock_production-20260101-120000.sql.gz
```

Service backups are stored under `${BACKUPS_DIR:-./data/backups}` and mounted
at `/rails/storage/backups` in production. A backup is only marked completed
after its artifact is persisted and SHA-256 verified. Keep the directory on
durable storage and include it in host-level disaster recovery.

## Off-site backup destinations and recovery keys

Settings → Backups manages organization destinations: Amazon S3, Cloudflare R2,
Backblaze B2, Wasabi, DigitalOcean Spaces, Hetzner Object Storage, MinIO and
Google Cloud Storage (S3 interoperability endpoint with HMAC keys). All of them
use the S3 API. A destination is saved only after a write/read/delete probe
succeeds; a failed probe leaves nothing behind. Editing credentials re-probes
the new values first and keeps the stored ones if the probe fails. Blank secret
fields keep the current secret. Verification writes to the bucket, so only
owners and admins can run it. A destination that still holds backups, backup
copies or a PITR configuration cannot be deleted.

Every artifact sent to a destination is encrypted with that destination's
recovery key (AES-256-GCM) before it leaves the host. RailDock stores the key
encrypted in its own database, so restores from the dashboard never ask for it.
Keep a copy off-host anyway: if the RailDock database is lost, the key is the
only way to read what is in the bucket. RailDock shows a generated key once,
when the destination is created. You can supply your own 64-character
hexadecimal key instead. The key cannot be changed later, because existing
artifacts depend on it.

### Decrypting an artifact without RailDock

The artifact format is `RAILDOCK-BACKUP-V1\0` (19 bytes), a 12-byte IV, the
ciphertext, and a 16-byte GCM authentication tag at the end of the file.
`openssl enc` cannot decrypt GCM, so use the bundled script. It needs only Ruby
and its OpenSSL library:

```bash
# Download the object (path_prefix/... as shown on the backup copy)
aws s3 cp s3://my-backups/raildock/<key> artifact.backup   # add --endpoint-url for non-AWS providers

# Prompts for the recovery key without echoing it
ruby scripts/decrypt-backup.rb artifact.backup artifact.out
# or: RAILDOCK_RECOVERY_KEY=<64 hex chars> ruby scripts/decrypt-backup.rb artifact.backup artifact.out
```

The output is written only after the authentication tag verifies, so a wrong key
or a truncated download fails without leaving a partial file. The decrypted file
is the original artifact, such as a database dump or a volume tarball. Restore it
with the datastore's usual tools.

## Email invitations

Set `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, and `MAIL_FROM` in `.env`, or configure SMTP through Settings. Until SMTP is configured, invitations are created but their links must be shared manually.

## Security and operations

- Secrets are generated per install and live in `.env` and `backend/config/master.key`. Do not commit them.
- SSH keys for managed servers are stored in `./data/dokku-ssh/`.
- JWT tokens expire after 30 days.
- Auth endpoints are rate-limited.
- Production runs with CSP, CORS restrictions, and other security headers.
- CI runs Brakeman, bundler-audit, and npm audit.
- Set `FORCE_SSL=true` when running behind a TLS-terminating proxy.

[Back to the README](../README.md)

## Templates

Templates are loaded from the configured on-disk repository when RailDock boots.
Set `RAILDOCK_TEMPLATES_REPO` to the Git URL of your trusted template repository,
then restart RailDock. The template view offers a retry if the API is temporarily
unavailable. Git and Docker image services remain available without a catalog.

## Recovery verification

PITR retention preserves the base backup anchoring the retention window and every
subsequent WAL artifact, including timeline history. Physical recovery drills boot
a private PostgreSQL container with no network or published ports, replay WAL,
verify that recovery completed, and remove the container and volume. An optional
ISO-8601 target is accepted by the drill endpoint; the UI accepts local time and
converts it to UTC. A failed/unreachable target is reported as a failed drill.
These drills do not replace a live datastore. Keep the recovery keys off-host.

## Release and startup checks

Main images are published only after CI succeeds for the checked-out commit.
Tagged releases run the same reusable checks. Before main publication,
`scripts/test-image.sh` starts the production image against a disposable
PostgreSQL server with fresh secrets and checks the API and credentials file.
Local credentials, environment files, storage artifacts, and development caches
are excluded from the Docker build context. Startup fails on migration errors;
it never marks a failed migration as applied.

Project manifests currently manage the default environment. Other environments
are managed through their service settings and environment sync. Bulk canvas
actions always target the selected environment.

The dependency lockfiles include the patched Rails 8.1.4.1 and SSH stack. The
frontend uses a scoped `minimatch` override for TypeScript ESLint's parser until
its upstream dependency range includes the patched major; other consumers keep
their compatible versions. Recheck this override when updating TypeScript ESLint.

## Development and versioned releases

Main publishes images after CI and updates one rolling `edge` prerelease.
`VERSION` supplies the development base; images identify the exact build as
`0.1.0-dev.<sha>`. Immutable image tags remain available for rollback. The
`latest` image alias follows development until the first stable release, then
is reserved for stable releases. Prerelease tags never replace a stable image.

Create an intentional release with `./scripts/release.sh 0.1.0`. Versioned
release pages wait for the image build; deploy image `:0.1.0`, not `:v0.1.0`.
Versioned installations follow stable releases; development installations
follow the rolling edge build. Cleaning GitHub metadata does not remove GHCR
images or change running containers.

## Updating from the dashboard

Dashboard and automatic updates run through a transient `systemd-run` service on
the installation host. Docker continues to manage the app with its restart
policy. Configure `DOKKU_HOST` and a matching local SSH server record; the runner
also verifies the current container id before scheduling a replacement. A remote
managed server is never selected merely because it has an SSH key.

The host job pulls the selected immutable image, saves a control-database backup,
checks its archive catalog and SHA-256, recreates only the RailDock service, and
waits for its health check. An unhealthy image triggers a fallback to the previous
image id. Database migrations are not automatically reversed: the private backup
is retained for deliberate recovery. Operation status, output, and backup files
live under `<install-dir>/data/updates/<operation-id>` (root-only). Inspect the
transient unit with `systemctl status raildock-update-<operation-id>` or read its
`output.log` if the dashboard cannot reconnect. The UI reports scheduling rather
than success until the host verifies the replacement.

Images built before this updater change require one CLI update to install the
new runner. No host update is executed merely by changing the repository code.


### Resource observability

Settings → Observability (instance administrators) controls application/host
collection independently and metric retention (1–90 days, default 30). Turning a
collector off stops both live and background reads, while retained samples age
out normally. Shortening retention expires older samples on the next cleanup.

Servers → View live metrics and history shows whole-host CPU, memory, root disk,
load, uptime and network counters. Host views refresh every ten seconds while
open; background history is sampled every minute. Container views now plot live
readings as well as retained history. The primary web/datastore container is the
current application scope; worker and replica aggregation is not yet supported.
Host collection failures are unavailable, never synthetic zeroes. Docker sampling
is batched per host. No additional host agent, public monitoring port or external
telemetry provider is installed. HTTP analytics and notification rules are configured separately; see the sections below.

### HTTP traffic analytics

Open Servers → select a host → HTTP traffic → Configure collection. Collection is
opt-in and reads an existing **host-accessible** JSON access log. It supports
Traefik JSON (`StartUTC`, `DownstreamStatus`, `Duration` in nanoseconds) and Caddy
JSON (`ts`, `status`, `duration` in seconds). The host needs Python 3 and `timeout`.
Use a regular `.log` or `.jsonl` file under `/var/log/` or `/var/lib/dokku/`.
Symlink log paths are refused. For a containerized proxy, the log file must already
be mounted to a host path. RailDock does not restart or rewrite an existing proxy.

Traefik's access log must be enabled in JSON format and written to a host-mounted
file; Caddy likewise needs its access-log JSON file output configured. These are
proxy operational changes: arrange the proxy's own safe reload/restart separately.
RailDock reports failed reads rather than assuming access logging is configured.

First enable and source changes start at EOF, avoiding a replay of an enormous
historic log. Subsequent scans read at most 2 MiB and preserve an inode/offset
cursor. Backlog, skipped malformed/oversized lines and rotation gaps appear in the
UI. Unread data in the old file after rotation may be missing; this is not a
lossless log archive. Switching sources keeps previously collected history.

Requests, response bytes, status counts and latency histograms are aggregated on
the host before transmission. Top-path persistence is separately opt-in and capped
at 25 categories plus an overflow bucket; query strings, IPs, headers and bodies
are not retained. Paths can still contain identifiers, so review that setting
before enabling it. Request domains map traffic to applications; unmatched requests
remain in server totals as unmapped traffic. Unique visitors, location and device
fingerprinting are not collected. Latency p95 is shown as a histogram upper bound.

Minute detail is retained for at most two days, hourly aggregates for the chosen
1–30 days. The seven-day dashboard uses hourly data. Cleanup continues when
collection is disabled. Background collection runs every minute; live views request
refresh every ten seconds and concurrent collectors are coalesced. Monitoring has
a separate worker queue so it cannot occupy deployment/backup worker threads.

### Monitoring notifications

Settings → Notifications is organization-scoped and available to owners/admins.
Enable monitoring for in-app incident history, then enable email to notify the
organization owner and admins. Add up to ten additional destinations (shared
inboxes/on-call addresses), separated by commas or new lines. Validated destinations
are stored with that organization's policy. Configure working SMTP under instance
Email settings before expecting outgoing mail.

Rules cover sustained host/application CPU and memory pressure, host disk pressure,
missing metric/HTTP collectors, HTTP 5xx rate and request-volume thresholds. The
5xx rule requires at least twenty requests in a complete minute. Pattern matching
is an optional rule with a default threshold of zero (off), not the purpose of the
analytics overview. A zero numeric threshold disables that rule. Deploy/backup
failure events are immediate and successful subsequent operations record recovery.

Sustained duration is 1–15 minutes. Active incidents are deduplicated; host resource
thresholds have five percentage points of recovery hysteresis. Traffic alerts pause
while collection is unavailable or catching up. Email uses the observability queue,
retries transient failures up to three attempts, and shows queued/delivered/failed,
SMTP-unconfigured or no-recipient status. Delivered means SMTP accepted the message,
not that an inbox received it. A crash after SMTP acceptance can cause a duplicate
on retry; exactly-once email delivery is not guaranteed. Resolved incident retention
is configurable from 1–90 days.

Operational cost: the dedicated observability queue adds a Rails worker process
(two threads), so budget additional application memory before production rollout.
A local, network-isolated Linux-container benchmark parsed 2,500 synthetic Caddy
records (375 KB) in 0.0148 CPU seconds with a process peak RSS of about 17 MiB.
This measures the Python reader only; it excludes Rails, SSH, database and SMTP
overhead and is not a production capacity guarantee.

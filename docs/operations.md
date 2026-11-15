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
telemetry provider is installed. HTTP analytics and notification rules are a
separate implementation; see [the observability review](reviews/2026-11-15-005-observability.md).

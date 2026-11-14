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

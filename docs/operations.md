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

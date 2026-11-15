# HTTP analytics setup

Open **Servers → a server → HTTP traffic → Set up HTTP analytics**. Discovery is read-only. Connect a discovered JSON log without a restart, or choose **Review setup** to configure logging.

Automatic setup supports root-running, CLI-configured Traefik containers owned by a single Docker Compose file, including external Coolify proxies and Dokku's managed Traefik. Python 3, Docker Compose, systemd and logrotate must already exist. Unsupported sources explain why; advanced connections still accept existing Traefik/Caddy JSON logs. No packages are installed automatically.

The reviewed action backs up the original Compose file, changes access logging and its bind mount, validates Compose, and recreates only the selected proxy with `--no-deps --pull never --no-build` against the same local image ID. Applications behind that proxy may briefly lose connections. Existing health checks and previously reachable published TCP listeners are checked before success. Failure restores the original configuration and recreates the proxy; failed rollback is reported explicitly. Startup checks do not verify every application route.

Signed reviews expire after 15 minutes and bind server, container identity and configuration digest. Host changes invalidate the review. Configuration contents and secrets never reach the browser. A private systemd operation continues if RailDock or SSH disconnects. Its result reconciles the dashboard on the next visit. Original Compose backups and results are root-private under `/var/lib/dokku/raildock-http`; temporary plan files are removed on exit.

For Dokku, the native `traefik-template-source` hook preserves logging across regeneration. Existing third-party hooks are refused. External managers can overwrite their Compose source later; RailDock does not silently fight them. Detect and review again if logging is lost.

## Storage and privacy

Managed logs use `/var/log/raildock-http/<container>/access.log`. The proxy retains StartUTC, RequestHost, DownstreamStatus, DownstreamContentSize and Duration, plus Traefik's level/message/time metadata. IPs, headers and paths are excluded at source. A 100-line asynchronous buffer reduces blocking. There is no extra agent. Logging adds per-request serialization and disk I/O proportional to traffic.

An hourly systemd timer runs logrotate: rotate at 25 MiB, keep two rotated files, signal Traefik to reopen, no compression. Files can exceed the threshold between checks. This raw-log policy is separate from aggregate retention (1–30 days). Disabling collection stops ingestion, not proxy logging or rotation.

Collectors retain bounded reads and begin at EOF on first enable; earlier traffic is not backfilled. Rotation can leave a gap, reported by the dashboard alongside backlog. Disabled or unavailable collection is not presented as measured zero traffic.

## Manual recovery

Stop `raildock-http-<container>.timer`, review the original Compose backup against the current configuration, restore the intended logging settings, and recreate only that proxy. For Dokku, also remove RailDock's custom hook from `plugins/enabled/raildock-http` before regeneration. Never blindly overwrite newer routing changes with an old backup.

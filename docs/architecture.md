# Architecture


RailDock ships as a single Docker image that runs nginx, Puma, and background workers under supervisor. The Rails backend talks to the deployment engine over SSH. The React frontend talks to Rails over a same-origin `/api` path and WebSocket `/cable`.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────────────────┐
│   React 19  │────▶│  Rails 8    │────▶│     Dokku (SSH or local)    │
│   (Vite)    │◀────│  PostgreSQL │◀────│   postgres/redis/mysql/     │
│             │ WS  │  Solid Q/C  │ SSH │        mongo plugins        │
└─────────────┘     └─────────────┘     └─────────────────────────────┘
       │                  │                       │
       ▼                  ▼                       ▼
  Traefik (80/443)   PostgreSQL         User App Containers
```

Key backend pieces, all real code:

- `DokkuEngine` + `HostEngine` — the SSH-driven deployment engine: a dual connection pool (restricted `dokku` user + `root` user) with thread-local session reuse, automatic retry, and keepalive.
- `ManifestReconciler` — desired-state vs. actual-state diff-and-apply loop in 6 ordered phases, using 3 severity tiers (reload/restart/redeploy) and topological dependency ordering.
- `ManifestParser` / `ManifestGenerator` — two-phase variable resolution (parse-time secrets + runtime infrastructure references) with round-trip export support for `raildock.toml`.
- `DeploymentSequenceJob` — orchestrates multi-service deploys by dependency order, cancelling dependents of failed deployments.
- `DeploymentJob` — full lifecycle with port auto-detection, external proxy label injection, post-deploy credential propagation across linked services, and real-time log streaming.
- `ProjectNetworkManager` — per-project Docker networks with DNS alias-based service discovery and automatic env var injection.
- `ExternalProxyConfigurator` + `TraefikLabelBuilder` — disables the engine's managed proxy and generates Traefik HTTP/HTTPS router labels with configurable entrypoints and cert resolvers.
- `LogsChannel`, `DeploymentsChannel`, `TerminalChannel` — real-time SSH streaming over ActionCable.
- `RunDueBackupsJob`, `RunPostgresPitrJob`, `RunRecoveryDrillsJob` — scheduled backups, WAL archiving, and recovery drills via Solid Queue recurring tasks.


[Back to the README](../README.md)

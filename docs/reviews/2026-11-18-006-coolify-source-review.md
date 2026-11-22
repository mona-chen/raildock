# Coolify source review: what RailDock should adopt

Reviewed 18 November 2026. Coolify main pinned to `10d1968f370a341bc0c1c5bd444e450ff17ad921` (17 November 2026). RailDock comparison at `96c0788`.

## Scope and confidence

This is a source-level comparative review, not a production benchmark, penetration test, or full audit of either product. I cloned Coolify, read the selected implementations and relevant test cases, and compared them with RailDock's existing paths. Coolify main may contain features absent from installed releases. I did not run Coolify or its tests. Sentinel runs from a separate image: the Coolify integration was reviewed, not the internals of the agent. Performance estimates below are architectural expectations, not measurements.

The recommendation is to keep RailDock's Rails/React control plane, Railway-style canvas, and Dokku deployment engine. Learn Coolify's operational contracts, not its entire stack or every feature.

## 1. Make update outcomes durable, diagnosable and independently verifiable — immediate

Coolify saves an automatic update attempt before replacement. The new process checks the running version against that target, reports results, claims completion to avoid duplicate notifications, and restores the saved attempt if notification queueing fails. Upgrade status includes timestamps; stale/running status has expiry rules.

Sources: [app/Actions/Server/UpdateCoolify.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Actions/Server/UpdateCoolify.php); [app/Services/AutoUpdateNotifier.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/AutoUpdateNotifier.php); [app/Services/CoolifyUpgradeStatus.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/CoolifyUpgradeStatus.php).

RailDock already has an independent systemd updater, an installation lock, verified backup, health checks and immutable-image rollback. Keep these. The current `HostUpdateRunner#status` returns `scheduled` when its status file cannot be read, with no age limit, and the status file has no timestamps or detailed failure reason. A lost operation can look active indefinitely. Health alone is also weaker than verifying which build actually started. The PostgreSQL client mismatch fixed in `96c0788` is a concrete example of a phase-specific failure that should reach the UI.

Adopt: operation id, created/updated timestamps, target and previous image digests, phase, bounded redacted reason code, host service exit status, running-build verification, and a startup/recurring reconciler. Notify on update start/failure/recovery; expose a bounded redacted log in Settings rather than sending people to SSH. Distinguish backup verification, migration failure, health failure and cleanup warnings. A container image rollback does not undo schema migrations: define migration compatibility and recovery explicitly; never automatically overwrite the database after new writes.

Acceptance: kill the host updater at each phase; status becomes interrupted rather than scheduled forever. New process confirms exact target build. Backup failure never replaces the app; rollback failure is unmistakable.

Cost: low recurring overhead; integration tests need disposable Docker/PostgreSQL.

## 2. Strengthen secret redaction before adding more logs — immediate

Coolify deployment log entries pass commands and output through a shared redactor before storage. Its redactor accepts known and locked secret values, handles structured sensitive keys, and suppresses output on redaction failure.

Sources: [app/Models/ApplicationDeploymentQueue.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Models/ApplicationDeploymentQueue.php); [app/Services/Security/SensitiveDataRedactor.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/Security/SensitiveDataRedactor.php).

RailDock's `LogRedactor` recognizes a small set of token, assignment and HTTP basic-auth patterns. Synthetic checks confirmed that an arbitrary `APP_KEY` value and a password in `postgres://...` remain visible. This is a coverage gap; this review did not establish that production secrets have actually leaked. `Deployment#append_log_chunk!` and serialization already call the redactor, so improve that boundary rather than adding disconnected UI masking.

Adopt: deployment-scoped known-secret sets, runtime/reference-resolved secrets, URL scheme coverage, nested structured redaction, streaming chunk-boundary handling, redaction at persistence and export, and clear fail-closed behavior. Avoid replacing every short normal word: locked short secrets need a deliberate handling policy. Test ANSI, escaped/encoded forms and split chunks with synthetic credentials. Do not claim masking prevents malicious builds from exfiltrating secrets.

Cost: modest string-processing overhead; bound chunks and avoid rereading every secret for each log line.

## 3. Separate container state, readiness and coverage — immediate

Coolify centralizes resource health aggregation: running, restarting, starting, mixed failed replicas and unavailable health checks do not all collapse into a green running badge. Its Sentinel state hash includes health and restart counts, while excluding changing metric values; unchanged pushes need not enqueue full reconciliation every minute.

Sources: [app/Services/ContainerStatusAggregator.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/ContainerStatusAggregator.php); [app/Http/Controllers/Api/SentinelController.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Http/Controllers/Api/SentinelController.php); [app/Livewire/Project/Shared/HealthChecks.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Livewire/Project/Shared/HealthChecks.php).

RailDock has a small service status enum and independent metric collection. `MetricsSamplerJob` currently selects `<app>.web.1` or one datastore; it does not represent every worker/replica. The network-flow collector's broader namespace coverage must not be mistaken for full resource-metrics coverage.

Adopt: per-process/replica identity with container incarnation, desired versus observed replica counts, health/readiness, restart count deltas and last successful observation. Preserve unavailable as unknown. Aggregate healthy/degraded/starting without treating an intentionally stopped worker as a crash. Present a concise service summary with an expandable process breakdown. Let Dokku remain the authority for deploy checks and promotion; do not reproduce Coolify's Docker rolling deploy engine.

Acceptance: web healthy + worker crashing displays degraded; collector outage displays unknown/stale; replacement containers do not create counter spikes. CPU units and memory denominators remain explicit.

Cost: small incremental cost when Docker inventory/stats are batched; database cardinality rises per replica. Measure first.

## 4. Make notification delivery a first-class subsystem — next

Coolify has channel adapters for email, webhook, Slack, Discord, Telegram and Pushover. Webhooks are separate queued jobs with retry policy and send-time URL validation. Team notifications have resource-based throttling and release throttle claims on sending errors.

Sources: [app/Notifications/Channels/WebhookChannel.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Notifications/Channels/WebhookChannel.php); [app/Jobs/SendWebhookJob.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Jobs/SendWebhookJob.php); [app/Models/Team.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Models/Team.php); [app/Contracts/ThrottledNotification.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Contracts/ThrottledNotification.php).

RailDock already has sustained windows, incident transitions, email destinations, recovery and retries. Do not rebuild those. `MonitoringNotificationJob` currently uses email only and one incident-level delivery status, which cannot accurately describe several independent destinations.

Adopt: one incident event plus per-channel/per-destination delivery records, stable event ids, explicit test delivery, attempts, last failure and retry action. Start with generic signed webhooks plus one chat adapter. Preserve severity/event/resource filters and separate triggering from delivery. External endpoints require response limits, timeouts, redirect policy, DNS rebinding defenses and secret URL redaction; allow internal destinations only by explicit operator policy.

Acceptance: email succeeds while chat fails without resending email; recovery is delivered once; disabled channels do not consume a throttle window. A successful SMTP handoff is not proof of inbox delivery.

Cost: low idle overhead, bounded burst work; isolate network delivery from collectors and deployments.

## 5. Observe the scheduler and collectors themselves — next

Coolify records scheduled occurrences separately from execution, supports bounded catch-up and stale publication recovery, and checks missing backups independently of backup jobs.

Sources: [app/Services/ScheduledJobDeliveryService.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/ScheduledJobDeliveryService.php); [app/Jobs/CheckMissingDatabaseBackupsJob.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Jobs/CheckMissingDatabaseBackupsJob.php).

RailDock has queue separation, backup coalescing, recurring jobs, data-safety reporting and stale-deployment reconciliation. Those are valuable foundations. Add independent proof that scheduling and sampling continue: last tick, oldest ready-job age, worker heartbeat, last successful sample, missed backup deadlines, and notification delivery age.

Adopt a small instance diagnostics page with collector heartbeat/lag and queue health. Recover missed backup occurrences idempotently; do not blindly replay arbitrary scheduled destructive commands. Distinguish host unreachable from collector worker stopped. An internal monitor cannot alert while the entire instance is down: provide an optional external dead-man check endpoint/integration.

Cost: low if indexed and bounded; no per-request full queue scans.

## 6. Scale observability without forcing an agent — deliberate architecture decision

Coolify starts a Sentinel container with local persistent storage, Docker socket and host PID access. It passes explicit collection interval/retention options and optional traffic configuration. Metrics clients batch reads, cache results, coalesce requests and cool down unreachable servers. State pushes and historical metrics are separate paths.

Sources: [app/Actions/Server/StartSentinel.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Actions/Server/StartSentinel.php); [app/Services/SentinelMetricsClient.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/SentinelMetricsClient.php); [app/Services/SentinelTrafficClient.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/SentinelTrafficClient.php).

RailDock already batches Docker samples per host, uses short shared snapshots and bounds TCP collection. Our earlier measurement on tween showed approximately 0.4 CPU seconds per TCP collection across 58 running containers; that measured neither all Rails/SSH overhead nor a Sentinel alternative. There is no evidence here that switching to an agent automatically reduces total resource cost.

Adopt now: standardized sample envelopes (`sampled_at`, source, coverage, partial/error reason, reset/lag metadata), bounded queries, cached negative results and read coalescing. Consider an optional agent only when fleet/SSH measurements justify it. Keep SSH-only supported, authenticate per host, rotate/revoke tokens and version the telemetry protocol. Docker socket plus host PID access is a significant privilege boundary, not a harmless lightweight plugin.

Cost: a resident agent has unavoidable RAM/CPU/disk and update maintenance. Benchmark before proposing default installation.

## 7. Expand HTTP analytics selectively and keep its mathematics honest — next/later

Coolify configures proxy access logs and exposes status, methods, paths, browsers, devices, bots and geography with top-N/sampling/retention controls. Its client prefers resource-scoped routes. Its PHP cross-source aggregator sums visitor estimates and takes maximum percentile values, explicitly flagging these as approximate; that is not a mathematically exact global p95 or deduplicated visitor count.

Sources: [app/Actions/Server/StartSentinel.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Actions/Server/StartSentinel.php); [app/Services/SentinelTrafficClient.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/SentinelTrafficClient.php); [app/Services/TrafficAnalyticsAggregator.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/TrafficAnalyticsAggregator.php).

RailDock already has proxy setup, bounded log reading, minute/hour rollups, service attribution, histogram buckets, retention and failure/lag state. Consolidate reliability before adding dimensions. Show coverage and collection status beside charts, and compare request rate, error rate and latency with deploy events. High traffic is not inherently hostile.

Adopt: useful application/domain/status/method breakdowns, response bandwidth, limited normalized paths, explicit top-N overflow, clear missing/disabled/stale states. If adding visitors, merge sketches and label estimates. For percentiles merge histograms/sketches rather than average or maximize precomputed p95s. Browser/OS/bot classification belongs in bounded asynchronous processing. GeoIP and full IP retention should be opt-in, not defaults.

Cost: cardinality and log throughput matter more than chart count. GeoIP refreshes, user-agent parsing and high-resolution long retention require separate load/storage measurements. No packet inspection or automatic blocking is needed for ordinary traffic analytics.

## 8. Improve deployment diagnosis and pending-change review — next

Coolify stores structured log fields (timestamp, type, command, hidden/debug, order/batch), has a persistent deployment-history/log workspace, and surfaces configuration diffs and missing required variables. Its rolling deployment path distinguishes readiness failure from old-container cleanup failures; cleanup failure does not necessarily fail a successful new deployment.

Sources: [app/Models/ApplicationDeploymentQueue.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Models/ApplicationDeploymentQueue.php); [resources/views/livewire/project/application/deployment/show.blade.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/resources/views/livewire/project/application/deployment/show.blade.php); [app/Livewire/Project/Shared/ConfigurationChecker.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Livewire/Project/Shared/ConfigurationChecker.php); [app/Jobs/ApplicationDeploymentJob.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Jobs/ApplicationDeploymentJob.php).

RailDock has streaming sequence numbers, search/follow controls, cancellation callbacks, manifests and drift review. Keep these. Add typed phase events alongside raw build output: prepare, source, build, release, readiness, routing, cleanup. Store bounded append-only chunks rather than repeatedly rewriting a growing log string. Use resumable sequence-based reads and role-aware redacted export.

UX: a compact stage strip, failing-stage summary, duration, revision, explicit follow state and relevant logs. Offer a full-page deployment workspace when the canvas panel is cramped, preserving canvas context. Before deploy, show changed field names, unresolved variables and whether a restart/build is needed. Never expose secrets in role-restricted diffs.

Cost: low-to-moderate engineering effort; chunk retention and cursor APIs avoid unbounded payloads.

## 9. Treat outbound integrations as one security policy — next

Coolify's safe URL rule validates schemes and resolved addresses, blocks metadata/loopback targets, supports deliberate private-network exceptions, and builds DNS-pinned HTTP options with redirects disabled. Its webhook sender repeats checks at delivery time.

Sources: [app/Rules/SafeWebhookUrl.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Rules/SafeWebhookUrl.php); [app/Jobs/SendWebhookJob.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Jobs/SendWebhookJob.php).

Adopt the policy boundary for future notification webhooks and audit current repository/backup/integration URL consumers individually. Do not copy a blanket ban on private networks: self-hosted Git, SMTP and S3-compatible storage are legitimate RailDock use cases. Classify integration purpose and require explicit internal-target policy. This review did not fully audit RailDock SSRF exposure, so this is a targeted audit recommendation, not a confirmed exploit claim.

Cost: small DNS/network overhead with timeouts and caching; implement rebinding protection at the actual client.

## 10. Build-server separation and preview environments — later

Coolify supports build-server selection with slot/fallback rules, registry-mediated image delivery and different execution paths for additional runtime servers. Its preview webhook trust logic verifies source, target and webhook repository identities and makes fork previews an explicit policy.

Sources: [app/Jobs/ApplicationDeploymentJob.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Jobs/ApplicationDeploymentJob.php); [app/Http/Controllers/Webhook/Concerns/ValidatesPreviewDeploymentRepository.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Http/Controllers/Webhook/Concerns/ValidatesPreviewDeploymentRepository.php); [tests/Feature/Webhook/PreviewDeploymentForkTrustTest.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/tests/Feature/Webhook/PreviewDeploymentForkTrustTest.php).

RailDock's environment copies are deliberately staged and have fresh instance identities. Preserve that invariant. Add previews only with isolated domains/networks/storage, separate credentials, untrusted-fork protection and TTL/PR-close cleanup. Environment-scoped variables should precede previews. Add dedicated build servers when production builds compete with serving traffic, via supported Dokku build facilities and immutable registry digests, not another homegrown scheduler.

Cost: builds are genuinely CPU/RAM intensive; previews multiply running resources. Both need quotas, concurrency limits and clear cost visibility.

## 11. Optional log drains and image scanning — later, explicit resource budgets

Coolify configures Fluent Bit log drains and can use Docker's CloudWatch driver. Its image-security subsystem uses bounded scanner containers, CPU/memory/time/output caps, stored findings, and configurable gates with explicit handling when scanning is unavailable.

Sources: [app/Actions/Server/StartLogDrain.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Actions/Server/StartLogDrain.php); [app/Services/ImageScan/ScannerCommands.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/ImageScan/ScannerCommands.php); [app/Services/ImageScan/SecurityGate.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Services/ImageScan/SecurityGate.php).

RailDock should support exporting structured runtime logs to an operator-selected system instead of becoming an unbounded log warehouse. An optional drain needs buffering/disk caps, retry/backpressure and safe config validation. For image scanning, start with digest-keyed asynchronous reports and useful remediation; enforce deployment gates only when explicitly configured. Dependency/CVE scanning and malware detection answer different questions.

Cost: log export is continuous bandwidth/disk/CPU; SBOM generation, image extraction and vulnerability DB updates can be expensive. Do not install or enable these silently. Present limits and benchmark with the operator first.

## 12. Adopt a design contract, not Coolify's appearance — immediate foundation

Coolify documents type/control scales, surface tokens, opaque overlays, sentence case, status color semantics and component anatomy. Its deployment view implements keyboard search, manual-scroll-aware following and responsive history/log layout; its configuration checker makes pending changes visible.

Sources: [DESIGN.md](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/DESIGN.md); [resources/views/livewire/project/application/deployment/show.blade.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/resources/views/livewire/project/application/deployment/show.blade.php); [app/Livewire/Project/Shared/ConfigurationChecker.php](https://github.com/coollabsio/coolify/blob/10d1968f370a341bc0c1c5bd444e450ff17ad921/app/Livewire/Project/Shared/ConfigurationChecker.php).

RailDock already has shared settings components but still has hard-coded visual values across feature pages. Consolidate spacing, typography, surfaces, button hierarchy, icon sizes and focus treatment into tokens. Keep the Railway-like architecture canvas as the navigation anchor. The paper connection note can remain a deliberate exception without becoming the design language of monitoring/settings. Make collection state and configuration actions discoverable with a consistent toolbar instead of adding floating cards.

A service detail should answer: Is it healthy? What changed? Which process is consuming resources? What should I do next? A server detail should show used/total/available memory and disk, CPU capacity, current pressure, coverage and last sample before history charts. Prefer progressive disclosure to copying every Coolify settings tab.

## What not to copy

- Do not replace Dokku with Coolify's direct Docker deployment orchestration. Their ownership models differ.
- Do not grow one giant deploy job: Coolify's reviewed `ApplicationDeploymentJob.php` is 7,483 lines; RailDock's is already 1,392. Extract coherent phases/services and a persisted operation model before adding more orchestration.
- Do not assume a richer monitoring page means application tracing or profiling. The reviewed source does not establish full OpenTelemetry trace support or packet-level attack detection.
- Do not call container-running state application health, missing samples zero load, or summed per-host visitors globally unique people.
- Do not weaken RailDock's verified destruction snapshots, last-copy retention, PITR chains and restore-drill requirements to match another product's simpler backup flow.
- If copying implementation code rather than ideas, review Coolify's Apache-2.0 license and preserve required notices/attribution. This report copies no implementation code.

## Suggested delivery order

| Order | Deliverable | Why first | Proof required |
|---|---|---|---|
| 1 | Secret-aware redaction and leak regression tests | Protect logs before expanding visibility | Synthetic values absent from stored/streamed/exported logs |
| 2 | Update lifecycle reconciliation and actionable errors | Directly addresses repeated failed updates | Disposable-host tests across interruption, backup, migration, replacement, rollback |
| 3 | Per-process metrics and honest health aggregation | A healthy web process cannot hide a broken worker | Mixed replicas, restarts, stale and partial telemetry tests |
| 4 | Delivery ledger + signed webhooks + instance diagnostics | Make alerts trustworthy | Independent channel failures/retries and missed-worker detection |
| 5 | Consistent server/service/deployment workspaces | Make the collected information usable | Keyboard/mobile/overflow QA and real failure-state browser tests |
| 6 | Analytics depth, environment-scoped variables, previews | Builds on reliable operations | Cardinality/load budgets and isolation tests |
| 7 | Optional agent, build hosts, drains and scanning | Useful at scale, not free | Measured overhead, quotas, recovery and upgrade contracts |

The best lesson is operational closure: every action has a durable outcome, every status explains its evidence, and every failure offers a clear next step. Adding features before closing those loops would make RailDock more complicated without making deployment easier.

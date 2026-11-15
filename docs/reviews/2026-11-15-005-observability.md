# Resource observability and traffic analytics

## Verified gaps and changes

RailDock's old metrics charts were not comparable to Coolify's server page:
they plotted the primary application container, not the whole server. Collection
ran every five minutes, Git apps without `docker_image` were previously skipped,
and the shared API camelized keys while history charts read snake case. That last
mismatch discarded CPU limits, memory bytes, network counters and block I/O in the
frontend. Failed host SSH commands also became zeroes.

Resource collection now includes whole-host CPU, available-memory usage, root disk
usage, one-minute load, uptime and network counters. Host collection uses one SSH
round trip, a one-second kernel CPU counter delta, a nonblocking PostgreSQL advisory
lock and a ten-second cache shared between processes. It holds no row lock or
transaction across SSH. Host live samples persist, so closing the view does not
discard them. Application live readings are plotted while the panel is open;
background service and host history runs every minute. Application CPU charts use
Docker's native units (100% = one core), preserving fractional values and avoiding
misleading rescaling when limits change.

Background Docker sampling is batched per host (one stats process, one inspect
batch), rather than launching stats/SSH per service. Only recognized service
container identities persist. Application coverage remains the primary web or
datastore container: worker/replica aggregation needs process-scoped identity and
restart-aware counters before it can be presented honestly.

Settings → Observability controls host and application collection independently,
and history retention from 1–90 days. Disabled collection retains history until
expiry. Cleanup still runs while collection is disabled. History API windows are
bounded to seven days; host responses downsample longer windows and are scoped to
the caller's authorized server. Shortening retention permanently expires samples.

## Competitor research (15 November 2026)

- [Coolify Sentinel](https://coolify.io/docs/core/observability/monitoring/sentinel)
  separates status reporting from optional metric history. Metrics collection uses
  server agents, and retention/collection rates are configurable.
- [Coolify traffic analytics](https://coolify.io/docs/core/observability/monitoring/traffic-analytics)
  reads proxy JSON access logs and stores aggregate rollups; this is separate from
  CPU/memory history. Traffic settings include bounded top lists and retention.
- [Railway observability](https://docs.railway.com/observability) brings metrics and
  logs together and supports configurable monitoring alerts. Its
  [resource metrics](https://docs.railway.com/observability/metrics) are distinct
  from application instrumentation such as request latency and business metrics.
- [Dokploy monitoring](https://docs.dokploy.com/docs/core/monitoring) documents
  configurable host/container refresh rates, retention and host threshold alerts.
  Its [Logs & Metrics](https://docs.dokploy.com/docs/core/logs-and-metrics) uses
  Vector/cAdvisor to export to external monitoring providers.

## Requests and incidents: implementation boundaries

Do not ship charts that label Docker network bytes as HTTP requests or attacks.
Traffic analytics requires real proxy access logs, correct host/service mapping,
log rotation handling, trusted client-IP boundaries and measured collector cost.
External proxies remain operator-owned; enabling analytics must not silently
restart or rewrite someone else's Traefik/Caddy instance.

The HTTP layer now uses a bounded per-host reader over authenticated SSH, minute/hourly rollups and organization-scoped monitoring policies. It does not forward raw request streams into Rails. Keep
request counts/statuses exact, bound top-N cardinality, and mark sampled latency or
approximate unique visitors explicitly. Percentile aggregates must use mergeable
histograms; averaging per-minute p95 values is mathematically wrong. Record lag,
dropped events and log rotation/reset conditions in the UI.

Default privacy: discard query strings, headers and bodies; anonymize client IPs
before persistence. Optional IP retention and offline GeoIP require explicit
settings. Collection, hourly/daily retention, top-N caps and sampling should be
independent. Do not add packet capture, request-body inspection or per-request
GeoIP database lookups to the default path.

Notifications should use sustained windows, recovery transitions, hysteresis,
deduplication and delivery retries. Start with host unavailable, stale collector,
CPU/memory/disk pressure, restart loops, and backup/deploy failures. Request/error
spikes and suspicious path patterns follow once request collection is reliable.
Scope channels and recipients to the organization. Show pending/failed delivery;
SMTP configuration alone is not proof that a notification arrived.

An LFI-looking path is a suspicious request, not evidence of compromise. HTTP
access logs cannot observe port scans against non-HTTP ports; those need explicit
host/firewall telemetry or integrations such as CrowdSec/Fail2ban. Avoid automatic
blocking until false positives, trusted proxies and recovery controls are proven.

## Cost and validation

The current changes add no resident agent, public port, packet inspection or
external telemetry vendor. A background host sample reads small kernel files and
root filesystem statistics; Docker work is batched. No production load benchmark
has been performed, so this is a bounded implementation, not a proven CPU budget.
At one-minute background intervals there are at most 1,440 samples per resource
per day; an actively viewed host can retain up to 8,640 samples/day. Retention is
the principal storage control. Long-term high-resolution metrics, large host
fleets, full IP/user-agent analytics, geolocation and deeper inspection require a
separate measured capacity review before enabling them by default.

Tests cover retention/disable behavior, fractional readings, failed/incomplete
host samples, batch container parsing, API key normalization and failed settings
saves. A local sample-data browser review checks chart layout and live pause.
The host sampling script was smoke-tested in a restricted local Linux container.
Real SSH-host collection, external proxy integration and production load still
require end-to-end operational validation; no production updater or proxy change
was executed during this work.

Implementation status: opt-in Traefik/Caddy file collection, minute/hourly history, HTTP/application breakdowns, organization notification rules, additional email destinations, deduplication and recovery are implemented. Optional geography, unique-visitor analytics, device fingerprinting, packet capture and automatic proxy reconfiguration remain outside this implementation. See operations.md for setup, limits and retention.

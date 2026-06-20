---
date: 2026-06-20
topic: smart-import-realtime-operations
---

# Smart Repository Import and Realtime Operations

## Summary

RailDock will turn a selected repository and branch into a reviewable canonical RailDock topology before creating anything. The same release will make deployment progress and service state continuously trustworthy, while consolidating the service panel around one operational status and one set of actions.

---

## Problem Frame

Operators currently choose a builder before RailDock has inspected the repository. That forces them to understand implementation details the repository may already declare in `raildock.toml`, `railway.toml`, `railway.json`, `app.json`, Dockerfiles, Procfiles, or monorepo structure. Multi-service topology and deployment hooks can consequently be flattened into an inappropriate single-service choice.

Long-running operations also use inconsistent update mechanisms. Deployment list state, detailed logs, canvas state, manifests, activity, backups, and runtime status may update through different combinations of websocket events, polling, or remounting. Operators cannot reliably tell whether the screen is current, and authenticated Git URLs can leak into captured build output.

---

## Actors

- A1. Platform operator: connects a repository, reviews discovered topology, deploys it, and responds to failures.
- A2. RailDock discovery pipeline: inspects repository evidence and translates supported formats into canonical desired state.
- A3. Deployment runtime: applies the canonical state and emits durable, redacted progress events.

---

## Key Flows

- F1. Repository discovery
  - **Trigger:** A1 selects a repository and branch.
  - **Actors:** A1, A2
  - **Steps:** RailDock scans the selected revision, identifies manifests and conventional files, translates all supported declarations, resolves precedence, and presents the resulting topology with provenance, confidence, warnings, and conflicts.
  - **Outcome:** A1 understands what RailDock will create before any infrastructure changes.
  - **Covered by:** R1, R2, R3, R4, R5

- F2. Review and apply topology
  - **Trigger:** Discovery produces a valid candidate topology.
  - **Actors:** A1, A2, A3
  - **Steps:** A1 reviews services and shared resources, optionally overrides a specific field, confirms the import, and watches each resource move through queued, applying, deployed, or failed states.
  - **Outcome:** The canonical RailDock topology is stored and applied without silently dropping foreign-manifest intent.
  - **Covered by:** R6, R7, R8, R9

- F3. Observe and recover a deployment
  - **Trigger:** A deployment, restart, restore, manifest apply, or other long-running operation begins.
  - **Actors:** A1, A3
  - **Steps:** The operation appears immediately, logs stream without remounting, connection freshness is visible, durable state reconciles missed events, secrets are redacted, and failures contain an actionable diagnosis.
  - **Outcome:** A1 never needs to refresh or collapse a panel to learn the current state.
  - **Covered by:** R10, R11, R12, R13, R14

---

## Requirements

**Canonical discovery and translation**

- R1. Repository inspection must happen after repository and branch selection and before service creation.
- R2. Discovery must recognize native RailDock manifests, Railway manifests, `app.json`, Dockerfiles, Procfiles, build/runtime descriptors, and common monorepo roots.
- R3. Every supported input must translate into the same canonical RailDock desired-state model, including multiple services, databases, links, variables, volumes, health checks, build settings, lifecycle hooks, restart behavior, and source roots where declared.
- R4. Precedence must be explicit: a native RailDock manifest is authoritative; a supported foreign manifest supplies declared topology; conventional file detection only fills undeclared gaps; user overrides are last and remain visibly marked.
- R5. Conflicting manifests or unsupported fields must produce a reviewable conflict or warning. RailDock must not silently pick one, flatten a topology, or discard behavior.

**Creation and review experience**

- R6. Service creation must use a source → discovery → review → apply flow, with progressive disclosure rather than an up-front builder matrix.
- R7. The review must group discovered applications, workers, databases, schedules, storage, links, variables, checks, and hooks, with the source of each decision visible.
- R8. A repository with no topology manifest may fall back to a single detected service, but the detected runtime, builder, start command, port, and confidence must be shown before creation.
- R9. Builder override must remain available as an advanced per-service control and must warn when it contradicts repository evidence or the target server lacks the required capability.
- R9a. The default creation path must use plain language, require no knowledge of manifests or builders, and ask the operator only for decisions RailDock cannot safely infer.

**Realtime contract and operational safety**

- R10. Every long-running operation must emit a common event shape with operation identity, resource identity, status, monotonic sequence, timestamp, message, and optional redacted log chunk.
- R11. Realtime events must update visible cached state directly; durable API state must reconcile missed or out-of-order events, with bounded polling as a fallback when the live connection is unhealthy.
- R12. Deployment details and logs must remain live while open, including when the operator joins mid-deployment, changes tabs, collapses a row, reconnects, or receives multiple rapid chunks.
- R13. The UI must show whether data is live, reconnecting, or using fallback refresh, and must display the last confirmed update time without presenting connection state as deployment health.
- R14. Credentials and authenticated repository URLs must be redacted before persistence, broadcast, API serialization, copy, export, or display.

**Service panel and host capability**

- R15. The service panel must have one shared operational header for current state, source revision, active operation, freshness, and lifecycle actions; tabs must not repeat competing versions of these controls.
- R16. Overview must become a concise service summary and dependency surface; Deployments must own deployment history and live logs; Settings must own configuration; Logs must own runtime logs.
- R17. The deployment surface must keep the active operation visible, stream logs by default, preserve scroll-follow with an explicit pause when the operator scrolls away, and show actionable failure summaries without hiding raw output.
- R18. Supported builders requiring host binaries or daemons must be installed during RailDock install/update or reported as unavailable before deployment; unsupported choices must never fail only after an expensive build begins.

---

## Acceptance Examples

- AE1. **Covers R1-R5, R7.** Given a repository containing a multi-service Railway configuration plus hooks and a Dockerfile for one service, discovery presents the full translated topology, uses Dockerfile only for that service, and retains hook intent or flags a precise unsupported mapping.
- AE2. **Covers R4, R5.** Given both `raildock.toml` and `railway.toml`, the RailDock manifest is authoritative and the review states that the Railway file was detected but superseded; no duplicate resources are created.
- AE3. **Covers R8, R9.** Given a repository with only a Dockerfile, discovery recommends Dockerfile with high confidence; choosing Railpack remains possible only as an explicit override and is blocked before deployment when Railpack is unavailable.
- AE4. **Covers R10-R13.** Given an operator opens a deployment after it has started, the existing durable log appears first, new chunks append without duplication, status changes immediately, and reconnecting fills any gap without collapsing the row.
- AE5. **Covers R14.** Given Dokku echoes a GitHub installation-token URL, stored logs, websocket payloads, exported logs, and the UI contain a redacted URL and never the token.
- AE6. **Covers R15-R17.** Given the service panel is open on any tab, its header shows one current status and active operation; switching tabs does not create duplicate subscriptions or contradictory actions.

---

## Success Criteria

- An operator can connect an unfamiliar repository and accurately predict every resource and lifecycle behavior RailDock will apply without first knowing which builder to choose.
- A non-technical operator can complete the happy path by selecting a repository, reviewing a plain-language summary, and choosing Deploy; technical evidence remains available progressively.
- A multi-service foreign manifest reaches the same downstream reconciliation path as a native RailDock manifest, with provenance and loss warnings preserved.
- Active operations update without manual refresh or component remount, while websocket interruption degrades visibly and recovers automatically.
- Builder incompatibility and missing host capabilities are caught before build execution.
- No deploy output exposes repository credentials.

---

## Scope Boundaries

- RailDock translates supported platform manifests; it does not emulate proprietary secret stores, billing, or provider-specific runtime infrastructure.
- Ambiguous or lossy mappings require operator review rather than guessed semantics.
- The panel redesign covers the service operational workspace, not a wholesale redesign of project navigation or global account settings.
- Realtime covers stateful operations and operational feeds; high-frequency metrics may continue sampled polling where streaming adds cost without operator value.

---

## Key Decisions

- Canonical topology over builder selection: a builder is one field of one service, not the entry point to importing a repository.
- Evidence with provenance over hidden magic: automatic decisions remain visible and overridable.
- One realtime contract with durable reconciliation over independent per-tab subscriptions and unconditional polling.
- One service-panel owner for status and actions over repeated controls in header, Overview, and Deployments.

---

## Dependencies / Assumptions

- Connected Git providers can read repository trees for the selected branch without cloning code into the RailDock application container.
- Foreign lifecycle commands run only after translation into RailDock's explicitly supported hook phases and safety model.
- Dokku remains the execution engine; RailDock owns discovery, canonicalization, capability checks, orchestration, and user feedback.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R3-R5][Technical] Define the exact translation coverage and loss policy for each supported foreign manifest version.
- [Affects R10-R13][Technical] Define event sequencing, snapshot reconciliation, and polling backoff within the current Action Cable and query-cache stack.

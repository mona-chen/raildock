---
title: Add railway.toml / railway.json manifest support
type: feat
status: active
created: 2026-06-20
target_repo: raildock
---

# Add `railway.toml` / `railway.json` manifest support

## Problem Frame

RailDock currently recognizes three manifest formats: `app.json` (Heroku/Dokku native), `raildock.toml`, and `raildock.json`. None of these match what users coming from Railway write in their repos. A developer who configured their app on Railway and is now moving to RailDock has to translate their `railway.toml` into `raildock.toml` by hand.

This is friction at the migration boundary. Adding native support for `railway.toml` and `railway.json` lets users drop the file into their repo, point RailDock at it, and proceed.

## Approach: detect → normalize → deploy

The architecture is the same shape as the existing `app.json` support. `ManifestParser.normalize_app_json` already takes a third-party format and produces the same internal `ManifestDesiredState` shape that `raildock.toml` produces. The reconciler and downstream code are format-agnostic — they only see the normalized service hash.

For Railway, we add **detect_format** routing for `railway.toml` / `railway.json` and a **normalize_railway** that builds the same service-hash shape. Everything downstream (schema validation, reconciler, deploy job, manifest controller) reuses the existing path with no changes.

This keeps the surface area small: one parser method, one controller heuristic, frontend hint is optional.

## Goals

- Parse `railway.toml` and `railway.json` into the same `ManifestDesiredState` shape `app.json` produces today.
- Map Railway's `[build]` and `[deploy]` sections onto RailDock's normalized service fields (builder, start_command, healthcheck, restart_policy, env).
- Let the existing schema validator and reconciler run unchanged against the normalized output.
- Surface `railway.toml` / `railway.json` as a recognized format in the manifest editor's reference list (documentation hint only — no functional change).

## Non-Goals (this iteration)

- **Generating `railway.toml` / `railway.json` from project state.** `ManifestGenerator` keeps emitting `raildock.toml` only. Same as `app.json`'s parse-only design.
- **Railway's `${{ secrets.X }}` / `${{ service.X }}` references in `[env]`.** They look syntactically similar to the `${{ shared.X }}` / `${{ linked.X.Y }}` markers RailDock already resolves, but their semantics differ (Railway's resolve against Railway's secret store / other services in the same project). Treat both `[env]` and `[vars]` as plain env strings in this iteration; flag unresolvable-looking markers in the parse warnings.
- **`buildCommand` / `preDeployCommand` execution.** RailDock has no pre-deploy hook system today. Skip these fields with a parse warning; revisit when RailDock exposes such hooks.
- **Cron, scaling, domain, storage mapping.** Railway's format has none — they're RailDock extensions. Out of scope.

## Key Technical Decisions

### Reuse the `app.json` template almost line-for-line

`normalize_railway` produces one service entry wrapping the parsed hash — same single-service shape as `normalize_app_json` at `manifest_parser.rb:122-170`. This means links, multi-service stacks, and per-service domains stay out of reach, with the same warning surfaced to the user.

### Format detection on filename first, content second

`detect_format` returns `:railway_toml` / `:railway_json` when the filename matches `railway.toml` / `railway.json` (case-insensitive). For auto-detection from raw content (used by `manifests_controller#update` when the user pastes without naming a file), check for the `build` or `deploy` top-level key as the heuristic for Railway's format vs. `buildpacks`/`formation` for `app.json`.

### Field mapping

| Railway field | RailDock normalized field | Notes |
|---|---|---|
| `[build].builder` | `service[:builder]` | Lowercase before passing to schema enum. Unknown values still pass through (schema rejects them); emit a parse warning. |
| `[build].buildCommand` | (skipped) | Warning: "buildCommand is not yet supported by RailDock" |
| `[deploy].startCommand` | `service[:start_command]` | String or array → joined with ` && `. |
| `[deploy].preDeployCommand` | (skipped) | Warning: "preDeployCommand is not yet supported by RailDock" |
| `[deploy].healthcheckPath` | `service[:checks][:path]` and `[:enabled] = true` | |
| `[deploy].healthcheckTimeout` | `service[:checks][:timeout]` | Railway's value is in seconds; RailDock's is also seconds per existing `app.json` mapping. |
| `[deploy].restartPolicyType` | `service[:restart_policy]` | Map `never`/`on-failure`/`always` → RailDock's enum. |
| `[env]` + `[vars]` | `service[:env]` | Merged. Nested objects (`{"value": ..., "generator": ...}`) follow the existing `app.json` generator pattern (`SECRET_GENERATED`). |

### Builder enum already includes Railway builders

`ManifestSchema::BUILDERS` at `manifest_schema.rb:21` already lists `railpack` and `nixpacks`. No schema change needed.

### No reconciler, controller, or schema changes

Because `normalize_railway` produces the same native service hash shape, every downstream consumer (schema validation, `ManifestReconciler`, `ManifestsController`, the deploy job) reuses the existing path with zero changes.

## Scope Boundaries

### In Scope

- `ManifestParser.detect_format` recognizes `railway.toml` / `railway.json` and a content-based heuristic for raw pastes.
- `ManifestParser.normalize_railway` builds the native service hash from a Railway hash.
- `ManifestsController#detect_format` heuristic extends to recognize Railway-shaped raw content.
- Frontend `ManifestEditorPage` lists `railway.toml` / `railway.json` as a recognized format in the sidebar reference (documentation only).
- Specs covering: parser happy paths for both formats, edge cases (unknown builder, array startCommand, `[env]` + `[vars]` merge), auto-detection from raw content.

### Deferred to Follow-Up Work

- **Round-trip generation** — emitting `railway.toml` / `railway.json` from project state. Same reasoning as `app.json`'s parse-only design.
- **`buildCommand` / `preDeployCommand` execution** — needs a RailDock-side hook system before they can do anything useful. Surfaced as a parse warning for now.
- **Custom config-file path per service** — would need a `Service.config_file_path` column and a Git-source-driven sync. Out of scope.
- **`[env]` Railway-only references** — `${{ secrets.X }}`, `${{ service.X }}`, `${{ volume.X }}` are Railway-platform-specific resolvers. RailDock doesn't have an equivalent. Treat them as opaque strings with a parse warning.

### Outside this product's identity

- Becoming a Railway-compatible runtime. We parse the config file format; we don't emulate Railway's secret store, service mesh, or volume primitives.

## High-Level Technical Design

Small, well-patterned addition. No diagrams needed — the implementation follows the existing `app.json` template almost line-for-line. The decision worth highlighting is **single-service wrapper** (same as `app.json`), which is the conceptual hinge.

```
railway.toml ──┐
railway.json ──┤
               ├──► ManifestParser.normalize_railway ──► ManifestDesiredState
               │                                           (services: [...one entry])
               │     ┌── builder (lowercased)
               │     ├── start_command (joined from array)
               │     ├── checks { enabled, path, timeout }
               │     ├── restart_policy
               │     └── env (merged [env] + [vars])
               │
               ▼
   (existing schema validation, reconciler, deploy job — all unchanged)
```

*Directional guidance for review, not implementation specification.*

## Implementation Units

### U1. Extend `ManifestParser` with Railway detection and normalization

**Goal:** `ManifestParser` recognizes `railway.toml` and `railway.json`, parses them, and produces the same `ManifestDesiredState` shape `app.json` produces.

**Files:**
- `backend/app/services/manifest_parser.rb` — extend `detect_format` with two new return values (`:railway_toml`, `:railway_json`); add `normalize_railway` method; dispatch in the `normalize` switch. Set `format_detected` to `"railway.toml"` or `"railway.json"`.
- `backend/spec/services/manifest_parser_spec.rb` — new `context 'with railway.toml'` and `context 'with railway.json'` blocks.

**Approach:** Mirror `normalize_app_json`. Single service hash with sensible defaults where Railway doesn't carry an equivalent field (name defaults to `"app"`, source.repo blank if not provided).

**Test scenarios:**
- `railway.toml` with `[build]` and `[deploy]` blocks parses to one service with correct builder/startCommand/healthcheck/restart-policy mapping
- `railway.json` with the same shape parses equivalently (TOML/JSON parity)
- `filename:` arg drives format detection regardless of content
- Auto-detect from raw content: a `{ "build": {...}, "deploy": {...} }` JSON is recognized as `railway.json`
- An unknown builder value (`"Bazel"`) lands in the service hash with a parse warning (still passes through; schema will reject downstream)
- An array `startCommand` is joined with ` && ` into one string
- `[env]` and `[vars]` both present are merged into `service[:env]` with `[vars]` taking precedence on key conflict
- `buildCommand` and `preDeployCommand` are skipped with parse warnings
- Resulting service hash uses the same key names (`start_command`, `restart_policy`, `checks`) as the `app.json` output

**Verification:** All existing parser specs still pass; new Railway specs pass.

### U2. Extend manifest controller auto-detection to recognize Railway content

**Goal:** When a user pastes raw Railway content without specifying a format, the controller picks `railway.toml` / `railway.json` correctly.

**Files:**
- `backend/app/controllers/api/manifests_controller.rb` — `detect_format` (line 130) extends its JSON-shape heuristic to recognize `{ build, deploy }` as `railway.json` and `[build]` / `[deploy]` sections as `railway.toml`.

**Approach:** JSON check first: starts with `{` AND contains top-level `build` or `deploy` keys → `railway.json`. TOML check: contains `[build]` or `[deploy]` section → `railway.toml`. Existing `app.json` and `raildock.toml` checks remain. Order of checks matters; Railway must be checked before `raildock.json` if both have `{` start.

**Test scenarios:**
- A pasted `{ "build": { "builder": "railpack" } }` is detected as `railway.json`
- A pasted `[build]\nbuilder = "railpack"` is detected as `railway.toml`
- Existing `app.json` and `raildock.toml` detection still works

**Verification:** Controller specs cover the four-format auto-detection matrix.

### U3. Frontend manifest editor lists Railway as a recognized format

**Goal:** Users see `railway.toml` and `railway.json` as recognized formats in the manifest editor's reference panel.

**Files:**
- `app/src/pages/ManifestEditorPage.tsx` — extend the "Formats" list (line 234) with the two new entries, mirroring the existing `raildock.toml` / `app.json` rows.

**Approach:** Pure additive UI — two new rows. This is documentation, not a functional change; the parser handles Railway content regardless of whether the user sees it listed.

**Test scenarios:**
- TypeScript compiles; the new rows render in the sidebar
- Existing UI behavior unchanged

**Verification:** Frontend build passes; manual smoke in the dev server.

### U4. Spec coverage across parser and controller

**Goal:** Lock down the new behavior with focused specs.

**Files:**
- `backend/spec/services/manifest_parser_spec.rb` — Railway TOML/JSON parser specs (U1).
- `backend/spec/requests/api/manifests_controller_spec.rb` — auto-detection coverage (U2).

**Approach:** Specs follow the existing `context 'with <format>'` pattern. Each parser spec exercises one happy-path + one edge-case (unknown builder, array startCommand, env/vars merge, skipped build/predeploy commands with warnings). Controller spec covers the four-format auto-detection matrix.

**Test scenarios:** Enumerated per-unit above.

**Verification:** Spec suite passes; coverage delta for the new paths is non-trivial.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Railway adds new fields to `[deploy]` that RailDock silently drops | Parse warnings surface unknown top-level and section keys; users see them in the editor before deploy. |
| Users expect `buildCommand` / `preDeployCommand` to actually run | Document the limitation in the parse warnings. Real fix is a RailDock-side hook system; out of scope here. |
| Builder name normalization (`DOCKERFILE` → `dockerfile`) hides a user typo | Emit a warning on any normalized value so the user knows. |
| Auto-detection in `manifests_controller` misroutes Railway JSON as `raildock.json` (both start with `{`) | The detection check explicitly looks for `build` or `deploy` keys; `raildock.json` has neither. Order of checks matters; Railway is checked before generic JSON. |
| Schema rejects Railway builders that look unfamiliar | `ManifestSchema::BUILDERS` already lists `railpack` and `nixpacks`. No schema change needed. |

## Open Questions

- None blocking. All call-outs surfaced in the Phase 0.7 synthesis are documented as decisions in Key Technical Decisions.
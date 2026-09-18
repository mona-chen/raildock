# 2026-09-18 — Static & SPA deploy support

## Problem

Deploying a static/React app fails on every builder:

- **Herokuish**: the app has no `start` script, so `/start web` runs `npm start`
  and exits (`Missing script: "start"`).
- **Railpack**: railpack builds a Caddy static image and puts the start command
  in the image `CMD`. Dokku's `builder-railpack` build stage runs
  `ENTRYPOINT []`, and Docker resets the base image `CMD` when `ENTRYPOINT` is
  set without a `CMD`. The scheduler therefore starts the container with no
  command (`Error response from daemon: no command specified`).
- **Nixpacks**: nixpacks defaults to `DEFAULT_NODE_VERSION = 18`, which has
  reached EOL and been removed from its pinned nixpkgs archives, so the build
  fails before it ever reaches the deploy.

Dokku only derives a process command from a repo `Procfile` or from the `ps`
plugin properties. A generated static site has neither, so nothing tells Dokku
how to serve the build.

## How other platforms model this

- **Railway / Railpack** auto-detect Vite, CRA, Angular, Astro (static),
  Next (`output: export`), React Router and Expo as SPAs, build into the
  publish directory, then serve it with Caddy and an `index.html` fallback.
  `RAILPACK_SPA_OUTPUT_DIR` forces/overrides the directory. Plain static repos
  use the `staticfile` provider (`RAILPACK_STATIC_FILE_ROOT`). Node defaults to
  `lts`.
- **Nixpacks** has a Vite SPA provider with Caddy (`NIXPACKS_SPA_OUT_DIR`,
  `/assets/Caddyfile`) and an nginx `staticfile` provider for prebuilt assets.
  It pins Node per nixpkgs archive; `NIXPACKS_NODE_VERSION` overrides the
  (broken) default of 18.
- **Coolify** exposes a "Static" build pack (prebuilt assets → nginx) and, for
  framework builds, an "Is it a static site?" toggle with a **Publish
  Directory** that feeds Nixpacks/Railpack.

The common model: a first-class *publish directory* + *SPA fallback* setting,
translated into whatever the selected builder natively supports.

## Design

### Model

`service.config["staticSite"]`:

```json
{ "publishDirectory": "dist", "spaFallback": true, "nodeVersion": "22" }
```

A service is static when it is an app with no `docker_image`/`start_command`
and a non-blank `publishDirectory`. Manifest equivalents are the top-level
service keys `publish_directory`, `spa_fallback`, `node_version`.

### Builder translation (`StaticSiteConfigurator`)

Static sites are only buildable/servable by `railpack` and `nixpacks`.
`dockerfile` is left alone (the user's Dockerfile owns serving). Any other
builder (`herokuish`, `pack`, `lambda`, `null`, `auto`, nil) resolves to
railpack when its BuildKit service is available, else nixpacks, and the
substitution is logged.

Build-time env (exported into the build by Dokku's `config_export`):

| builder  | env |
| --- | --- |
| railpack | `RAILPACK_SPA_OUTPUT_DIR=<dir>`, optional `RAILPACK_NODE_VERSION` |
| nixpacks | `NIXPACKS_SPA_OUT_DIR=<dir>`, `NIXPACKS_NODE_VERSION=<nodeVersion or 22>` |

Process command, written to `ps:set <app> dockerfile-start-cmd` (the property
the docker-local scheduler reads for every non-herokuish image):

| builder  | command |
| --- | --- |
| railpack | `caddy run --config /Caddyfile --adapter caddyfile` |
| nixpacks | `caddy run --config /assets/Caddyfile --adapter caddyfile` |

The property is reconciled on every deploy (set or cleared), so removing the
static config cannot leave a stale command behind. An explicit
`start_command` always wins and suppresses the derived one.

### Detection

`StaticSiteDetector` reads `package.json` (plus framework config files when
present) and returns the publish directory for Vite, CRA, Angular, Astro
(static), Gatsby, and Next static export, mirroring railpack's heuristics so
the two stay consistent. `RepositoryDiscovery` records the result on the
generated service so importing a React/Vite repo produces a working static
service with no manual configuration.

## Non-goals

- Prebuilt static repos with no build step (railpack/nixpacks `staticfile`).
  These need `RAILPACK_STATIC_FILE_ROOT`/nginx handling and are not required to
  fix the reported failures.
- Dockerfile-based static sites: the repo's Dockerfile is authoritative.

## Shipped

- `StaticSiteConfigurator` (settings → build env + `ps:set <app>
  dockerfile-start-cmd`), `StaticSiteDetector`, and import-time detection in
  `RepositoryDiscovery` landed in `b0ef5f9`.
- Deploy-time coverage closed the gap the settings-only path left: a frontend
  repo that was never given static settings still failed. `StaticSiteProbe`
  now reads the repo at the deployed revision through its GitHub App connection,
  and `DeploymentJob` falls back to reading the Caddy serve command out of the
  built image (`dokku run <app> cat /Caddyfile`), saves the publish directory,
  and retries the rebuild once when the repo cannot be read at all.
- Confirmed on a real Dokku 0.38.1 host: `ENTRYPOINT []` in
  `plugins/builder-railpack/dockerfiles/builder-build.Dockerfile` (and the
  nixpacks wrapper entrypoint) clears the inherited `CMD` for every build, so
  `dockerfile-start-cmd` is the only thing that makes a static image start.
  Upstream `master` still behaves this way.

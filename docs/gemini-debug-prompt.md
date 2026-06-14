# RailDock External Proxy Debugging Context

## Architecture

RailDock is an open-source PaaS (like Heroku/Coolify) that deploys apps via Dokku. It supports two proxy modes:
- **managed**: RailDock controls Dokku's Traefik
- **external**: RailDock defers to a pre-existing Traefik instance, applying Docker labels for routing

The tween server has a **Matrix Traefik** (traefik:v3.7.5) as the external proxy. RailDock writes Traefik labels to `/var/lib/dokku/config/traefik/<app>/labels` files, which Dokku's traefik plugin reads during deploy and applies to containers.

## Current State

### Traefik Configuration
- Entrypoints: `web` (:8080→host:80), `web-secure` (:8443→host:443), `health` (:7777)
- `web` entrypoint has **global HTTP→HTTPS redirect** (redirects all port 80 traffic to port 443)
- Cert resolver: `letsencrypt` with HTTP challenge on `web` entrypoint
- `acme.json` is **empty** (0 bytes) — no Let's Encrypt certs have been issued
- All HTTPS currently uses Traefik's default self-signed cert
- `exposedByDefault: false` — containers need `traefik.enable=true` label

### Cloudflare
- `alex.tween.im`, `alex-api.tween.im`, `alex-cdn.tween.im` all resolve to **Cloudflare IPs** (104.x, 172.x)
- Cloudflare handles SSL termination (Full mode — connects to origin over HTTPS, accepts self-signed cert)
- Matrix Synapse (`core.tween.im`) works fine through this same setup

### Working: `alex.tween.im` → `alexandrie-frontend-ae9644cd`
- Returns **HTTPS 200** ✅
- RailDock labels file has correct labels (entrypoints=web-secure, tls=true, certresolver=letsencrypt)
- Container is on `traefik` network
- `target_port=8200` (corrected from default 3000)

### Broken: `alex-api.tween.im` → `alexandrie-backend-4eafb60d`
- Returns **HTTPS 404**
- **Labels file** (from RailDock's ExternalProxyConfigurator) only has the sslip.io domain — **missing alex-api.tween.im labels entirely**:
  ```
  traefik.http.routers.alexandrie-backend-4eafb60d-alexandrie-backend-4eafb60d-152-53-163-11-sslip-io-http.entrypoints=web
  traefik.http.routers.alexandrie-backend-4eafb60d-alexandrie-backend-4eafb60d-152-53-163-11-sslip-io-http.rule=Host(`alexandrie-backend-4eafb60d.152.53.163.11.sslip.io`)
  traefik.http.services.alexandrie-backend-4eafb60d-web.loadbalancer.server.port=3000
  ```
- **Container labels** have conflicting labels from BOTH sources:
  - RailDock's labels file (entrypoints=web, correct)
  - Managed plugin's auto-generated labels (entrypoints=https — **wrong**, should be web-secure)
  ```
  # From RailDock labels file (correct entrypoint):
  traefik.http.routers...-http.entrypoints=web
  
  # From managed plugin (WRONG entrypoint — "https" doesn't exist):
  traefik.http.routers...-web-https.entrypoints=https
  traefik.http.routers...-web-https.rule=Host(`...`) || Host(`alex-api.tween.im`)
  traefik.http.routers...-web-https.tls.certresolver=leresolver
  traefik.http.services...-web-https.loadbalancer.server.port=8201
  ```
- The managed plugin's router uses `entrypoints=https` but the Traefik config only has `web-secure`, not `https`

### Broken: `alex-cdn.tween.im` → `alexandrie-rustfs-856c7e88`
- Returns **HTTPS 404**
- Labels file has correct RailDock labels for alex-cdn.tween.im (entrypoints=web-secure, tls=true, certresolver=letsencrypt)
- But container ALSO has managed plugin labels with wrong entrypoint (`https` instead of `web-secure`)
- Port: RailDock labels say 9000 (correct for rustfs/minio), managed plugin says 3000 (wrong)

## Root Causes

1. **Missing labels**: When a custom domain (alex-api.tween.im) is added to a service, the ExternalProxyConfigurator should regenerate ALL labels for ALL domains on the service. But it seems to only write labels for domains that existed at deploy time, not domains added later.

2. **Conflicting labels**: The managed Dokku traefik plugin ALSO generates labels during deploy (entrypoints=https, certresolver=leresolver). These conflict with RailDock's labels (entrypoints=web-secure, certresolver=letsencrypt). The managed plugin uses wrong entrypoint name "https" instead of "web-secure".

3. **Wrong entrypoint**: The managed plugin hardcodes `entrypoints=https` but the Matrix Traefik uses `web-secure` as the entrypoint name.

4. **Port mismatch**: RailDock's TraefikLabelBuilder uses `domain.target_port || service.detected_port || 5000` but the actual container port may differ (detected from Docker image at deploy time by the managed plugin).

## Key Files

- `backend/app/services/external_proxy_configurator.rb` — writes labels to `/var/lib/dokku/config/traefik/<app>/labels`
- `backend/app/services/traefik_label_builder.rb` — generates Traefik router/service labels
- `backend/app/services/project_network_manager.rb` — manages network attachment (attach-post-create for project net, attach-post-deploy for traefik net)
- `backend/app/services/ssl_status_checker.rb` — checks SSL cert status, auto-detects Cloudflare
- `backend/app/services/cloudflare_detector.rb` — DNS check against Cloudflare IP ranges
- `backend/app/controllers/api/domains_controller.rb` — domain CRUD, sets ssl_status
- `backend/app/services/temporary_domain_service.rb` — auto-provisions temporary domains
- `backend/app/jobs/deployment_job.rb` — full deploy pipeline
- `backend/app/models/domain.rb` — Domain model (hostname, ssl, ssl_status, challenge_type, target_port)
- `backend/app/models/server.rb` — Server model (proxy_mode, external_proxy_*, dns_challenge_*)
- `app/src/features/service-panel/tabs/DomainsTab.tsx` — domain list with SSL status badges
- Dokku traefik plugin hook: `/var/lib/dokku/plugins/enabled/traefik-vhosts/docker-args-process-deploy` — reads labels file and generates managed labels

## What Needs Fixing

1. **Labels file must include ALL domains** — When ExternalProxyConfigurator runs, it should write labels for every domain on the service, including ones added after the last deploy.

2. **Remove/override managed plugin labels** — The managed traefik plugin generates its own labels with wrong entrypoint names. Either:
   - Clear the managed plugin's docker-options before writing RailDock labels
   - Or ensure RailDock's labels take precedence (they won't — Traefik merges all labels)

3. **Port detection** — TraefikLabelBuilder should use the actual detected port from the container/managed plugin, not the domain's target_port default.

4. **Entrypoint name** — The server's `external_proxy_https_entrypoint` setting (`web-secure`) should be used consistently. The managed plugin hardcodes `https`.

## Environment

- Server: `152.53.163.11` (SSH as root: `ssh tween`)
- RailDock: `/opt/raildock/` on the server
- RailDock container: `raildock-raildock-1` (port 8888)
- External Traefik: `matrix-traefik` container
- Dokku apps: `alexandrie-frontend-ae9644cd`, `alexandrie-backend-4eafb60d`, `alexandrie-rustfs-856c7e88`
- Docker network for Traefik: `traefik`
- Project network: `rd-alexandrie-7`

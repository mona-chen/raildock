# Domain & SSL Research: How the Big Players Do It

> Research into how Railway, Coolify, Dokploy, Heroku, Render, CapRover, and Vercel handle domains, auto-SSL, port mapping, and wildcard support — with recommendations for RailDock's domain architecture rebirth.

---

## Executive Summary

RailDock's current domain system works but is primitive compared to modern PaaS expectations. The biggest gaps:

1. **No "Generate Domain" button per service** — domains auto-create on service creation, not on demand
2. **No port-to-domain mapping** — Railway's killer "Target Port" feature is missing
3. **Magic domains are HTTP-only** — sslip.io domains can't have SSL (by design), making them unusable for HTTPS-only apps
4. **No wildcard custom domain support** — multi-tenant SaaS is impossible
5. **No private networking DNS** — services can't talk to each other by name like `postgres.project.internal`
6. **Port mapping is a separate concern from domains** — Docker image apps (ActivePieces, etc.) need `http:80:3000` mapped but this is disconnected from the domain UI

---

## 1. Railway — The Gold Standard

### Auto-Generated Domains
- Every service can get a `.up.railway.app` subdomain via **"Generate Domain"** button
- Format: `service-name-abc123.up.railway.app` (random suffix for uniqueness)
- SSL is automatic and immediate (Railway controls the wildcard cert for `*.up.railway.app`)

### Custom Domains
- User adds domain in service settings
- Railway provides: **CNAME target** + **TXT record for ownership verification**
- Both records required — domain 404s without TXT verification
- Let's Encrypt auto-issues within ~1 hour
- Wildcard support: `*.example.com` — requires CNAME + TXT + `_acme-challenge` CNAME

### Target Ports (The Killer Feature)
> "Target Ports, or Magic Ports, correlate a single domain to a specific internal port"

```
https://example.com/     → :8080
https://api.example.com/ → :9000
```

- Auto-detects listening ports from running container
- If multiple ports exposed, user picks from dropdown
- Each domain maps to exactly one internal port
- This is how Railway handles apps that listen on non-80 ports

### Private Networking
- Every service gets `service-name.railway.internal`
- IPv4 + IPv6 support
- Cross-service communication via internal DNS
- Reference variables: `${{Postgres.DATABASE_URL}}`

### SSL
- Let's Encrypt RSA 2048bit
- 90-day certs, auto-renew at 30 days remaining
- Cloudflare-aware: detects orange cloud, advises "Full" (not Strict) mode

---

## 2. Coolify — The Self-Hosted Reference

### Default Auto-Domains
- Uses **sslip.io** by default for quick testing
- Format: `app.5-199-174-174.sslip.io` → resolves to `5.199.174.174`
- Zero DNS setup required

### Wildcard Custom Domains
- Configure `*.example.com` wildcard
- Each app auto-gets `app-name.example.com`
- Requires wildcard DNS A record pointing to server IP

### SSL Architecture
- **Reverse Proxy**: Traefik (default)
- **Challenge**: HTTP-01 by default (port 80 must be open)
- **Wildcard SSL**: DNS-01 challenge only (needs DNS provider API key)
- **Custom certs**: Upload `.cert` + `.key` to `/data/coolify/proxy/certs/`
- **Storage**: `acme.json` for LE certs

### Domain → Port Mapping
- Traefik routes based on Host header
- Container port is specified in the app config
- Traefik load-balances to the container port

### Key Insight
> Coolify uses sslip.io as a **fallback** when no wildcard domain is configured. This is the right mental model: sslip.io is for "I haven't set up DNS yet", not for production.

---

## 3. Dokploy — The Traefik-First Approach

### Free Domains
- `traefik.me` for quick testing (HTTP only, no SSL)
- `traefik.me` is a wildcard DNS service similar to sslip.io

### Custom Domains
- Add domain in app settings
- Auto Let's Encrypt via Traefik
- Three domain types: `application`, `compose`, `preview`

### Domain Object Structure
```json
{
  "domainType": "application",
  "host": "app.example.com",
  "port": 3000,
  "https": true,
  "certificateType": "letsencrypt"
}
```

### Port per Domain
- Each domain has an explicit `port` field
- Maps external domain to internal container port
- This is critical for Docker Compose services where different services expose different ports

### Wildcard SSL
- Requires DNS-01 challenge
- Configure DNS provider API token in Traefik settings
- Cloudflare, Route53, DigitalOcean, etc.

### Preview Deployments
- Wildcard domain for PR previews: `*.preview.example.com`
- Each PR gets its own subdomain

---

## 4. Heroku — The OG

### Auto Domains
- Every app gets `app-name.herokuapp.com`
- Wildcard SSL already covers `*.herokuapp.com`
- Zero config, immediate HTTPS

### Custom Domains
- `heroku domains:add example.com`
- DNS: CNAME to `example.com.herokudns.com`
- ACM (Automated Certificate Management): `heroku certs:auto:enable`
- Let's Encrypt fully automated

### ACM Behavior
- Auto-issues cert when domain added
- Auto-renews 1 month before expiry
- Validates via HTTP-01 (handled by Heroku router, not app)
- Wildcard domains supported on Common Runtime

### Key Difference
> Heroku's router handles ACME challenges *before* traffic reaches your app. The `/.well-known/acme-challenge/*` paths are intercepted by the platform.

---

## 5. Render — The Simple Approach

### Auto Domains
- Every web service gets `service-name.onrender.com`
- Auto TLS for the subdomain

### Custom Domains
- Add in dashboard → configure DNS → verify
- Free TLS via Let's Encrypt + Google Trust Services
- Wildcard support
- Auto HTTP→HTTPS redirect

### Limitations
- Hobby plan: 2 custom domains
- Pro: 15, Scale: 25
- Extra domains: $0.25/month

---

## 6. CapRover — The Wildcard-First Model

### Installation
- Requires wildcard DNS: `*.caprover.yourdomain.com` → server IP
- Dashboard at `captain.caprover.yourdomain.com`

### App Domains
- Each app auto-gets: `app-name.caprover.yourdomain.com`
- Built-in Let's Encrypt via certbot
- HTTP-01 default, DNS-01 for wildcard

### SSL
- One-click enable per app
- Auto-renewal
- Custom certbot command override possible
- Custom nginx config override

---

## 7. sslip.io / nip.io — Magic DNS Explained

### How It Works
- Wildcard DNS service that extracts IP from subdomain
- `192-168-1-1.sslip.io` → resolves to `192.168.1.1`
- `myapp.152-53-163-11.sslip.io` → resolves to `152.53.163.11`
- Any subdomain works because it's a wildcard: `*.sslip.io`

### SSL Limitation
> **Critical**: You CANNOT get a valid SSL certificate for `*.152-53-163-11.sslip.io` because you don't own the `sslip.io` domain. Let's Encrypt will not issue certs for it.

> This means sslip.io domains are **HTTP-only**. For HTTPS, you need your own domain + wildcard DNS.

### Usage Pattern
- **Development/testing**: sslip.io is perfect — no DNS setup
- **Production**: Must use your own domain with wildcard A record

---

## 8. Current RailDock State

### What's Working
- `Server#base_domain` + `auto_domains` toggle
- `Domain` model with hostname, port, ssl, letsencrypt, temporary
- `Server#temporary_hostname` generates `app-name.152-53-163-11.sslip.io`
- Magic domains get HTTP/80 (no SSL)
- Regular domains get HTTPS/443 + Let's Encrypt
- Dokku syncs domains via `domains:add`
- Traefik proxy with Let's Encrypt

### What's Broken / Missing

| Problem | Impact |
|---------|--------|
| sslip.io can't have SSL | Apps requiring HTTPS (OAuth, webhooks) break |
| No "Generate Domain" button | Domains auto-create clutter; user has no control |
| No target port per domain | Can't route `api.example.com` → :8080 and `app.example.com` → :3000 |
| No port auto-detection | Docker image apps (ActivePieces on :3000) need manual port mapping |
| No wildcard custom domain | Multi-tenant SaaS impossible |
| No private networking DNS | Services can't reference each other by name |
| No preview/branch domains | No PR preview workflow |
| Domain is service-level only | No project-level domain namespace |
| Port mapping is separate UI | Confusing: domain config and proxy ports are disconnected |

---

## 9. Recommended Architecture Rebirth

### Phase 1: Target Ports + Port Auto-Detection (Immediate)

**Core change**: Every domain maps to a target port. This is how Railway and Dokploy do it.

```ruby
# Domain model enhancement
class Domain < ApplicationRecord
  belongs_to :service
  validates :hostname, presence: true
  validates :target_port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
  
  # target_port = the port the app actually listens on inside the container
  # This is DIFFERENT from the port users connect to (always 80/443)
end
```

**Port detection logic** (like Railway's "Magic Ports"):
1. After deployment, inspect running container: `docker inspect --format='{{json .Config.ExposedPorts}}'`
2. If `EXPOSE` found, use that port as default target_port
3. If no `EXPOSE`, default to 5000 (Dokku default) or allow user override
4. Store detected port on the service

**Dokku proxy mapping**:
```
dokku ports:set app-name http:80:3000 https:443:3000
```
This maps public 80/443 to container 3000. The domain stays clean.

### Phase 2: Per-Service "Generate Domain" (Immediate)

**Change auto-domain from auto-create to on-demand:**

```
Service Settings → Domains → [Generate Domain] button
```

**Auto-domain format options:**

Option A — Project-scoped (like Railway):
```
service-name-project-id.up.raildock.io   # if we control a domain
# OR for self-hosted:
service-name.152-53-163-11.sslip.io      # current, HTTP only
```

Option B — Server-scoped wildcard (like Coolify/CapRover):
```
# User sets wildcard A record: *.apps.mydomain.com → server IP
# Then auto-domains are:
service-name.apps.mydomain.com           # auto-SSL via wildcard!
```

**Recommendation**: Support BOTH patterns:
- **Magic DNS** (sslip.io) for quick testing — HTTP only, no SSL
- **Wildcard domain** for production — HTTPS with auto-SSL via wildcard cert

### Phase 3: Wildcard SSL for Self-Hosted (Short-term)

**The sslip.io problem**: No SSL. The solution is a two-tier domain system:

```
Tier 1 — Magic DNS (no SSL):
  app-name.152-53-163-11.sslip.io
  → Zero setup, HTTP only, for testing

Tier 2 — Wildcard Domain (full SSL):
  User configures: *.apps.mydomain.com → server IP
  RailDock requests: *.apps.mydomain.com wildcard cert via DNS-01
  Each app gets: app-name.apps.mydomain.com
  → Full HTTPS, auto-SSL, production-ready
```

**DNS-01 challenge implementation**:
- Dokku Traefik supports DNS-01: `dokku traefik:set --global challenge-mode dns`
- Requires DNS provider API token (Cloudflare, Route53, etc.)
- One wildcard cert covers ALL apps on that server

### Phase 4: Private Networking DNS (Medium-term)

**Like Railway's `*.railway.internal`:**

```
# Each service gets an internal hostname:
postgres.my-project.raildock.internal
redis.my-project.raildock.internal
api.my-project.raildock.internal

# These resolve to internal Docker IPs
# Apps communicate via internal network, no public exposure needed
```

**Implementation**:
- Use Dokku's Docker network + custom DNS
- Or Traefik internal entrypoint
- Or simple `/etc/hosts` injection via Dokku

### Phase 5: Preview/Branch Domains (Medium-term)

```
# For Git-based services:
main branch → app-name.apps.mydomain.com
pr-123      → app-name-pr-123.apps.mydomain.com
branch-x    → app-name-branch-x.apps.mydomain.com
```

**Requires**: wildcard cert + automatic subdomain generation per deployment

---

## 10. UI/UX Recommendations

### Service Panel → Domains Tab (Redesigned)

```
┌─ Domains ─────────────────────────────────────────────┐
│                                                         │
│  [Generate Domain]  [+ Add Custom Domain]              │
│                                                         │
│  ┌─ service-name-abc123.up.raildock.io ─────────────┐  │
│  │  🌐 Public  •  Target: :3000  •  SSL: Auto ✅    │  │
│  │  [Copy]  [Open]  [×]                              │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ api.mydomain.com ────────────────────────────────┐  │
│  │  🌐 Custom  •  Target: :8080  •  SSL: Let's Encrypt │  │
│  │  [Copy]  [Open]  [×]  [Verify DNS]                │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Domain Generation Modal

```
┌─ Generate Domain ─────────────────────────────────────┐
│                                                         │
│  Domain Type:                                           │
│  ○ Auto (sslip.io) — instant, HTTP only                │
│  ○ Server wildcard — requires *.apps.mydomain.com DNS  │
│                                                         │
│  Target Port: [3000 ▼] (auto-detected)                  │
│                                                         │
│  [Generate]  [Cancel]                                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Server Settings → Domain Configuration

```
┌─ Domain Settings ─────────────────────────────────────┐
│                                                         │
│  Base Domain: [*.apps.mydomain.com        ]            │
│              ℹ️ Create A record: *.apps.mydomain.com   │
│                 → 152.53.163.11                         │
│                                                         │
│  Wildcard SSL: [Enable]                                 │
│  DNS Provider: [Cloudflare ▼]                           │
│  API Token:    [••••••••••••••                        ]│
│                                                         │
│  Auto-assign domains: [✓]                               │
│  Default target port: [80 ▼]                            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 11. Data Model Changes

```ruby
# domains table enhancements
class AddTargetPortToDomains < ActiveRecord::Migration[8.1]
  def change
    add_column :domains, :target_port, :integer, default: 80
    add_column :domains, :generated, :boolean, default: false  # vs custom
    add_column :domains, :verified, :boolean, default: true    # DNS verified?
    add_column :domains, :verified_at, :datetime
  end
end

# servers table enhancements
class AddWildcardSslToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :wildcard_domain, :string
    add_column :servers, :wildcard_ssl_enabled, :boolean, default: false
    add_column :servers, :dns_provider, :string
    add_column :servers, :dns_provider_token, :string  # encrypted
  end
end

# services table enhancements
class AddDetectedPortToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :detected_port, :integer
    add_column :services, :internal_hostname, :string
  end
end
```

---

## 12. Dokku Integration Changes

### Port Mapping (Critical for Docker Image Apps)

```ruby
# In DeploymentJob or ServiceSettingsSync
def sync_port_mapping(service, engine)
  service.domains.each do |domain|
    target = domain.target_port || service.detected_port || 5000
    
    # Set proxy port mapping: public 80/443 → container target_port
    engine.run("dokku ports:set #{service.dokku_app_name} http:80:#{target} https:443:#{target}")
  end
end
```

### Wildcard SSL via Traefik + DNS-01

```bash
# One-time server setup
dokku traefik:set --global letsencrypt-email admin@example.com
dokku traefik:set --global challenge-mode dns
dokku traefik:set --global dns-provider cloudflare
dokku traefik:set --global dns-provider-cf_api_token <token>
dokku traefik:stop
dokku traefik:start

# Add wildcard domain to Traefik config
dokku traefik:set --global tls-domains-main mydomain.com
dokku traefik:set --global tls-domains-sans '*.apps.mydomain.com'
```

### Private Networking

```bash
# Create custom Docker network for the project
dokku network:create raildock-internal

# Connect app to internal network
dokku network:set my-app attach-post-create raildock-internal

# Add internal DNS aliases
dokku network:set my-app post-create-network raildock-internal
```

---

## 13. Implementation Priority

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| **P0** | Port auto-detection + `target_port` on Domain | 1 day | Fixes ActivePieces and all Docker image apps |
| **P0** | `dokku ports:set http:80:target_port` on deploy | 1 day | Makes custom-port apps accessible |
| **P1** | "Generate Domain" button (on-demand, not auto) | 2 days | Better UX, less clutter |
| **P1** | Connect Domain.target_port to proxy port mapping | 2 days | Clean domain→port routing |
| **P2** | Wildcard domain support + DNS-01 | 3 days | Production SSL for all apps |
| **P2** | Private networking DNS | 2 days | Service-to-service communication |
| **P3** | Preview/branch domains | 3 days | PR preview workflow |
| **P3** | Custom domain verification (CNAME + TXT) | 2 days | Railway-like custom domain flow |

---

## 14. Key Takeaways

1. **sslip.io is a dev tool, not production**. For production SSL, users MUST configure a wildcard domain.

2. **Target port per domain is non-negotiable**. Railway, Dokploy, Coolify all do this. It's how you handle apps on ports 3000, 8080, 9000.

3. **Port auto-detection saves users pain**. Inspect `EXPOSE` from Docker image, default to 5000.

4. **Wildcard SSL via DNS-01 is the holy grail**. One cert covers all apps. Coolify and CapRover both do this.

5. **Private networking DNS** makes the platform feel complete. `postgres.my-project.internal` is magic.

6. **Railway's UX is the benchmark**: Generate Domain → pick target port → auto-SSL → done.

---

*Research compiled 2026-05-21. Sources: Railway docs, Coolify docs, Dokploy docs, Heroku Dev Center, Render docs, CapRover docs, Dokku docs, sslip.io docs.*

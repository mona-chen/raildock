---
title: "Automated Remote Dokku Server Setup"
type: feat
date: 2026-06-28
status: implemented
---

# Automated Remote Dokku Server Setup

## Problem Frame

RailDock currently assumes Dokku runs on the same host as RailDock. The installer auto-provisions a local Dokku instance, generates an SSH key, and creates a "Local Dokku" server record. When a user wants to manage a remote Dokku host, they must:

1. Generate an SSH key manually.
2. Add the public key to both `dokku` and `root` authorized_keys on the remote host.
3. Paste the private key into the UI with no validation or format checking.
4. Validate blindly with no host-key verification.
5. Hope the `dokku` and `root` users are both correctly authorized, because the UI never explains the root-SSH requirement.

This is error-prone, insecure, and undocumented inside the product. The goal is to make adding a remote Dokku server as automated as Coolify's "Add Server" flow while keeping the implementation simple and fixing all known security/UX gaps.

---

## Scope Boundaries

### In Scope
- Org-scoped SSH key generation and storage.
- In-app public-key display with copy-to-clipboard and setup instructions.
- One-line remote bootstrap command/script that installs prerequisites and authorizes RailDock.
- Server creation wizard with pre-save connection test and clear error surfacing.
- Host-key fingerprint capture and verification.
- Fix server authorization to be organization-scoped.
- Implement `INSTALL_DOKKU` / `SKIP_DOKKU_CHECK` installer flags.
- Fix `/tmp` private-key permissions during install/dev setup.

### Deferred to Follow-Up Work
- Multi-server load balancing or auto-routing of app traffic across servers.
- Agent-based remote management (long-running daemon on managed host).
- SSH jump host / bastion support.
- Cloud provider APIs for automatic VM provisioning.
- Per-server SSH key passphrases.

### Outside This Product's Identity
- Replacing Dokku with a different PaaS backend.
- Managing non-Linux servers.

---

## Research Summary: How Coolify Does It

Coolify uses a straightforward pattern that we can adapt:

1. **Centralized key management** — Users create SSH keys in **Keys & Tokens**. Coolify can generate an RSA/Ed25519 key pair and stores the private key encrypted.
2. **Add Server flow** — User enters IP/domain, selects a private key, and specifies the user (default `root`).
3. **Manual public-key step** — Coolify displays the public key and instructs the user to add it to `/root/.ssh/authorized_keys` on the target host.
4. **Validation & provisioning** — After the key is in place, Coolify connects over SSH, validates Docker, and installs Docker Engine if missing.
5. **Security model** — Coolify connects as `root` for host-level operations. A recent CVE (CVE-2025-64420) exposed root private keys to low-privileged users, reinforcing that key access must be strictly admin-only.

### What We Will Adapt
- Generate one Ed25519 key pair per organization (simpler than Coolify's key-per-entry model).
- Display the public key with a one-line bootstrap command that the user runs on the remote host.
- The bootstrap command adds the public key to `root` and `dokku` authorized_keys, installs Dokku if needed, and opens port 22.
- Validate the connection from the UI and surface Dokku/Docker versions, proxy type, and public IP.

### What We Will Improve Over Coolify
- Strict admin-only access to private keys.
- Ed25519 keys with host-key verification enabled via stored fingerprints.
- Org-scoped authorization instead of user-scoped ownership.
- Clear in-app setup instructions instead of relying on external docs.

---

## Key Technical Decisions

1. **Org-scoped keys, not server-scoped**  
   One Ed25519 key pair per organization reduces key sprawl and matches RailDock's organization-centric model. The private key is encrypted with Lockbox and only readable by organization owners/admins.

2. **Bootstrap command over full agent install**  
   A one-line shell command that the user runs as root on the remote host is the right balance of automation and simplicity. It avoids the complexity of a persistent agent while still installing Dokku/Docker and authorizing the key.

3. **Host-key verification enabled**  
   Replace `verify_host_key: :never` with `:accept_new_or_local_tunnel` semantics: accept a new key on first validation, store the fingerprint, and fail if the fingerprint changes on subsequent connections.

4. **Organization-scoped authorization**  
   Servers belong to organizations, not users. Access checks will rely on `OrganizationMembership` roles (`owner`/`admin` can manage servers; `member` can view but not modify).

5. **Keep Dokku as the deployment backend**  
   The remote setup automation is about connecting to Dokku hosts, not replacing Dokku.

---

## Implementation Units

### U1. Organization SSH Key Model and Service

**Goal**: Store and manage an organization-wide Ed25519 SSH key pair used to connect to remote Dokku hosts.

**Files**:
- `backend/db/migrate/` — add `organization_id` and encrypted private/public key columns to a new `organization_ssh_keys` table (or extend `organizations`).
- `backend/app/models/organization.rb`
- `backend/app/models/organization_ssh_key.rb` (new)
- `backend/app/services/organization_ssh_key_service.rb` (new)
- `backend/spec/models/organization_ssh_key_spec.rb` (new)
- `backend/spec/services/organization_ssh_key_service_spec.rb` (new)

**Approach**:
- Create a model that belongs to an `Organization` and stores `private_key_ciphertext` (Lockbox-encrypted), `public_key`, and `fingerprint`.
- Provide `OrganizationSshKeyService.generate(organization)` that creates an Ed25519 key pair with no passphrase using `OpenSSL::PKey::EC` or `Net::SSH::KeyFactory` (reuse patterns from `SshKeyService`).
- Expose `organization.ensure_ssh_key!` that lazily creates the key on first use.
- Restrict read access to organization owners/admins.

**Test scenarios**:
- Generating a key creates a valid Ed25519 public/private pair.
- The private key is encrypted and decryptable with the correct Lockbox master key.
- Only admins/owners can read the private key; members cannot.
- `ensure_ssh_key!` is idempotent.

---

### U2. Host-Key Verification and Fingerprint Storage

**Goal**: Replace disabled host-key verification with a secure first-use capture + fingerprint check model.

**Files**:
- `backend/app/models/server.rb`
- `backend/app/services/dokku_engine.rb`
- `backend/app/services/host_engine.rb`
- `backend/app/services/ssh_connection_builder.rb` (new)
- `backend/spec/services/ssh_connection_builder_spec.rb` (new)

**Approach**:
- Add `host_key_fingerprint` column to `servers`.
- Introduce `SshConnectionBuilder` that centralizes SSH options for both engines.
- On first validation: accept the host key, store its SHA-256 fingerprint, and log the event.
- On subsequent connections: compare the presented host key with the stored fingerprint; fail loudly on mismatch.
- For local development / `host.docker.internal`, allow a configurable `RAILDOCK_TRUST_LOCAL_HOSTS=true` escape hatch, defaulting to false in production.

**Test scenarios**:
- First connection stores the host-key fingerprint.
- Second connection with matching fingerprint succeeds.
- Connection with mismatched fingerprint raises a clear error.
- Missing stored fingerprint on a non-local host requires explicit confirmation.

---

### U3. Remote Bootstrap Script and Endpoint

**Goal**: Provide a one-line shell command that prepares a remote host for RailDock management.

**Files**:
- `backend/app/services/server_bootstrap_command_builder.rb` (new)
- `backend/app/controllers/api/servers_controller.rb`
- `backend/config/routes.rb`
- `backend/spec/services/server_bootstrap_command_builder_spec.rb` (new)
- `backend/spec/requests/api/servers_bootstrap_spec.rb` (new)
- `scripts/` — optionally host a static bootstrap script if it grows large.

**Approach**:
- Add `GET /api/organizations/:id/server-bootstrap` that returns:
  - The organization's public SSH key.
  - A one-line command: `curl -fsSL <raildock-url>/bootstrap.sh | bash -s -- <org-public-key>`.
  - Manual steps for users who prefer not to run a remote script.
- The bootstrap script (delivered via the Rails app or a static file) will:
  - Detect package manager (`apt`, `yum`, etc.).
  - Install Docker Engine if missing.
  - Install Dokku if `INSTALL_DOKKU=1` or if no Dokku is present and the user confirmed.
  - Append the public key to `/root/.ssh/authorized_keys` and `/home/dokku/.ssh/authorized_keys`.
  - Ensure correct permissions (`700 ~/.ssh`, `600 authorized_keys`).
  - Print a confirmation message.
- Do **not** store the private key in `/tmp` with `0644`; the public key is the only thing transmitted.

**Test scenarios**:
- Bootstrap endpoint returns the public key and a valid shell command.
- Bootstrap script correctly appends the public key to authorized_keys with correct permissions.
- Bootstrap script installs Docker when missing.
- Bootstrap script is idempotent on re-run.
- Endpoint requires admin/owner role.

---

### U4. Server Creation Wizard and Pre-Save Validation

**Goal**: Make adding a remote server a guided, validated flow with clear error messages.

**Files**:
- `app/src/pages/ServerPage.tsx`
- `app/src/components/ServerSetupWizard.tsx` (new)
- `app/src/hooks/useServers.ts`
- `app/src/lib/api.ts`
- `app/src/__tests__/components.test.tsx` or new `app/src/__tests__/ServerSetupWizard.test.tsx`
- `backend/app/controllers/api/servers_controller.rb`
- `backend/app/models/server.rb`

**Approach**:
- Replace the simple "Add Server" modal with a two-step wizard:
  1. **Bootstrap** — Show the org public key and the one-line bootstrap command. Explain that the user must run it as root on the remote host.
  2. **Connect** — Enter host/IP and SSH user (default `root` for HostEngine, `dokku` for DokkuEngine). Click "Test & Add" to run `ServersController#validate` before persisting.
- Surface validation errors in the UI: SSH unreachable, auth failed, Dokku not found, Docker missing, host-key mismatch.
- Add model validations: valid SSH key format when provided, host format, and SSH user presence.
- Allow editing name, host, SSH user, and proxy settings after creation.

**Test scenarios**:
- Wizard renders bootstrap instructions when no org key exists.
- Creating a server with a reachable host succeeds and stores detected metadata.
- Creating a server with an unreachable host shows a clear error without persisting a broken record.
- Editing a server's host re-runs validation.

---

### U5. Fix Server Authorization Model

**Goal**: Make servers organization-scoped consistently across all endpoints.

**Files**:
- `backend/app/controllers/api/servers_controller.rb`
- `backend/app/controllers/concerns/authorizable.rb`
- `backend/spec/requests/api/servers_spec.rb`

**Approach**:
- Remove `user_id` ownership from server access checks.
- Update `scoped_servers` to return servers belonging to the current organization.
- Require `owner` or `admin` role for create/update/destroy/validate.
- Allow `member` role to view servers in their organization.
- Ensure `authorize_server_record!` uses organization membership, not `current_user.admin? || server.user_id == current_user.id`.

**Test scenarios**:
- Org owner can create, update, validate, and destroy servers.
- Org admin can manage servers.
- Org member can list and view servers but cannot create/update/destroy.
- User outside the organization cannot access servers.

---

### U6. Implement Installer Flags and Fix Local Setup

**Goal**: Honor documented `INSTALL_DOKKU` and `SKIP_DOKKU_CHECK` flags, and fix insecure temporary key handling.

**Files**:
- `install.sh`
- `scripts/setup-dev.sh`
- `scripts/dokku-init.sh`
- `README.md`
- `AGENTS.md`

**Approach**:
- Read `INSTALL_DOKKU` (default `1`) and `SKIP_DOKKU_CHECK` in `install.sh`.
- When `INSTALL_DOKKU=0`, skip Dokku installation entirely (useful for managing remote hosts only).
- When `SKIP_DOKKU_CHECK=1`, skip the Dokku presence check (useful for testing or non-Dokku installs).
- Fix `install.sh` and `scripts/setup-dev.sh` to copy keys to `/tmp` with `chmod 600` and use `mktemp` with cleanup traps.

**Test scenarios**:
- `INSTALL_DOKKU=0` skips Dokku installation.
- `SKIP_DOKKU_CHECK=1` bypasses the Dokku check.
- Temporary key files are created with `0600` permissions and removed on exit.

---

### U7. Security Hardening and Backend Validation

**Goal**: Validate SSH keys, enforce admin-only private-key access, and audit server operations.

**Files**:
- `backend/app/models/organization_ssh_key.rb`
- `backend/app/models/server.rb`
- `backend/app/controllers/api/servers_controller.rb`
- `backend/app/services/ssh_key_validator.rb` (new)
- `backend/spec/services/ssh_key_validator_spec.rb` (new)

**Approach**:
- Add `SshKeyValidator` to check that a pasted private key is a valid OpenSSH/PEM format.
- Add uniqueness validation on `Server#host` within an organization.
- Ensure private keys are never serialized in JSON responses (already encrypted, but add an explicit guard).
- Add an audit log entry (or structured log line) for server create/update/destroy and validation attempts.

**Test scenarios**:
- Invalid SSH key string is rejected with a clear error.
- Duplicate host within the same organization is rejected.
- Private key is not included in any API response.
- Server operations emit an audit log line.

---

### U8. Integration and End-to-End Tests

**Goal**: Verify the full remote-server flow works end to end.

**Files**:
- `backend/spec/requests/api/organization_ssh_keys_spec.rb` (new)
- `backend/spec/requests/api/server_setup_flow_spec.rb` (new)
- `backend/spec/support/ssh_test_helpers.rb` (new)

**Approach**:
- Add request specs covering:
  - Org key generation and public-key retrieval.
  - Bootstrap command generation.
  - Server creation with mocked SSH validation.
  - Host-key fingerprint capture on first connect.
- Use `WebMock` or a lightweight SSH mock to avoid requiring a real remote host.

**Test scenarios**:
- Full happy path: generate org key → get bootstrap command → add server → validate succeeds → fingerprint stored.
- Failure path: generate org key → add server → SSH auth fails → server not marked connected.

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Bootstrapping arbitrary remote hosts with a shell script is dangerous if the script is MITM'd. | Serve bootstrap script over HTTPS from the RailDock instance; pin the script URL in the UI; include a checksum option for paranoid users. |
| Root SSH key exposure to low-privileged users. | Store private key encrypted; only owners/admins can read; never serialize in JSON; audit access. |
| Host-key changes break automation. | Store fingerprints; provide UI flow to approve a changed host key; allow override env var for development. |
| Dokku installation on remote hosts varies by OS. | Support Ubuntu/Debian first; detect and fail gracefully on unsupported distros; document manual steps. |
| Existing user-owned servers become inaccessible after auth change. | Migration: update existing `Server` records to belong to the creator's current organization if unscoped. |

---

## Verification

The implementation is complete when:
1. An org owner can open **Servers → Add Server**, see a public key, and copy a one-line bootstrap command.
2. Running the bootstrap command on a fresh Ubuntu host authorizes RailDock and installs Dokku.
3. Returning to RailDock and entering the host IP succeeds in a "Test & Add" flow.
4. Host-key fingerprints are stored and verified on subsequent connections.
5. Server management is organization-scoped and admin-only.
6. `INSTALL_DOKKU=0` and `SKIP_DOKKU_CHECK=1` work as documented.
7. All new and existing tests pass.

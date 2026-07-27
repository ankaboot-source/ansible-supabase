# Ansible Supabase

One-command deployment of a **self-hosted, production-ready Supabase stack** on any Debian/Ubuntu server. The playbook installs Docker, clones the latest Supabase release, generates all configuration files, and starts the full stack — secured by default with automatic TLS, SSO/OAuth2, basic auth, IP allow-listing, a firewall, and brute-force protection.

This repository's purpose is to give you a **ready-to-use, full-featured Supabase with security, encryption, and SSO/auth baked in** — not a bare dashboard exposed to the internet.

> **Encryption at rest (LUKS) and automated S3 backups** are included and ready to enable; they need a dedicated disk volume and S3 credentials respectively, so they are shown as optional hardening steps at the end of this guide.

For deep customization (custom OAuth providers, Grafana modes, retention tuning, version pinning) see [docs/advanced-docs.md](docs/advanced-docs.md).

---

## 🚀 Quick Start

### 1. 📋 Prerequisites

- A **Debian/Ubuntu server** with root or sudo access
- A **domain** with three DNS A records pointing to your server:
  - `sb.example.com` — Supabase dashboard + API
  - `auth.example.com` — OAuth2 authentication endpoint
  - `monitor.example.com` — Grafana dashboard (monitoring is enabled by default)
- Ports **80** and **443** reachable for automatic Let's Encrypt TLS and the Caddy reverse proxy
- A registered **OAuth2 application** (GitHub, GitLab, Discord, or any OIDC provider) to protect the dashboard via SSO — see [SSO Provider Setup](#sso-provider-setup) below

### 2. 📥 Clone

```bash
git clone https://github.com/ankaboot-source/ansible-supabase.git
cd ansible-supabase
```

### 3. 🔑 Generate Supabase Required Keys

```bash
sh generate-keys.sh
```

This updates `env/supabase.yml` with all Supabase cryptographic secrets (JWT, anon key, service role key, Postgres password, and all tokens).

### 4. ⚙️ Configure `env/supabase.yml`

Open `env/supabase.yml` and fill in every field tagged `#REQUIRED`. The file ships with **secure defaults** (basic auth + IP allow-list + SSO on the dashboard). Keep them — do not strip them down.

```yaml
# ── System User ──────────────────────────
deploy_user: your-ssh-username
docker_users:
  - your-ssh-username

# ── Supabase Secrets (auto-generated in step 3) ──────
postgres_db_pwd: <strong-password>
sb_jwt_secret: <jwt-secret-from-generator>
sb_anon_key: <anon-key-from-generator>
sb_service_role_key: <service-role-key-from-generator>
secret_key_base: ...
vault_enc_key: ...
pg_meta_crypto_key: ...
logflare_public_access_token: ...
logflare_private_access_token: ...
s3_protocol_access_key_id: ...
s3_protocol_access_key_secret: ...
pooler_tenant_id: pooler

# ── Public URLs ──────────────────────────
site_url: https://app.example.com          # Your app's public URL
api_external_url: https://sb.example.com   # Supabase API endpoint (used by Studio)
additional_redirect_urls: https://app.example.com/auth/callback
mailer_templates_base_url: https://app.example.com

# ── SMTP (for auth emails) ───────────────
smtp_admin_email: user@example.com
smtp_host: mail.example.com
smtp_user: user@example.com
smtp_password: <smtp-password>
```

#### SSO Provider Setup

Pick **one** OAuth2 provider and fill in its block in `env/supabase.yml`. Set `SSO_PROVIDER` to `github`, `gitlab`, `discord`, or `generic` (any OIDC).

**GitHub** (redirect URI: `https://sb.example.com/oauth2/github/authorization-code-callback`):

```yaml
SSO_PROVIDER: github
github_oauth_client_id: <your-client-id>
github_oauth_client_secret: <your-client-secret>
github_allow_list: "github.com/user1 github.com/user2"
```

**GitLab** (redirect URI: `https://sb.example.com/oauth2/gitlab/authorization-code-callback`):

```yaml
SSO_PROVIDER: gitlab
gitlab_domain: gitlab.com
gitlab_oauth_client_id: <your-client-id>
gitlab_oauth_client_secret: <your-client-secret>
gitlab_allow_list: "user1@example.com user2@example.com"
```

**Discord** (redirect URI: `https://sb.example.com/oauth2/discord/authorization-code-callback`):

```yaml
SSO_PROVIDER: discord
discord_oauth_client_id: <your-client-id>
discord_oauth_client_secret: <your-client-secret>
admin_role_id: <your-admin-user-id>
discord_guild_id: <your-discord-server-id>
```

**Generic OIDC** (any OpenID Connect provider, e.g. Keycloak):

```yaml
SSO_PROVIDER: generic
oidc_realm: generic
oidc_driver: generic
oidc_client_id: <your-client-id>
oidc_client_secret: <your-client-secret>
base_auth_url: https://keycloak.example.com
metadata_url: https://keycloak.example.com/.well-known/openid-configuration
app_url: https://sb.example.com
generic_allow_list: "user1@gmail.com user2@gmail.com"
```

**Common SSO variables** (required for any provider):

```yaml
base_auth_domain: auth.example.com    # OAuth2 auth endpoint subdomain
root_domain: example.com              # root domain for SSO cookies
jwt_shared_key: <openssl rand -base64 32>
```

#### 🛡️ Caddyfile Configuration (Reverse Proxy + SSO + Basic Auth)

The `projects` block in `env/supabase.yml` is pre-configured to protect the dashboard with SSO, basic auth, and an IP allow-list. Keep this secure default:

```yaml
projects:
  supabase:
    log_file: supabase-access
    domain: "sb.example.com"
    allowed_ips:                       # IP allow-list — remove if you don't need it
      - 123.123.123.123
      - 111.111.111.111
    oidc_enabled: true
    upstreams:
      # Dashboard — protected by SSO + basic auth
      - targets: ["localhost:3001"]
        paths: [""]
        oidc: true
        basicauth:
          - path: /project/default
            username: your_user
            # Generate with: caddy hash-password
            password: $2a$10$...
      # API routes — Kong handles auth, no SSO
      - targets: ["localhost:8000"]
        paths:
          - /rest/v1/*
          - /auth/v1/*
          - /realtime/v1/*
          - /storage/v1/*
          - /functions/v1/*
        oidc: false

  monitor:
    log_file: monitor-access
    domain: "monitor.example.com"
    oidc_enabled: false
    upstreams:
      - targets: ["localhost:3002"]
        paths: [""]
        oidc: false
```

> To lock down Grafana, set `GRAFANA_AUTH_ANONYMOUS_ENABLED: false` and enable basic auth or GitHub OAuth for Grafana (see [docs/advanced-docs.md](docs/advanced-docs.md)).

#### 🧱 Firewall & Brute-force Protection

The default `firewall_allow` / `firewall_deny` and fail2ban blocks in `env/supabase.yml` are already sane (allow 80/443 + SSH, deny internal ports). Adjust the `allowed_ips` and `firewall_allow` entries to your needs.

### 5. 🧩 Enable the Security Roles

The security roles ship commented in `playbook-supabase.yml`. **Uncomment them** so the default deploy includes the full security stack:

```yaml
---
- hosts: localhost
  become: true
  roles:
   - docker
   - supabase

   # ─── Security & monitoring (enabled by default) ───
   - ufw                     # Firewall — allow/deny rules per port
   - caddy                   # Reverse proxy + automatic TLS + SSO + basic auth
   - fail2ban                # Brute-force protection for Postgres
   - monitor                 # Grafana + Prometheus + Loki stack

   # ─── Optional hardening (need external resources) ───
   # - role: luks             # At-rest disk encryption (needs a dedicated volume)
   #   when: supabase_encryption.enabled
   # - backup                 # Automated S3-compatible backups (needs S3 creds)
```

### 6. ▶️ Deploy

Run the installer (installs Ansible + Git if needed, then executes the playbook):

```bash
sudo ./install.sh
```

To see what will happen without making changes:

```bash
sudo ./install.sh -d
```

---

## 🔒 Optional Hardening

These two features are part of the complete stack but require external resources, so they are not enabled by default. Enable them for a fully hardened deployment.

### At-rest Disk Encryption (LUKS)

Encrypts a separate data volume for Postgres data with automatic unlock on boot. Set in `env/supabase.yml`:

```yaml
supabase_encryption:
  enabled: true
luks_device: /dev/disk/by-id/YOUR_VOLUME_NAME
luks_mount_point: /data
```

Then uncomment the `luks` role in `playbook-supabase.yml` (see step 5).

### Automated S3 Backups

Dumps the database on a cron schedule and uploads to any S3-compatible storage. Set in `env/supabase.yml`:

```yaml
s3_remote_name: r2
s3_provider: Cloudflare
s3_access_key: <your-key>
s3_secret_key: <your-secret>
s3_endpoint: https://<your-endpoint>
s3_bucket_name: supabase-backups
```

Then uncomment the `backup` role in `playbook-supabase.yml` (see step 5).

---

## 📦 What Gets Deployed

| Container | Service | Port |
|-----------|---------|------|
| `studio` | Supabase Dashboard | 3001 |
| `kong` | API Gateway | 8000 |
| `auth` | GoTrue (Authentication) | 9999 |
| `rest` | PostgREST (REST API) | 3000 |
| `realtime` | Realtime (WebSockets) | 4000 |
| `storage` | Storage API | 5000 |
| `imgproxy` | Image Transformation | 5001 |
| `meta` | postgres-meta | 8080 |
| `functions` | Edge Functions (Deno) | 9000 |
| `db` | PostgreSQL 17 | 5432 |
| `supavisor` | Connection Pooler | 6543 |

Plus the security/monitoring stack: **Caddy** (reverse proxy + TLS + SSO), **UFW** firewall, **Fail2ban**, and **Grafana/Prometheus/Loki**.

---

## 📚 Advanced Features

| Feature | Description |
|---------|-------------|
| **Caddy Reverse Proxy + SSO** | Automatic TLS, GitHub/GitLab/Discord/Generic OIDC, basic auth, IP allow lists |
| **Monitoring Stack** | Grafana, Prometheus, Loki, Node Exporter, cAdvisor, Postgres Exporter |
| **LUKS Encryption** | At-rest disk encryption for Postgres data |
| **S3 Backups** | Automated cron-based backups to S3-compatible storage |
| **Fail2ban** | Brute-force protection for PostgreSQL |
| **UFW Firewall** | Fine-grained allow/deny rules |
| **Secure MCP Access** | MCP server restricted to localhost; authorized clients connect via SSH tunnel — no public exposure |

Full documentation: **[docs/advanced-docs.md](docs/advanced-docs.md)**

---

## 📄 License

MIT
# Ansible Supabase

One-command deployment of a **self-hosted Supabase stack** on any Debian/Ubuntu server. The playbook installs Docker, clones the latest Supabase release, generates all configuration files, and starts the full stack with a single command.

For production hardening (SSO, monitoring, firewall, backups, encryption) see [docs/advanced-docs.md](docs/advanced-docs.md).

---

## 🚀 Quick Start

### 1. 📋 Prerequisites

- A **Debian/Ubuntu server** with root or sudo access
- A **domain** with a DNS A record pointing to your server (e.g. `sb.example.com`)
- Ports **80** and **443** reachable for auto Let's Encrypt TLS and reverse proxy

### 2. 📥 Clone

```bash
git clone https://github.com/ankaboot-source/ansible-supabase.git
cd ansible-supabase
```

### 3. 🔑 Generate Supabase Required Keys

```bash
sh generate-keys.sh
```

This updates `env/supabase.yml` with all Supabase keys (JWT, anon key, service role key, Postgres password, and all cryptographic tokens).

### 4. ⚙️ Configure `env/supabase.yml`

Set the minimum required Supabase variables (every field tagged `#REQUIRED`):

```yaml
# ── System User ──────────────────────────
deploy_user: your-ssh-username
docker_users:
  - your-ssh-username

# ── Supabase Secrets ( Auto generated from step 3) ──────
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

# ── SMTP (for auth emails) ───────────────
smtp_admin_email: user@example.com
smtp_host: mail.example.com
smtp_user: user@example.com
smtp_password: <smtp-password>
```

#### Caddyfile Configuration (Reverse Proxy)

The Caddyfile configuration in `env/supabase.yml` defines how incoming requests are routed. For a minimal setup without SSO or basic auth, configure the `projects` section like this:

```yaml
projects:
  supabase:
    log_file: supabase-access
    domain: "sb.example.com"
    upstreams:
      # Dashboard
      - targets: ["localhost:3001"]
        paths: [""]
      # API routes
      - targets: ["localhost:8000"]
        paths:
          - /rest/v1/*
          - /auth/v1/*
          - /realtime/v1/*
          - /storage/v1/*
          - /functions/v1/*
```

> **Note:** The existing `env/supabase.yml` includes basic auth and IP whitelisting for basic dashboard protection. You can keep that configuration for minimal access control, or replace it with the example above for an unprotected dashboard. For SSO and production-grade security, see [docs/advanced-docs.md](docs/advanced-docs.md).

### 5. ▶️ Deploy

Run the installer (installs Ansible + Git if needed, then executes the playbook):

```bash
sudo ./install.sh
```

To see what will happen without making changes:

```bash
sudo ./install.sh -d
```



> **⚠️ Security Notice:** This minimal setup exposes the Supabase dashboard without any authentication. Anyone who can reach your server can access the Studio UI. For production deployments, enable basic auth, SSO, firewall rules, or the full Caddy reverse proxy — see [docs/advanced-docs.md](docs/advanced-docs.md).

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

---

## 📚 Advanced Features

| Feature | Description |
|---------|-------------|
| **Caddy Reverse Proxy + SSO** | Automatic TLS, GitHub/GitLab/Discord OAuth2, basic auth, IP allow lists |
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


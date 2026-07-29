# Ansible-Supabase — AI Context

## Purpose
Deterministic, configuration-based Ansible deployer for self-hosted Supabase with optional components (Caddy SSO, monitoring, fail2ban, backups, UFW, LUKS).

## Workflow
```
config.yml  ──>  setup.sh  ──>  env/supabase.yml  ──>  ansible-playbook
                                        │
                              playbook-supabase.yml
                              (regenerated from component toggles)
```

The user edits **only** `config.yml` (copy of `config.example.yml`). `setup.sh` validates, renders env vars into `env/supabase.yml`, regenerates `playbook-supabase.yml`, then runs `install.sh` (which bootstraps Ansible and executes the playbook).

## Key Files
| File | Purpose |
|------|---------|
| `config.example.yml` | User-facing template — add new config fields here |
| `config.yml` | Actual config (gitignored) — single source of truth |
| `setup.sh` | Orchestrator: validates, renders secrets, writes env vars |
| `env/supabase.yml` | Ansible vars file — rendered by `setup.sh`, consumed by playbook |
| `playbook-supabase.yml` | Generated playbook — roles enabled/disabled by component toggles |
| `install.sh` | Ansible runner (pip install + ansible-playbook) |

## Roles (`roles/`)
Each role follows Ansible convention:
- `tasks/main.yml` — idempotent deployment logic
- `defaults/main.yml` — default variables
- `templates/` — Jinja2 templates

### Role: docker
Installs Docker Engine (official APT repo), `docker-compose-plugin`, and adds `deploy_user` to the `docker` group. Always runs first as a prerequisite.

### Role: supabase
Clones the official Supabase repo, renders the Docker Compose stack, configures Kong (API gateway), sets up SSL certs (from Caddy or self-signed), and starts all Supabase services (Postgres, GoTrue, PostgREST, Realtime, Storage, Edge Functions, Studio, etc.). Four templates: `docker-compose-supabase.yml.j2`, `kong-supabase.yml.j2`, `env-supabase.j2`, `start-supabase.sh.j2`.

### Role: caddy
Reverse proxy + automatic TLS + SSO. Four provider templates in `templates/`:
- `Caddyfile-github.j2` — uses `github_allow_list` (match sub)
- `Caddyfile-gitlab.j2` — uses `gitlab_allow_list` (match email)
- `Caddyfile-generic.j2` — uses `generic_allow_list` (match email)
- `Caddyfile-discord.j2` — no allow list; uses role-based auth via `admin_role_id` + `discord_guild_id`

Template selection: `{ src: "Caddyfile-{{ SSO_PROVIDER }}", dest: "/etc/caddy/Caddyfile" }`. Also creates the systemd unit and reloads/restarts caddy on config changes.

### Role: monitor
Deploys Grafana + Prometheus + Loki + cAdvisor + Node Exporter + Postgres Exporter + Promtail via Docker Compose. Ten templates including datasources, dashboards (pre-built server-stats dashboard), and config files. Supports anonymous access or basic auth with customizable passwords.

### Role: fail2ban
Installs fail2ban with a Postgres-specific jail that watches `/var/log/postgresql/postgresql.log` for failed auth attempts and bans offending IPs for 24 hours. Three templates: jail, action, and filter configs.

### Role: backup
Installs a cron-based S3 backup script (`/usr/local/bin/s3-backup.sh`) that dumps the Supabase database (data-only + schema) via Supabase CLI and uploads compressed archives to any S3-compatible storage via rclone (Docker). One template: `s3-backup.sh.j2`.

### Role: ufw
Configures UFW firewall — always allows SSH (port 22), then applies allow/deny rules from config (supports per-rule IP/CIDR restrictions). One template: `reset_ufw.sh.j2`.

### Role: luks
Encrypts a secondary block device with LUKS2 (AES-XTS-512), creates an `ext4` filesystem, mounts it, and configures automatic unlock at boot via crypttab/fstab. Includes a safeguard against encrypting the root device. No templates; one handler for `update-initramfs`.

## Config Flow for New Variables
When adding a new variable that users should configure in `config.yml`:
1. Add the field to `config.example.yml` with a comment explaining usage
2. Add a `cfg_get` / `set_env_var` pair in `setup.sh` to read from `config.yml` and write to `env/supabase.yml`
3. If the variable is already a placeholder in `env/supabase.yml`, the `set_env_var` call (which uses `sed`) will replace it
4. If a new Ansible template variable is needed, add it as a placeholder to `env/supabase.yml`

## Config Reading/Writing in setup.sh
- `cfg_get "path.to.key"` — reads from `config.yml` via embedded Python YAML parser
- `cfg_bool "path.to.key"` — returns 0 if `true`, 1 otherwise
- `set_env_var "key" "value"` — writes `key: value` to `env/supabase.yml` via `sed -i`

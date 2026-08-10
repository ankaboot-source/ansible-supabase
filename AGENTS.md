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

## Operating on a Deployed Instance (Self-Hosted)

Most agents default to treating Supabase like the SaaS cloud product. This repo deploys a **self-hosted** stack on a VPS via Ansible, and the runtime shape is different. Read this section before running any command against a deployed instance.

### Context & Stack Architecture
- **Topology**: PostgreSQL and all Supabase services (GoTrue, PostgREST, Realtime, Storage, Edge Functions, Studio, Kong, Supavisor) run in Docker Compose on a single host. Caddy runs as a **native systemd service** (apt package, not a container) and acts as the reverse proxy + automatic TLS + OAuth2 SSO gateway (GitHub/GitLab/Generic/Discord).
- **Monitoring**: Observability is a separate Docker Compose stack — Prometheus, Loki, Grafana, cAdvisor, Node Exporter, Postgres Exporter, Promtail. Logflare/Analytics is **disabled** in self-hosted builds (Kong routes for `/analytics/v1/*` are commented out), so the Studio UI logs pane is empty by design.
- **Database**: PostgreSQL is bound to `127.0.0.1:5432` only — it is **never exposed to the public internet**. The Supavisor pooler is bound to `127.0.0.1:6543`. Both are reachable from the host loopback, not from outside.

### Where Things Live on the Host
| Path | Contents |
|------|----------|
| `/home/<deploy_user>/supabase/` | Cloned upstream Supabase repo (chowned to `deploy_user`) |
| `/home/<deploy_user>/supabase/docker/` | Rendered `docker-compose-supabase.yml`, `.env`, `start-supabase.sh`, Kong config (`volumes/api/kong.yml`) — this is the stack working directory (`supabase_path` var, default `supabase/docker`) |
| `/home/<deploy_user>/supabase/docker/volumes/functions/` | Edge Function source — each function is a subfolder (`<name>/index.ts`) mounted into the edge-runtime container (`/home/deno/functions`) and Studio (`/app/edge-functions`) |
| `/opt/postgres-certs/` | Postgres SSL certs (mounted read-only into the db container) |
| `/var/log/postgresql/` | Postgres logs (host-mounted into the db container — never inside the data dir) |
| `/etc/caddy/Caddyfile` | Caddy config (rendered from the SSO provider template) |
| `config.yml` (repo root, gitignored) | The single source of truth for the deploy — user edits only this |
| `env/supabase.yml` (repo root) | Rendered Ansible vars — consumed by the playbook, regenerated by `setup.sh` |

> **There is no `/etc/supabase/instance.json` manifest in this repo.** Do not invent one. The source of truth for connection parameters is `env/supabase.yml` (on the control machine) and the rendered `.env` at `/home/<deploy_user>/supabase/docker/.env` (on the deployed host). Read those before guessing ports, passwords, or container names.

### ⛔ Hard Rules (Never Violate)
1. **Read the rendered config first.** Always read `env/supabase.yml` (locally) or `/home/<deploy_user>/supabase/docker/.env` (on the host) BEFORE running commands. Never guess ports, keys, or container names — the `deploy_env` suffix can change container names (e.g. `supabase-db-prod`).
2. **No direct external DB access.** Never attempt a raw `psql` connection from your local machine — Postgres is bound to `127.0.0.1` and the firewall (UFW) blocks external DB access. DB tasks and migrations MUST run on the host via `docker exec supabase-db ...`, the Supabase CLI, or MCP over an SSH tunnel.
3. **Port routing**:
   - **Migrations / direct DDL**: Use the direct Postgres port `5432` (via `docker exec supabase-db psql ...` or the loopback-bound listener). Never run migrations through the pooler.
   - **App queries / TS typegen**: Use the Supavisor pooler port `6543` (transaction mode).
4. **Logs & monitoring**: Do not use the Studio UI for logs (Logflare is disabled). Use `docker logs --tail 100 <container>` or Grafana/Loki/Promtail.
5. **Caddy is a systemd service, not a container.** Inspect Caddy/SSO logs with `journalctl -u caddy -n 100 --no-pager`, not `docker logs caddy`. Restart with `systemctl restart caddy`, not `docker restart caddy`.

### 🚀 Standard Operating Recipes

**Run a migration**:
1. Read DB parameters from `env/supabase.yml` / the rendered `.env` (`POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT=5432`).
2. Verify the latest backup succeeded (the `backup` role runs a cron S3 dump).
3. Apply the migration on the host, pointing at the **direct** port:
   ```bash
   docker exec -i supabase-db psql -U postgres -d <POSTGRES_DB> < migration.sql
   ```
   Or via Supabase CLI / MCP configured against `postgresql://postgres:<pwd>@127.0.0.1:5432/<db>`.

**Regenerate TypeScript types**:
```bash
supabase gen types typescript --db-url "postgresql://postgres:<pwd>@127.0.0.1:5432/<db>" > types/supabase.ts
```
Use the direct port (`5432`), not the pooler.

**Deploy / update an Edge Function**:
1. Copy the function folder onto the host under the functions volume (each function is a directory containing `index.ts`):
   ```bash
   scp -r ./my-function user@host:/home/<deploy_user>/supabase/docker/volumes/functions/
   ```
2. Restart the functions service so the edge-runtime picks up the new/changed code:
   ```bash
   cd /home/<deploy_user>/supabase/docker && docker compose restart functions
   ```
3. Verify: `curl https://<domain>/functions/v1/<name>` (Kong routes `/functions/v1/*` to the edge-runtime).
- `supabase functions deploy` targets Supabase **Cloud** projects and does **not** deploy to a self-hosted instance — self-hosted deployment is filesystem-based (copy into `volumes/functions` + restart). Function env vars/secrets live in the compose `environment:` block (or a `.env.functions` override); changing them requires recreating the container, not just restarting.

**Inspect logs & services**:
1. Resolve container names: `cd /home/<deploy_user>/supabase/docker && docker compose ps` (e.g. `supabase-db`, `supabase-kong`, `supabase-rest`, `supabase-auth`, `supabase-studio`, `supabase-pooler`, `grafana`, `promtail`).
2. Fetch recent logs: `docker logs --tail 100 <container_name>`.
3. For HTTP 401/403 on Studio/Grafana (SSO issues): `journalctl -u caddy -n 100 --no-pager` — Caddy is a systemd unit, not a container.

**Restart services safely**:
- Never blind-`docker restart` the whole stack. Target a specific service:
  ```bash
  cd /home/<deploy_user>/supabase/docker
  docker compose restart rest        # PostgREST (schema cache reload)
  docker compose restart kong        # Kong gateway
  docker compose restart auth        # GoTrue
  ```
- To pick up `.env` / compose changes, `docker compose up -d` alone is **not** reliable — run `start-supabase.sh` (which does `down && up`), or `docker compose down && docker compose up -d` manually.

### 🧰 Troubleshooting Matrix

| Symptom | Common Cause | Fix |
| :--- | :--- | :--- |
| `Connection refused` / `Timeout` to `5432` from outside the host | DB is bound to `127.0.0.1` + UFW blocks external DB | SSH-tunnel into the host, then use `docker exec supabase-db` or loopback `127.0.0.1:5432` |
| `401 Unauthorized` on Studio/Grafana | Caddy SSO session expired or OAuth callback URL misconfigured | `journalctl -u caddy -n 100 --no-pager`; verify `API_EXTERNAL_URL` / `SITE_URL` in the rendered `.env` |
| PostgREST doesn't see new tables | PostgREST schema cache out of sync | `docker compose restart rest` (container `supabase-rest`) |
| Migration hangs or fails | Migration ran through the Supavisor pooler (`6543`) | Re-run pointing strictly at the **direct** port `5432` (`docker exec supabase-db psql ...`) |
| Empty logs in Studio UI | Logflare/Analytics is disabled in self-hosted builds | Use `docker logs --tail 100 <container>` or Grafana/Loki |
| `403 {"message":"IP address not allowed: ..."}` on `/mcp` | Docker NATs host-originated traffic to the bridge gateway IP; the `ip-restriction` allow list must include the pinned subnet gateway (`172.28.0.1`) | See **MCP / Docker networking** pitfalls below; update `mcp_allowed_ips` to match the pinned subnet gateway |
| Kong fails to start after a route/plugin edit | A malformed plugin (e.g. `ip-restriction` with a YAML flow-list bug) breaks the startup healthcheck | Test on a staging route first; keep risky config commented until the runtime rejection is understood (see Kong pitfall below) |
| Edge Function returns `404` or serves stale code | Function folder not in `volumes/functions/` (`<name>/index.ts`), or edge-runtime not restarted after the copy | Copy the folder to `<supabase_path>/volumes/functions/` and `docker compose restart functions` |
| `supabase functions deploy` fails against the self-hosted host | The CLI deploys to Supabase **Cloud**, not self-hosted instances | Deploy by copying the function into `volumes/functions/` and restarting the `functions` service |

## Known Pitfalls & Lessons Learned

These are problems encountered while building this repo, and how they were fixed. Do not repeat them.

### Ansible / Jinja2
- **`environment` clashes with Ansible's reserved keyword** — using it as a variable name silently broke the container-name suffix rendering. Use `deploy_env`. Check against the literal placeholder (`!= 'changeit'`), not truthiness — the placeholder is non-empty.
- **`{% if %}` blocks leave stray whitespace/newlines in templated compose files** under trim_blocks. Use inline expressions instead: `{{ '-' + deploy_env if deploy_env != 'changeit' else '' }}`.
- **`{% for %}` block loops collapse onto one line under trim_blocks** and break YAML-only consumers. The Kong template's `ip-restriction` allow list must stay an inline expression (`allow: {{ mcp_allowed_ips }}` renders a YAML flow list) — the previous `{%- for ip in ... %}`/`{%- endfor %}` form mangled `allow:` + `deny: []` onto one line and Kong refused to start (`block sequence entries are not allowed in this context`). `verify-secure-mcp.py` renders under all `trim_blocks`/`lstrip_blocks` combos to catch this class.
- **`docker compose up -d` does not reliably pick up config/env changes.** `start-supabase.sh` must run `down && up` for changes to take effect.
- **Postgres refuses to init if its log dir is inside the data dir** ("data directory exists but is not empty"). Log to `/var/log/postgresql` (host-mounted into the container), never `/var/lib/postgresql/data/log`.
- **Mounted Postgres dirs and certs must use the image's real UID/GID** (currently 100/101 for the supabase postgres image), not guessed values.
- **After cloning the Supabase repo as root, chown the whole tree to `deploy_user` recursively**, or the stack can't write to it.
- **Kong route/plugin changes can break Kong's startup healthcheck** and take the whole API down (e.g. an `ip-restriction` plugin on `/mcp`). Test on a staging route before rolling out; keep risky config commented until the runtime rejection is understood. The original `/mcp` `ip-restriction` rejection was later root-caused to a Docker NAT source-IP mismatch — see **MCP / Docker networking** below.
- **`foo.bar is defined` raises UndefinedError when `foo` itself is undefined** — guarding a nested attribute with `is defined` is not enough. Use `foo is defined and foo.bar is defined`, or `(foo | default({})).bar | default('')` for a chain.

### Postgres SSL / Certificates
- **Never put a config-driven value in `roles/*/defaults/main.yml`** — defaults are for constants only. The Postgres cert used to be generated with a hardcoded `postgres_domain: your-domain.com` placeholder, so every deployed cert had `CN=your-domain.com` and matched nothing. The role now reads `projects.supabase.domain` (the Caddy config domain, e.g. `sb.example.com`) directly, and an `assert` fails fast if it's still a placeholder.
- **A self-signed cert with only a `CN` (no SANs) fails `sslmode=verify-full`.** Generate with `-addext "subjectAltName=DNS:<domain>,DNS:localhost,IP:127.0.0.1[,IP:<server_ip>]"` so hostname verification works whether clients connect by domain, loopback, or the server's public IP.
- **`openssl req` writes the private key world-readable (0644)** and Postgres refuses to start ("private key file has group or world access"). chmod `0600` the key / `0644` the cert and chown both to the postgres image UID/GID (100/101) — done by the `Set ownership and permissions` task.
- **The `creates:` guard meant an existing wrong cert was never regenerated** after a domain change. Check the live cert with `openssl x509 -noout -subject -nameopt RFC2253` and regenerate when it doesn't match the configured domain. Always use `-nameopt RFC2253` — the default subject format differs between OpenSSL 1.1.1 (`/CN=...`) and 3.x (`CN = ...`), which breaks naive `grep` comparisons.
- **Prefer Caddy's real Let's Encrypt cert over self-signed** — look it up at `caddy_cert_base_path/<domain>/` (per-domain directory) and copy it; only fall back to self-signed when it's missing. The lookup only works if `caddy_cert_base_path` matches where Caddy actually stores certs.
- **SSL was dead code until the compose args were uncommented** — the db container had `-c ssl=on` / `ssl_cert_file` / `ssl_key_file` commented out, so Postgres ignored the mounted certs entirely.

### setup.sh / config flow
- **`set_env_var` uses `sed` on `key: value` lines — never run it on a list variable**, it corrupts the YAML (e.g. `docker_users`). For lists, replace only the `- item` line and leave the key line untouched.
- **When a rendered value may be empty or a placeholder, guard the write** with `[[ -n "$val" ]]` so template rendering doesn't break.
- **Regenerate the whole playbook from component toggles** — never edit it line-by-line/uncomment fragments.

### Monitoring
- **Promtail's push URL must have a valid scheme** (`http://loki:3100/...`, not `http//loki:3100`).
- **Promtail can't read Docker container logs without both** the `/var/lib/docker/containers` mount and a `docker: {}` pipeline stage.
- **Bind Grafana/Loki/Prometheus/cAdvisor/node-exporter/Studio to `127.0.0.1` by default** — do not expose monitoring/admin ports on all interfaces.
- **Grafana home dashboards are silently ignored unless wired in**: templates must be named `home.json.j2`, copied to the target path, and enabled via `default_home_dashboard_path` in grafana.ini. Duplicate `home.json` / `home.json.j2` files cause confusion.
- **Grafana dashboard exports use `{{label_name}}` legend syntax that collides with Ansible**: a verbatim dashboard JSON shipped as `server-stats.json.j2` rendered `{{device}}`/`{{name}}`/`{{instance}}` as Ansible vars and failed with `'device' is undefined`. Wrap dashboard JSON in `{% raw %}`...`{% endraw %}` (renders byte-identical; no real Ansible vars in such files).
- **Never hardcode an OAuth provider as `enabled = true`** — gate it behind a toggle so placeholder credentials can't break Grafana startup.

### Caddy / SSO
- **After writing/fmt-ing the Caddyfile, reload/start caddy** (handler + systemd enable) or the new config is never applied.
- **SSO allow lists are provider-specific**: github matches sub, gitlab/generic match email, discord uses role-based auth and has no allow list.

### Auth / Email
- **An empty `ADDITIONAL_REDIRECT_URLS` makes GoTrue fall back to the SITE_URL root** and breaks the magic-link callback. Always template it from config.
- **Don't point `MAILER_TEMPLATES_*` at storage-object URLs** — they return 400 and GoTrue falls back to plaintext. Use a dedicated templates base URL.
- **GoTrue subject placeholders resolve empty** unless titles are injected via user_metadata — use static subjects instead.
- **The magic-link flow uses its own `magic_link` template type**, separate from `confirmation`. It needs dedicated `MAILER_SUBJECTS_MAGIC_LINK` / `MAILER_TEMPLATES_MAGIC_LINK` vars.
- **Keep OTP expiry long enough** (1h) for email flows.
- **Keep mailer templates/subjects brand-agnostic**; brand-specific values are injected via CI/CD overrides.

### Supabase template sync
- **Templates drift from upstream self-hosted releases** (e.g. postgres 15→17, removed analytics/vector, SAML routes, new healthchecks). Sync against the latest upstream compose on a regular basis.
- **Never bake project-specific changes into the default templates** (e.g. m3llm shared networks) — apply them via CI/CD overrides instead.

### MCP / Docker networking
- **`ip-restriction` on `/mcp` with `127.0.0.1`/`::1` can never match** — Docker source-NATs every host-originated connection (localhost, SSH tunnels) to the Docker bridge gateway IP before it reaches Kong, so Kong sees the gateway, not the loopback address. A request from the server itself returns `403 {"message":"IP address not allowed: 172.18.0.1"}`. This was the real cause of the QA 502 that forced commit `b44b6a6` to revert the original MCP feature (`0fe79d3`).
- **Pin the compose network subnet so the gateway is deterministic** — `docker-compose-supabase.yml.j2` declares `networks.default.ipam.config.subnet: 172.28.0.0/16`, making the gateway always `172.28.0.1`. `mcp_allowed_ips` must stay in sync with this gateway (default `[172.28.0.1]`). Without the pin, `docker compose down && up` re-issues whatever subnet is free, silently re-breaking the allow list.
- **The Kong/compose template now ships a top-level `networks:` block** — anything that blind-appends a second `networks:` key (e.g. the m3llm CI/CD `deploy-supabase-stack.yml`, which adds `shared-net`) produces a YAML duplicate-key error and breaks the deploy. Merge into the existing block instead (`grep -q '^networks:'` + `sed -i '/^networks:/a\...'`), never append a second block.
- **`verify-secure-mcp.py` only renders the template — it never runs Kong.** A syntactically valid but wrong allow list (e.g. `127.0.0.1`) ships green. When touching MCP, cross-check `mcp_allowed_ips` against the pinned subnet gateway.

### Security-by-default
- **The MCP endpoint must never be publicly reachable**; prefer SSH-tunnel access over opening Kong routes.
- **Docs/README must default to the full secure-featured setup**, never the unprotected minimal one.

## Config Flow for New Variables
When adding a new variable that users should configure in `config.yml`:
1. Add the field to `config.example.yml` with a comment explaining usage
2. Add a `cfg_get` / `set_env_var` pair in `setup.sh` to read from `config.yml` and write to `env/supabase.yml`
3. If the variable is already a placeholder in `env/supabase.yml`, the `set_env_var` call (which uses `sed`) will replace it
4. If a new Ansible template variable is needed, add it as a placeholder to `env/supabase.yml`

See the **Ansible / Jinja2** and **setup.sh / config flow** pitfall subsections above — especially: never `set_env_var` a list, guard writes that can be empty, and avoid Ansible reserved words as variable names.

## Config Reading/Writing in setup.sh
- `cfg_get "path.to.key"` — reads from `config.yml` via embedded Python YAML parser
- `cfg_bool "path.to.key"` — returns 0 if `true`, 1 otherwise
- `set_env_var "key" "value"` — writes `key: value` to `env/supabase.yml` via `sed -i`

## Migration Script (`migrate.sh`)

Migrates a Supabase Cloud project into a self-hosted instance. Lives at `migrate.sh` with config at `env/migrate.yml` (copy of `env/migrate.example.yml`).

### Architecture
Four phases run sequentially:
1. **DB dump+restore** — probes all schemas from source, dumps them in a single `pg_dump`, restores in a single `pg_restore`
2. **Auth users** — data-only dump of `auth.users` + `auth.identities` (preserves UUIDs)
3. **Storage objects** — `rclone copy` from source S3 to target S3 (best-effort)
4. **Manual steps report** — prints checklist for post-migration tasks

### Key Difficulty: Cross-Schema Dependencies (Triggers)
**Problem:** The original per-schema loop (`for schema in ...; do pg_dump --schema=$s; pg_restore; done`) dumped/restored schemas one at a time. Triggers on `public` tables referencing `auth.*` functions failed because `auth` wasn't restored yet when `public` ran. The `--exit-on-error` flag caused those trigger failures to abort the schema restore, so triggers were silently lost.

**Fix:** Replace per-schema loop with a single `pg_dump` (all `--schema=` flags) followed by a single `pg_restore`. pg_dump resolves inter-schema dependency ordering internally, so triggers are created in the correct order. Removed `--exit-on-error` (harmless "already exists" DDL errors) and `--clean --if-exists` (target is fresh, cascade-drop not needed).

### Key Difficulty: Schema Discovery
**Problem:** The original script hardcoded a schema list (`SCHEMAS=(public auth storage ...)`). This missed custom schemas like `private`, `supabase_migrations`, and required manual updates when new schemas were added.

**Fix:** Probe `information_schema.schemata` dynamically, excluding only Postgres built-in schemas (`pg_catalog`, `information_schema`, `pg_toast`) and temporary schemas (`pg_temp_%`, `pg_toast_temp_%`). All remaining schemas (user + Supabase system) are dumped — Supabase system schema DDL produces harmless "already exists" errors, but their data (auth users, storage metadata, etc.) is migrated.

### Key Difficulty: Temporary Cloud Schemas
**Problem:** Supabase Cloud Postgres creates ephemeral `pg_temp_N` and `pg_toast_temp_N` schemas for connection pooling. These have reserved `pg_` prefix names that fail on restore with "unacceptable schema name".

**Fix:** Added `NOT LIKE 'pg\_temp\_%'` and `NOT LIKE 'pg\_toast\_temp\_%'` to the schema probe query.

### Key Requirement: supabase_admin User
The target `db_url` must use `supabase_admin` (superuser), not `postgres`. Only `supabase_admin` has the privileges to restore DDL in the `auth` and `storage` schemas. The `migrate.example.yml` now documents this requirement and provides the correct connection string format.

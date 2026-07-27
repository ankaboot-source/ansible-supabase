#!/bin/bash
# =============================================================================
# setup.sh — Deterministic, configuration-based Supabase installer.
# =============================================================================
# Reads config.yml, generates secrets, renders env/supabase.yml, enables the
# selected components in playbook-supabase.yml, then runs the deployment.
#
# Usable by humans and AI agents. The only file you need to edit is config.yml
# (copy it from config.example.yml).
#
# Usage:
#   sudo bash setup.sh              # generate + deploy
#   bash setup.sh --dry-run         # preview without modifying files
#   bash setup.sh --yes             # non-interactive (AI-friendly)
#   bash setup.sh --help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"
EXAMPLE_CONFIG="${SCRIPT_DIR}/config.example.yml"
ENV_FILE="${SCRIPT_DIR}/env/supabase.yml"
PLAYBOOK_FILE="${SCRIPT_DIR}/playbook-supabase.yml"
GENERATE_KEYS="${SCRIPT_DIR}/generate-keys.sh"

DRY_RUN=0
ASSUME_YES=0
VERBOSE=0

# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

log()     { printf "${BLUE}[setup]${NC} %s\n" "$*"; }
ok()      { printf "${GREEN}[ok]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[warn]${NC} %s\n" "$*" >&2; }
die()     { printf "${RED}[error]${NC} %s\n" "$*" >&2; exit 1; }

# ─── Help ────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
setup.sh — Deterministic Supabase installer (configuration-based)

Usage:
  sudo bash setup.sh [options]

Options:
  --dry-run        Preview actions without modifying any files
  --yes            Non-interactive (skip confirmation prompts) — for AI/CI
  -v, --verbose    Verbose output
  -h, --help       Show this help and exit

Workflow:
  1. Copy config.example.yml to config.yml
  2. Edit the REQUIRED section in config.yml
  3. Run: sudo bash setup.sh

The script:
  - Validates required fields are filled (not "changeit")
  - Auto-generates cryptographic secrets (unless secrets.generate: false)
  - Renders env/supabase.yml from your config
  - Enables selected components in playbook-supabase.yml
  - Runs the Ansible deployment via install.sh
EOF
}

# ─── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=1; shift ;;
    --yes)      ASSUME_YES=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

[[ $VERBOSE -eq 1 ]] && set -x

# ─── Preflight checks ────────────────────────────────────────────────────────
[[ -f "$EXAMPLE_CONFIG" ]] || die "config.example.yml not found in $SCRIPT_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
  die "config.yml not found.

  Copy the example and edit the REQUIRED section:
    cp config.example.yml config.yml
    # edit config.yml, then re-run:
    bash setup.sh"
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required (Ansible depends on it). Install with: sudo apt install -y python3"

[[ -f "$ENV_FILE" ]]        || die "env/supabase.yml not found in $SCRIPT_DIR"
[[ -f "$PLAYBOOK_FILE" ]]   || die "playbook-supabase.yml not found in $SCRIPT_DIR"

# ─── YAML parsing via python3 ─────────────────────────────────────────────────
# Reads a value from config.yml. Usage: cfg_get "required.deploy_user"
cfg_get() {
  python3 - "$CONFIG_FILE" "$1" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
keys = sys.argv[2].split('.')
node = data
for k in keys:
    if isinstance(node, dict) and k in node:
        node = node[k]
    else:
        print("")  # missing -> empty string
        sys.exit(0)
# Print scalar; for bools print true/false; for lists/dicts print yaml
if isinstance(node, bool):
    print("true" if node else "false")
elif isinstance(node, (list, dict)):
    print(yaml.dump(node, default_flow_style=False).strip())
else:
    print(node if node is not None else "")
PYEOF
}

# Reads a boolean value; returns 0 if true, 1 if false/missing.
cfg_bool() {
  local val
  val="$(cfg_get "$1")"
  [[ "$val" == "true" ]]
}

# ─── Validation ───────────────────────────────────────────────────────────────
log "Validating config.yml…"

REQUIRED_FIELDS=(
  "required.deploy_user"
  "required.site_url"
  "required.api_external_url"
  "required.supabase_domain"
  "required.smtp_admin_email"
  "required.smtp_host"
  "required.smtp_user"
  "required.smtp_password"
)

MISSING=()
for field in "${REQUIRED_FIELDS[@]}"; do
  val="$(cfg_get "$field")"
  if [[ -z "$val" || "$val" == "changeit" ]]; then
    MISSING+=("$field")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  die "The following REQUIRED fields in config.yml are still set to 'changeit' or empty:

  $(printf '  - %s\n' "${MISSING[@]}")

Edit config.yml and fill in every field under the REQUIRED section."
fi

# Warn on enabled components with placeholder advanced config.
warn_component_placeholders() {
  local warnings=0
  if cfg_bool "components.backup"; then
    for f in s3_remote_name s3_provider s3_access_key s3_secret_key s3_endpoint s3_bucket_name; do
      v="$(cfg_get "advanced.backup.$f")"
      if [[ -z "$v" || "$v" == "changeit" ]]; then
        warn "components.backup is enabled but advanced.backup.$f is '$v'."
        warnings=$((warnings + 1))
      fi
    done
  fi
  if cfg_bool "components.caddy"; then
    for f in sso_client_id sso_client_secret; do
      v="$(cfg_get "advanced.caddy.$f")"
      if [[ -z "$v" || "$v" == "changeit" ]]; then
        warn "components.caddy is enabled but advanced.caddy.$f is '$v'."
        warnings=$((warnings + 1))
      fi
    done
  fi
  if cfg_bool "components.luks"; then
    v="$(cfg_get "advanced.luks.device")"
    if [[ -z "$v" || "$v" == "changeit" ]]; then
      warn "components.luks is enabled but advanced.luks.device is '$v'."
      warnings=$((warnings + 1))
    fi
  fi
  return $warnings
}

if ! warn_component_placeholders; then
  warn "Some enabled components have unconfigured advanced fields. Deployment may fail."
  [[ $ASSUME_YES -eq 0 ]] && {
    read -rp "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted by user."
  }
fi

ok "config.yml validated."

# ─── Dry-run summary ──────────────────────────────────────────────────────────
if [[ $DRY_RUN -eq 1 ]]; then
  log "DRY RUN — no files will be modified."
  log "Would render: $ENV_FILE"
  log "Would update: $PLAYBOOK_FILE"
  log "Components to enable:"
  for c in caddy monitor fail2ban backup ufw luks; do
    if cfg_bool "components.$c"; then
      printf "  + %s\n" "$c"
    fi
  done
  log "Would run: bash install.sh"
  ok "Dry run complete. Re-run without --dry-run to deploy."
  exit 0
fi

# ─── Confirmation ─────────────────────────────────────────────────────────────
if [[ $ASSUME_YES -eq 0 ]]; then
  printf "About to render env/supabase.yml, update the playbook, and deploy.\n"
  read -rp "Proceed? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted by user."
fi

# ─── Secret generation ───────────────────────────────────────────────────────
gen_hex() { openssl rand -hex "$1"; }
gen_b64() { openssl rand -base64 "$1"; }
b64url()  { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
gen_jwt() {
  local jwt_secret="$1" payload="$2"
  local header='{"alg":"HS256","typ":"JWT"}'
  local hdr pld sig
  hdr=$(printf '%s' "$header" | b64url)
  pld=$(printf '%s' "$payload" | b64url)
  sig=$(printf '%s' "$hdr.$pld" | openssl dgst -binary -sha256 -hmac "$jwt_secret" | b64url)
  echo "$hdr.$pld.$sig"
}

# sed helper: replace a `key: value` line in env/supabase.yml (anchored at line start).
set_env_var() {
  local key="$1" val="$2"
  # Escape forward slashes and ampersands for sed replacement.
  local escaped
  escaped="$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')"
  sed -i "s|^${key}:.*|${key}: ${escaped}|" "$ENV_FILE"
}

log "Rendering env/supabase.yml…"

# Required fields
set_env_var "deploy_user"        "$(cfg_get "required.deploy_user")"
set_env_var "site_url"           "$(cfg_get "required.site_url")"
set_env_var "api_external_url"   "$(cfg_get "required.api_external_url")"
set_env_var "smtp_admin_email"   "$(cfg_get "required.smtp_admin_email")"
set_env_var "smtp_host"          "$(cfg_get "required.smtp_host")"
set_env_var "smtp_user"          "$(cfg_get "required.smtp_user")"
set_env_var "smtp_password"      "$(cfg_get "required.smtp_password")"

# docker_users is a list; the template has `- changeit` under it. Replace the
# first list item line (do NOT touch the `docker_users:` key — it must stay a list).
sed -i "s|^  - changeit.*|  - $(cfg_get "required.deploy_user")|" "$ENV_FILE"

# supabase dashboard domain (inside projects.supabase.domain)
python3 - "$ENV_FILE" "$(cfg_get "required.supabase_domain")" <<'PYEOF'
import sys, re
path, domain = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
# Replace the domain line under the supabase project block.
content = re.sub(
    r'(\nprojects:\n  supabase:.*?\n    domain:\s*)"[^"]*"',
    r'\1"%s"' % domain,
    content,
    count=1,
    flags=re.DOTALL,
)
with open(path, 'w') as f:
    f.write(content)
PYEOF

# deploy_env (optional)
deploy_env="$(cfg_get "advanced.deploy_env")"
if [[ -n "$deploy_env" && "$deploy_env" != "changeit" ]]; then
  set_env_var "deploy_env" "$deploy_env"
fi

# Secrets
if cfg_bool "secrets.generate"; then
  log "Auto-generating cryptographic secrets…"
  jwt_secret="$(gen_b64 30)"
  iat="$(date +%s)"
  exp=$((iat + 157680000)) # 5 years
  anon_key="$(gen_jwt "$jwt_secret" "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")"
  service_role_key="$(gen_jwt "$jwt_secret" "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")"

  set_env_var "postgres_db_pwd"              "$(gen_hex 16)"
  set_env_var "sb_jwt_secret"                "$jwt_secret"
  set_env_var "sb_anon_key"                  "$anon_key"
  set_env_var "sb_service_role_key"          "$service_role_key"
  set_env_var "secret_key_base"              "$(gen_b64 48)"
  set_env_var "vault_enc_key"                "$(gen_hex 16)"
  set_env_var "pg_meta_crypto_key"           "$(gen_b64 24)"
  set_env_var "logflare_public_access_token" "$(gen_b64 24)"
  set_env_var "logflare_private_access_token" "$(gen_b64 24)"
  set_env_var "s3_protocol_access_key_id"    "$(gen_hex 16)"
  set_env_var "s3_protocol_access_key_secret" "$(gen_hex 32)"
  ok "Secrets generated and written to env/supabase.yml."
else
  log "Using user-provided secrets from config.yml…"
  set_env_var "postgres_db_pwd"              "$(cfg_get "secrets.postgres_db_pwd")"
  set_env_var "sb_jwt_secret"                "$(cfg_get "secrets.sb_jwt_secret")"
  set_env_var "sb_anon_key"                  "$(cfg_get "secrets.sb_anon_key")"
  set_env_var "sb_service_role_key"           "$(cfg_get "secrets.sb_service_role_key")"
  set_env_var "secret_key_base"              "$(cfg_get "secrets.secret_key_base")"
  set_env_var "vault_enc_key"                "$(cfg_get "secrets.vault_enc_key")"
  set_env_var "pg_meta_crypto_key"           "$(cfg_get "secrets.pg_meta_crypto_key")"
  set_env_var "logflare_public_access_token" "$(cfg_get "secrets.logflare_public_access_token")"
  set_env_var "logflare_private_access_token" "$(cfg_get "secrets.logflare_private_access_token")"
  set_env_var "s3_protocol_access_key_id"    "$(cfg_get "secrets.s3_protocol_access_key_id")"
  set_env_var "s3_protocol_access_key_secret" "$(cfg_get "secrets.s3_protocol_access_key_secret")"
  ok "User-provided secrets written to env/supabase.yml."
fi

# ─── Advanced component config → env/supabase.yml ─────────────────────────────
if cfg_bool "components.caddy"; then
  set_env_var "SSO_PROVIDER"        "$(cfg_get "advanced.caddy.sso_provider")"
  set_env_var "root_domain"          "$(cfg_get "advanced.caddy.root_domain")"
  set_env_var "base_auth_domain"     "$(cfg_get "advanced.caddy.base_auth_domain")"
  # SSO credentials are provider-specific; map common fields.
  case "$(cfg_get "advanced.caddy.sso_provider")" in
    github)
      set_env_var "github_oauth_client_id"     "$(cfg_get "advanced.caddy.sso_client_id")"
      set_env_var "github_oauth_client_secret" "$(cfg_get "advanced.caddy.sso_client_secret")"
      ;;
    gitlab)
      set_env_var "gitlab_oauth_client_id"     "$(cfg_get "advanced.caddy.sso_client_id")"
      set_env_var "gitlab_oauth_client_secret" "$(cfg_get "advanced.caddy.sso_client_secret")"
      ;;
    discord)
      set_env_var "discord_oauth_client_id"    "$(cfg_get "advanced.caddy.sso_client_id")"
      set_env_var "discord_oauth_client_secret" "$(cfg_get "advanced.caddy.sso_client_secret")"
      ;;
    Generic)
      set_env_var "oidc_client_id"             "$(cfg_get "advanced.caddy.sso_client_id")"
      set_env_var "oidc_client_secret"         "$(cfg_get "advanced.caddy.sso_client_secret")"
      ;;
  esac
fi

if cfg_bool "components.monitor"; then
  set_env_var "GRAFANA_SERVER_ROOT_URL" "$(cfg_get "advanced.monitor.grafana_root_url")"
  set_env_var "GRAFANA_ALERT_HOST"      "$(cfg_get "advanced.monitor.grafana_alert_host")"

  # monitor domain (inside projects.monitor.domain)
  python3 - "$ENV_FILE" "$(cfg_get "advanced.monitor.domain")" <<'PYEOF'
import sys, re
path, domain = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
content = re.sub(
    r'(\nprojects:.*?\n  monitor:.*?\n    domain:\s*)"[^"]*"',
    r'\1"%s"' % domain,
    content,
    count=1,
    flags=re.DOTALL,
)
with open(path, 'w') as f:
    f.write(content)
PYEOF

  if cfg_bool "advanced.monitor.anonymous_enabled"; then
    set_env_var "GRAFANA_AUTH_ANONYMOUS_ENABLED" "true"
  else
    set_env_var "GRAFANA_AUTH_ANONYMOUS_ENABLED" "false"
    set_env_var "GRAFANA_AUTH_BASIC_ENABLED" "true"
    set_env_var "GRAFANA_ADMIN_PASSWORD" "$(cfg_get "advanced.monitor.admin_password")"
  fi
fi

if cfg_bool "components.backup"; then
  set_env_var "s3_remote_name"    "$(cfg_get "advanced.backup.s3_remote_name")"
  set_env_var "s3_provider"       "$(cfg_get "advanced.backup.s3_provider")"
  set_env_var "s3_access_key"     "$(cfg_get "advanced.backup.s3_access_key")"
  set_env_var "s3_secret_key"     "$(cfg_get "advanced.backup.s3_secret_key")"
  set_env_var "s3_endpoint"       "$(cfg_get "advanced.backup.s3_endpoint")"
  set_env_var "s3_bucket_name"    "$(cfg_get "advanced.backup.s3_bucket_name")"
  set_env_var "backup_cron_hour"  "$(cfg_get "advanced.backup.backup_cron_hour")"
  set_env_var "backup_cron_minute" "$(cfg_get "advanced.backup.backup_cron_minute")"
fi

if cfg_bool "components.luks"; then
  set_env_var "luks_device"     "$(cfg_get "advanced.luks.device")"
  set_env_var "luks_mount_point" "$(cfg_get "advanced.luks.mount_point")"
  # Enable the encryption flag
  python3 - "$ENV_FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
content = re.sub(
    r'(supabase_encryption:\n  enabled:\s*)false',
    r'\1true',
    content,
)
with open(path, 'w') as f:
    f.write(content)
PYEOF
fi

ok "env/supabase.yml rendered."

# ─── Playbook component toggling ─────────────────────────────────────────────
# Regenerate playbook-supabase.yml deterministically from the component toggles.
# This avoids fragile line-by-line uncommenting and keeps the playbook structure
# valid YAML regardless of which components are enabled.
log "Updating playbook-supabase.yml with selected components…"

python3 - "$PLAYBOOK_FILE" "$CONFIG_FILE" <<'PYEOF'
import sys, yaml
path, cfg_path = sys.argv[1], sys.argv[2]
with open(cfg_path) as f:
    cfg = yaml.safe_load(f)
components = cfg.get("components", {}) or {}

# Preserve the original header (everything up to and including the supabase
# prerequisite role + the advanced-roles banner comment), then append the
# enabled roles in a fixed canonical order.
with open(path) as f:
    original = f.read()

# Build the new roles list. Prerequisites are always present.
header = """---
- hosts: localhost
  become: true
  roles:
   # Prerequisite — always needed
   - docker
   - supabase

   # ─── Advanced Roles ───────────────────────────────
   # Enabled via config.yml (components). See docs/advanced-docs.md.
"""

role_lines = []
if components.get("ufw"):
    role_lines.append("   - ufw                     # Firewall — allow/deny rules per port")
if components.get("luks"):
    role_lines.append("   - role: luks              # At-rest disk encryption (LUKS)")
    role_lines.append("     when: supabase_encryption.enabled")
if components.get("caddy"):
    role_lines.append("   - caddy                   # Reverse proxy + automatic TLS + SSO")
if components.get("monitor"):
    role_lines.append("   - monitor                 # Grafana + Prometheus + Loki stack")
if components.get("fail2ban"):
    role_lines.append("   - fail2ban                # Brute-force protection for Postgres")
if components.get("backup"):
    role_lines.append("   - backup                  # Automated S3-compatible backups")

content = header
if role_lines:
    content += "\n".join(role_lines) + "\n"
else:
    content += "   # (no advanced components enabled in config.yml)\n"

with open(path, 'w') as f:
    f.write(content)
PYEOF

ok "playbook-supabase.yml updated."

# ─── Deploy ───────────────────────────────────────────────────────────────────
log "Starting deployment via install.sh…"
cd "$SCRIPT_DIR"
bash install.sh
ok "Deployment complete."

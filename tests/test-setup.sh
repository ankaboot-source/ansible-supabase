#!/bin/bash
# test-setup.sh — Tests for the deterministic installer (setup.sh)
# Run: bash tests/test-setup.sh
# Shell-level tests that validate setup.sh behavior without running Ansible
# (the deploy step is stubbed out).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="$SCRIPT_DIR/.."
SETUP="$WORKTREE/setup.sh"
EXAMPLE="$WORKTREE/config.example.yml"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0

ok()   { printf "  \033[0;32mPASS\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[0;31mFAIL\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }

make_sandbox() {
  local d="$TMPDIR_BASE/$1"
  mkdir -p "$d/env"
  cp "$WORKTREE/setup.sh" "$WORKTREE/config.example.yml" "$WORKTREE/install.sh" \
     "$WORKTREE/generate-keys.sh" "$WORKTREE/playbook-supabase.yml" "$d/" 2>/dev/null
  cp "$WORKTREE/env/supabase.yml" "$d/env/"
  cat > "$d/install.sh" <<'STUB'
#!/bin/bash
echo "STUBBED_INSTALL_OK"
STUB
  chmod +x "$d/install.sh" "$d/setup.sh"
  echo "$d"
}

# Run setup in sandbox; sets OUT and RC variables in caller scope.
run_setup_rc() {
  local dir="$1"; shift
  OUT="$( cd "$dir" && bash setup.sh "$@" 2>&1 )" && RC=0 || RC=$?
}

# Fill all required fields in a config.yml with valid test values.
fill_required() {
  local c="$1/config.yml"
  sed -i 's|deploy_user: changeit|deploy_user: ubuntu|' "$c"
  sed -i 's|site_url: https://app.example.com|site_url: https://myapp.com|' "$c"
  sed -i 's|api_external_url: https://sb.example.com|api_external_url: https://sb.myapp.com|' "$c"
  sed -i 's|supabase_domain: sb.example.com|supabase_domain: sb.myapp.com|' "$c"
  sed -i 's|smtp_admin_email: changeit|smtp_admin_email: me@myapp.com|' "$c"
  sed -i 's|smtp_host: changeit|smtp_host: mail.myapp.com|' "$c"
  sed -i 's|smtp_user: changeit|smtp_user: me@myapp.com|' "$c"
  sed -i 's|smtp_password: changeit|smtp_password: secret123|' "$c"
}

# ─── TC-SETUP-001: Missing config.yml ────────────────────────────────────────
echo "TC-SETUP-001: missing config.yml"
d="$(make_sandbox tc001)"
rm -f "$d/config.yml"
run_setup_rc "$d" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "config.yml not found"; then
  ok "exits non-zero with clear message"
else
  fail "expected non-zero exit + 'config.yml not found' (got rc=$RC)"
fi

# ─── TC-SETUP-002: Required fields left as changeit ──────────────────────────
echo "TC-SETUP-002: required fields left as changeit"
d="$(make_sandbox tc002)"
cp "$d/config.example.yml" "$d/config.yml"
run_setup_rc "$d" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "REQUIRED fields"; then
  ok "exits non-zero listing required fields"
else
  fail "expected non-zero exit listing required fields (got rc=$RC)"
fi

# ─── TC-SETUP-011: config.example.yml is valid YAML ──────────────────────────
echo "TC-SETUP-011: config.example.yml is valid YAML"
if python3 -c "import yaml; d=yaml.safe_load(open('$EXAMPLE')); \
  assert set(['required','secrets','components','advanced']).issubset(d.keys())" 2>/dev/null; then
  ok "valid YAML with expected top-level keys"
else
  fail "config.example.yml is not valid YAML or missing top-level keys"
fi

# ─── TC-SETUP-009: Help output ────────────────────────────────────────────────
echo "TC-SETUP-009: help output"
d="$(make_sandbox tc009)"
run_setup_rc "$d" --help
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -qi "Usage"; then
  ok "prints usage and exits 0"
else
  fail "expected exit 0 with Usage (got rc=$RC)"
fi

# ─── TC-SETUP-008: Dry-run does not modify files ──────────────────────────────
echo "TC-SETUP-008: dry-run does not modify files"
d="$(make_sandbox tc008)"
cp "$d/config.example.yml" "$d/config.yml"
fill_required "$d"
env_before="$(sha256sum "$d/env/supabase.yml" | cut -d' ' -f1)"
pb_before="$(sha256sum "$d/playbook-supabase.yml" | cut -d' ' -f1)"
run_setup_rc "$d" --dry-run --yes
env_after="$(sha256sum "$d/env/supabase.yml" | cut -d' ' -f1)"
pb_after="$(sha256sum "$d/playbook-supabase.yml" | cut -d' ' -f1)"
if [[ $RC -eq 0 && "$env_before" == "$env_after" && "$pb_before" == "$pb_after" ]]; then
  ok "dry-run leaves files unchanged"
else
  fail "dry-run modified files (rc=$RC, env_changed=$([[ $env_before == $env_after ]] && echo no || echo yes))"
fi

# ─── TC-SETUP-003: Auto-generate secrets ──────────────────────────────────────
echo "TC-SETUP-003: auto-generate secrets"
d="$(make_sandbox tc003)"
cp "$d/config.example.yml" "$d/config.yml"
fill_required "$d"
run_setup_rc "$d" --yes
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -q "STUBBED_INSTALL_OK"; then
  if grep -q "^postgres_db_pwd: changeit" "$d/env/supabase.yml"; then
    fail "postgres_db_pwd still changeit after generation"
  elif grep -q "^sb_jwt_secret: changeit" "$d/env/supabase.yml"; then
    fail "sb_jwt_secret still changeit after generation"
  else
    ok "secrets auto-generated and written"
  fi
else
  fail "setup.sh failed during secret generation (rc=$RC)"
  echo "$OUT" | tail -20
fi

# ─── TC-SETUP-007: Required fields written to env/supabase.yml ────────────────
echo "TC-SETUP-007: required fields written to env/supabase.yml"
if [[ -n "${d:-}" ]] && grep -q "^deploy_user: ubuntu" "$d/env/supabase.yml" \
  && grep -q "^site_url: https://myapp.com" "$d/env/supabase.yml" \
  && grep -q "^api_external_url: https://sb.myapp.com" "$d/env/supabase.yml" \
  && grep -q "^smtp_host: mail.myapp.com" "$d/env/supabase.yml"; then
  ok "required fields present in env/supabase.yml"
else
  fail "required fields not found in env/supabase.yml"
fi

# ─── TC-SETUP-005: Enable a component (caddy) ─────────────────────────────────
echo "TC-SETUP-005: enable caddy component"
d="$(make_sandbox tc005)"
cp "$d/config.example.yml" "$d/config.yml"
fill_required "$d"
sed -i 's|caddy: false|caddy: true|' "$d/config.yml"
sed -i 's|sso_client_id: changeit|sso_client_id: myid|' "$d/config.yml"
sed -i 's|sso_client_secret: changeit|sso_client_secret: mysecret|' "$d/config.yml"
run_setup_rc "$d" --yes
if [[ $RC -eq 0 ]]; then
  if grep -Eq '^[[:space:]]*-[[:space:]]+caddy\b' "$d/playbook-supabase.yml" \
    && ! grep -Eq '^[[:space:]]*#[[:space:]]*-[[:space:]]*caddy\b' "$d/playbook-supabase.yml"; then
    ok "caddy role uncommented in playbook"
  else
    fail "caddy role not enabled in playbook"
    grep -n caddy "$d/playbook-supabase.yml"
  fi
else
  fail "setup.sh failed with caddy enabled (rc=$RC)"
  echo "$OUT" | tail -20
fi

# ─── TC-SETUP-006: Components disabled by default ─────────────────────────────
echo "TC-SETUP-006: components disabled by default"
d="$(make_sandbox tc006)"
cp "$d/config.example.yml" "$d/config.yml"
fill_required "$d"
run_setup_rc "$d" --yes
if [[ $RC -eq 0 ]]; then
  # No advanced role should be enabled (uncommented) by default.
  if grep -Eq '^[[:space:]]*-[[:space:]]+(caddy|monitor|fail2ban|backup|ufw|role:[[:space:]]*luks)\b' "$d/playbook-supabase.yml"; then
    fail "some advanced roles were enabled unexpectedly"
    cat "$d/playbook-supabase.yml"
  else
    ok "no advanced roles enabled by default"
  fi
else
  fail "setup.sh failed with default config (rc=$RC)"
  echo "$OUT" | tail -20
fi

# ─── TC-SETUP-012: Non-interactive execution ──────────────────────────────────
echo "TC-SETUP-012: non-interactive (--yes) execution"
d="$(make_sandbox tc012)"
cp "$d/config.example.yml" "$d/config.yml"
fill_required "$d"
OUT="$( cd "$d" && bash setup.sh --yes </dev/null 2>&1 )" && RC=0 || RC=$?
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -q "STUBBED_INSTALL_OK"; then
  ok "completes non-interactively with --yes"
else
  fail "blocked or failed with --yes (rc=$RC)"
  echo "$OUT" | tail -20
fi

# ─── TC-SETUP-013: Idempotent re-run ───────────────────────────────────────────
echo "TC-SETUP-013: idempotent re-run"
d="$(make_sandbox tc013)"
cp "$d/config.example.yml" "$d/config.yml"
fill_required "$d"
run_setup_rc "$d" --yes
RC1=$RC
run_setup_rc "$d" --yes
if [[ $RC1 -eq 0 && $RC -eq 0 ]] && echo "$OUT" | grep -q "STUBBED_INSTALL_OK"; then
  ok "second run completes successfully"
else
  fail "second run failed (rc1=$RC1 rc2=$RC)"
  echo "$OUT" | tail -20
fi

# ─── TC-SETUP-014: env/supabase.yml remains valid YAML after render ───────────
echo "TC-SETUP-014: env/supabase.yml is valid YAML after setup"
d="$(make_sandbox tc014)"
cp "$d/config.example.yml" "$d/config.yml"
fill_required "$d"
run_setup_rc "$d" --yes
if [[ $RC -eq 0 ]] && python3 -c "import yaml,sys; d=yaml.safe_load(open('$d/env/supabase.yml')); \
   assert isinstance(d.get('docker_users'), list), 'docker_users must be a list'; \
   assert d.get('deploy_user') == 'ubuntu', 'deploy_user mismatch'" 2>/dev/null; then
  ok "env/supabase.yml is valid YAML with correct types"
else
  fail "env/supabase.yml is invalid YAML or has wrong types (rc=$RC)"
  python3 -c "import yaml; yaml.safe_load(open('$d/env/supabase.yml'))" 2>&1 | tail -5
fi

# ─── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
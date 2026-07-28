#!/bin/bash
# test-migrate.sh — Tests for the migration script (migrate.sh, Layer 1)
# Run: bash tests/test-migrate.sh
# Shell-level tests that validate migrate.sh behavior with stubbed binaries
# (pg_dump, pg_restore, rclone, psql) so they run without a real Supabase
# project or database. Stubs log their argv so tests can assert the
# read-only-source invariant.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="$SCRIPT_DIR/.."
MIGRATE="$WORKTREE/migrate.sh"
EXAMPLE="$WORKTREE/env/migrate.example.yml"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0

ok()   { printf "  \033[0;32mPASS\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[0;31mFAIL\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }

# ─── Sandbox builder ─────────────────────────────────────────────────────────
# Creates a sandbox dir with migrate.sh, env/migrate.example.yml, and a
# stub-bin directory populated with stubbed pg_dump/pg_restore/rclone/psql.
# Stubs log their argv to $SANDBOX/stub-bin/<name>.calls and behave per the
# env vars the test sets (e.g. STUB_PSQL_PUBLIC_TABLES=5).
make_sandbox() {
  local name="$1"
  local d="$TMPDIR_BASE/$name"
  mkdir -p "$d/env" "$d/stub-bin"
  cp "$MIGRATE" "$d/migrate.sh"
  cp "$EXAMPLE" "$d/env/migrate.example.yml"
  chmod +x "$d/migrate.sh"

  # Stub each binary. Each stub appends its argv (one line per arg, NUL-separated
  # for safety) to its .calls file, then behaves per env vars.
  for bin in pg_dump pg_restore rclone psql; do
    cat > "$d/stub-bin/$bin" <<STUB
#!/bin/bash
# stub for $bin — logs argv, behaves per env vars
{
  printf 'CALL %s\n' "$bin"
  for a in "\$@"; do printf '  ARG %s\n' "\$a"; done
} >> "$d/stub-bin/$bin.calls"
case "$bin" in
  psql)
    # psql is called with -c "SELECT count(*) ...". Inspect the query to decide.
    query="\$(printf '%s ' "\$@" | grep -oE 'SELECT count\(\*\) FROM [a-z._]+')"
    case "\$query" in
      *"information_schema.tables"*)
        echo "\${STUB_PSQL_PUBLIC_TABLES:-0}"
        ;;
      *"auth.users"*)
        echo "\${STUB_PSQL_AUTH_USERS:-0}"
        ;;
      *)
        echo "0"
        ;;
    esac
    ;;
  pg_dump)
    # pg_dump succeeds unless STUB_PGDUMP_FAIL_SCHEMA is set to a schema name
    # present in argv.
    for a in "\$@"; do
      case "\$a" in
        --schema=*)
          schema="\${a#--schema=}"
          if [[ "\${STUB_PGDUMP_FAIL_SCHEMA:-}" == "\$schema" ]]; then
            echo "STUB_PGDUMP_FAIL: \$schema" >&2
            exit 1
          fi
          ;;
      esac
    done
    exit 0
    ;;
  pg_restore)
    [[ "\${STUB_PGRESTORE_FAIL:-0}" == "1" ]] && exit 1
    exit 0
    ;;
  rclone)
    [[ "\${STUB_RCLONE_FAIL:-0}" == "1" ]] && exit 1
    exit 0
    ;;
esac
STUB
    chmod +x "$d/stub-bin/$bin"
  done

  echo "$d"
}

# Run migrate in sandbox; sets OUT and RC variables in caller scope.
run_migrate_rc() {
  local dir="$1"; shift
  # Put stub-bin first on PATH so the stubs shadow any real binaries.
  OUT="$( cd "$dir" && PATH="$dir/stub-bin:$PATH" bash migrate.sh "$@" 2>&1 )" && RC=0 || RC=$?
}

# Fill all required fields in a config.yml with valid test values.
fill_required() {
  local c="$1/env/migrate.yml"
  sed -i 's|project_ref: changeit|project_ref: testprojref12345|' "$c"
  sed -i 's|db_url: changeit.*# postgresql://postgres.\[ref\]:\[pwd\]@db.\[ref\].supabase.co:6543/postgres|db_url: postgresql://postgres.testprojref12345:pwd@db.testprojref12345.supabase.co:6543/postgres|' "$c"
  sed -i 's|storage_endpoint: changeit.*# https://\[ref\].supabase.co/storage/v1|storage_endpoint: https://testprojref12345.supabase.co/storage/v1|' "$c"
  sed -i 's|storage_access_key: changeit|storage_access_key: srcak12345|' "$c"
  sed -i 's|storage_secret_key: changeit|storage_secret_key: srcsk12345|' "$c"
  sed -i 's|storage_region: changeit.*# e.g. us-east-1|storage_region: us-east-1|' "$c"
  # target defaults are fine except the changeit access/secret keys
  sed -i 's|storage_access_key: changeit.*# from env/supabase.yml|storage_access_key: tgtak12345|' "$c"
  sed -i 's|storage_secret_key: changeit.*# from env/supabase.yml|storage_secret_key: tgtsk12345|' "$c"
}

# ─── TC-MIG-001: Missing config file ─────────────────────────────────────────
echo "TC-MIG-001: missing config file"
d="$(make_sandbox tc001)"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "Config file not found"; then
  ok "exits non-zero with clear message"
else
  fail "expected non-zero exit + 'Config file not found' (got rc=$RC)"
fi

# ─── TC-MIG-002: Required fields left as changeit ─────────────────────────────
echo "TC-MIG-002: required fields left as changeit"
d="$(make_sandbox tc002)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "changeit"; then
  ok "exits non-zero listing changeit fields"
else
  fail "expected non-zero exit listing changeit fields (got rc=$RC)"
fi

# ─── TC-MIG-003: Invalid source DSN scheme ────────────────────────────────────
echo "TC-MIG-003: invalid source DSN scheme"
d="$(make_sandbox tc003)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
sed -i 's|db_url: postgresql://postgres.testprojref12345:pwd@db.testprojref12345.supabase.co:6543/postgres|db_url: mysql://user@host/db|' "$d/env/migrate.yml"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "must start with postgresql://"; then
  ok "exits non-zero on invalid DSN scheme"
else
  fail "expected non-zero exit on invalid DSN scheme (got rc=$RC)"
fi

# ─── TC-MIG-004: Source DSN equals target DSN ─────────────────────────────────
echo "TC-MIG-004: source DSN equals target DSN"
d="$(make_sandbox tc004)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
# Make target equal source
sed -i 's|db_url: postgresql://postgres:postgres@localhost:5432/postgres|db_url: postgresql://postgres.testprojref12345:pwd@db.testprojref12345.supabase.co:6543/postgres|' "$d/env/migrate.yml"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "must not be the same database"; then
  ok "exits non-zero when source == target"
else
  fail "expected non-zero exit on source==target (got rc=$RC)"
fi

# ─── TC-MIG-005: Missing required binary ──────────────────────────────────────
echo "TC-MIG-005: missing required binary (rclone)"
d="$(make_sandbox tc005)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
# Remove the rclone stub so it's not on PATH
rm "$d/stub-bin/rclone"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "required binary not found: rclone"; then
  ok "exits non-zero on missing rclone"
else
  fail "expected non-zero exit on missing rclone (got rc=$RC)"
fi

# ─── TC-MIG-006: Non-empty target refusal (relations present) ─────────────────
echo "TC-MIG-006: non-empty target refusal (public tables)"
d="$(make_sandbox tc006)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
STUB_PSQL_PUBLIC_TABLES=5 run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "target is not empty"; then
  ok "exits non-zero on non-empty target (public tables)"
else
  fail "expected non-zero exit on non-empty target (got rc=$RC)"
fi

# ─── TC-MIG-007: Non-empty target refusal (auth.users present) ─────────────────
echo "TC-MIG-007: non-empty target refusal (auth.users)"
d="$(make_sandbox tc007)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
STUB_PSQL_AUTH_USERS=3 run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "target is not empty"; then
  ok "exits non-zero on non-empty target (auth.users)"
else
  fail "expected non-zero exit on non-empty target (auth.users) (got rc=$RC)"
fi

# ─── TC-MIG-008: Dry-run does not modify anything ─────────────────────────────
echo "TC-MIG-008: dry-run does not invoke any binary"
d="$(make_sandbox tc008)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --dry-run --yes
no_calls=true
for bin in pg_dump pg_restore rclone psql; do
  if [[ -f "$d/stub-bin/$bin.calls" ]]; then
    no_calls=false
    break
  fi
done
if [[ $RC -eq 0 ]] && $no_calls; then
  ok "dry-run exits 0 and invokes no stubbed binary"
else
  fail "dry-run invoked a binary or exited non-zero (rc=$RC)"
fi

# ─── TC-MIG-009: Help output ──────────────────────────────────────────────────
echo "TC-MIG-009: help output"
d="$(make_sandbox tc009)"
run_migrate_rc "$d" --help
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -qi "Usage"; then
  ok "prints usage and exits 0"
else
  fail "expected exit 0 with Usage (got rc=$RC)"
fi

# ─── TC-MIG-010: Non-interactive execution (no TTY) ───────────────────────────
echo "TC-MIG-010: non-interactive (--yes) execution with no TTY"
d="$(make_sandbox tc010)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
OUT="$( cd "$d" && PATH="$d/stub-bin:$PATH" bash migrate.sh --config "$d/env/migrate.yml" --yes </dev/null 2>&1 )" && RC=0 || RC=$?
if [[ $RC -eq 0 ]]; then
  ok "completes non-interactively with --yes and no TTY"
else
  fail "blocked or failed with --yes (rc=$RC)"
  echo "$OUT" | tail -20
fi

# ─── TC-MIG-011: Full happy path with stubs ───────────────────────────────────
echo "TC-MIG-011: full happy path with stubs"
d="$(make_sandbox tc011)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -eq 0 ]] \
  && [[ -f "$d/stub-bin/pg_dump.calls" ]] \
  && [[ -f "$d/stub-bin/pg_restore.calls" ]] \
  && [[ -f "$d/stub-bin/rclone.calls" ]]; then
  ok "happy path invokes pg_dump, pg_restore, rclone"
else
  fail "happy path did not invoke all expected binaries (rc=$RC)"
  echo "$OUT" | tail -20
fi

# ─── TC-MIG-012: Manual-steps report is always printed ────────────────────────
echo "TC-MIG-012: manual-steps report is always printed"
# Reuse tc011 output
if echo "$OUT" | grep -q "MANUAL STEPS" \
  && echo "$OUT" | grep -q "AUTH CONFIGURATION" \
  && echo "$OUT" | grep -q "EDGE FUNCTIONS" \
  && echo "$OUT" | grep -q "CRON JOBS" \
  && echo "$OUT" | grep -q "WEBHOOKS" \
  && echo "$OUT" | grep -q "STORAGE BUCKET CONFIGURATION" \
  && echo "$OUT" | grep -q "CLIENT ENV VARS" \
  && echo "$OUT" | grep -q "USERS MUST LOG IN AGAIN"; then
  ok "manual-steps report contains all 7 sections"
else
  fail "manual-steps report missing sections"
fi

# ─── TC-MIG-013: Read-only-source invariant ───────────────────────────────────
echo "TC-MIG-013: read-only-source invariant (no write command against source)"
d="$(make_sandbox tc013)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
# Assert: pg_dump is the only binary pointed at the source DSN
src_dsn="db.testprojref12345.supabase.co"
violations=0
# pg_restore must never reference the source DSN
if [[ -f "$d/stub-bin/pg_restore.calls" ]] && grep -q "$src_dsn" "$d/stub-bin/pg_restore.calls"; then
  violations=$((violations+1))
fi
# rclone must use copy, not sync/move/delete
if [[ -f "$d/stub-bin/rclone.calls" ]]; then
  if ! grep -q "ARG copy" "$d/stub-bin/rclone.calls" \
     || grep -qE "ARG (sync|move|delete|purge|rmdir)" "$d/stub-bin/rclone.calls"; then
    violations=$((violations+1))
  fi
else
  violations=$((violations+1))  # rclone wasn't called at all
fi
# psql against source: only SELECT count(*) (preflight). But psql is only
# called against the target in our implementation, so source DSN should never
# appear in psql.calls.
if [[ -f "$d/stub-bin/psql.calls" ]] && grep -q "$src_dsn" "$d/stub-bin/psql.calls"; then
  violations=$((violations+1))
fi
if [[ $violations -eq 0 ]]; then
  ok "no write command issued against source DSN"
else
  fail "read-only-source invariant violated ($violations violation(s))"
fi

# ─── TC-MIG-014: Storage failure is non-fatal + appears in runtime notes ──────
echo "TC-MIG-014: storage failure is non-fatal + in runtime notes"
d="$(make_sandbox tc014)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
STUB_RCLONE_FAIL=1 run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -qi "storage copy failed"; then
  ok "storage failure is non-fatal and reported"
else
  fail "storage failure should be non-fatal (got rc=$RC)"
fi

# ─── TC-MIG-015: Missing optional schema is skipped with warning ───────────────
echo "TC-MIG-015: missing optional schema skipped with warning"
d="$(make_sandbox tc015)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
STUB_PGDUMP_FAIL_SCHEMA=pgsodium run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -qi "skipping schema 'pgsodium'"; then
  ok "missing schema skipped with warning, not fatal"
else
  fail "missing schema should be skipped, not fatal (got rc=$RC)"
  echo "$OUT" | tail -20
fi

# ─── TC-MIG-016: env/migrate.example.yml is valid YAML ────────────────────────
echo "TC-MIG-016: env/migrate.example.yml is valid YAML"
if python3 -c "import yaml; d=yaml.safe_load(open('$EXAMPLE')); \
  assert set(['source','target','tools']).issubset(d.keys())" 2>/dev/null; then
  ok "valid YAML with expected top-level keys"
else
  fail "env/migrate.example.yml is not valid YAML or missing top-level keys"
fi

# ─── TC-MIG-017: Unknown flag rejected ────────────────────────────────────────
echo "TC-MIG-017: unknown flag rejected"
d="$(make_sandbox tc017)"
run_migrate_rc "$d" --bogus
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi "Unknown option"; then
  ok "exits non-zero on unknown flag"
else
  fail "expected non-zero exit on unknown flag (got rc=$RC)"
fi

# ─── TC-MIG-018: --config is required ──────────────────────────────────────────
echo "TC-MIG-018: --config is required"
d="$(make_sandbox tc018)"
run_migrate_rc "$d" --yes
if [[ $RC -ne 0 ]] && echo "$OUT" | grep -qi -- "--config is required"; then
  ok "exits non-zero when --config missing"
else
  fail "expected non-zero exit when --config missing (got rc=$RC)"
fi

# ─── TC-MIG-019: pg_dump uses read-only-compatible flags ──────────────────────
echo "TC-MIG-019: pg_dump uses read-only-compatible flags"
d="$(make_sandbox tc019)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
if [[ -f "$d/stub-bin/pg_dump.calls" ]] \
  && grep -q "ARG --no-owner" "$d/stub-bin/pg_dump.calls" \
  && grep -q "ARG --no-privileges" "$d/stub-bin/pg_dump.calls"; then
  ok "pg_dump invoked with --no-owner --no-privileges"
else
  fail "pg_dump missing --no-owner/--no-privileges flags"
fi

# ─── TC-MIG-020: pg_restore targets the target DSN only ───────────────────────
echo "TC-MIG-020: pg_restore targets the target DSN only (via --dbname=)"
d="$(make_sandbox tc020)"
cp "$d/env/migrate.example.yml" "$d/env/migrate.yml"
fill_required "$d"
run_migrate_rc "$d" --config "$d/env/migrate.yml" --yes
tgt_dsn="localhost:5432"
src_dsn="db.testprojref12345.supabase.co"
# Strengthened per review (H1): assert the DSN is passed via --dbname= (the
# correct pg_restore connection option), NOT as a bare positional filename.
# pg_restore's positional arg is the archive FILE; the DSN must go via --dbname=.
if [[ -f "$d/stub-bin/pg_restore.calls" ]] \
  && grep -q "ARG --dbname=postgresql://postgres:postgres@${tgt_dsn}/postgres" "$d/stub-bin/pg_restore.calls" \
  && ! grep -q "$src_dsn" "$d/stub-bin/pg_restore.calls"; then
  ok "pg_restore targets target DSN via --dbname=, never source"
else
  fail "pg_restore DSN not passed via --dbname= or targets source"
fi

# ─── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
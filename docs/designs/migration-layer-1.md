# Design Canvas: Migration Script (Layer 1) — `migrate.sh`

**Issue:** #99 — Migration script from supabase.com
**Labels:** feature, migration, layer-1
**Status:** Approved (autonomous mode — no interactive approval gate)

---

## 1. Goal

A single command that takes a Supabase Cloud project and migrates it end-to-end
into a freshly installed self-hosted instance (this repo's own stack), accepting
downtime and a short list of manual steps printed at the end.

```bash
./migrate.sh --config env/migrate.yml --yes
```

This is the **walking skeleton**: the entire functional perimeter touched, none
of it deeply. Incomplete, but never silently incomplete.

---

## 2. Non-Goals (Deliberately excluded — each has its own layer)

- Verification / dry-run
- Session continuity / resumability
- Auth config import (manual checklist only at this layer)
- Downtime reduction
- Edge Functions migration (listed as manual steps)
- Cron jobs / webhooks migration (listed as manual steps)
- Storage bucket config reconciliation (objects only, no bucket config)

---

## 3. Fidelity Contract (what "done" means at this layer)

| Surface | After this issue |
|---|---|
| Schema + data | Dumped and restored, including Supabase-managed schemas |
| Roles | `anon`, `authenticated`, `service_role` recreated; custom roles best-effort |
| Auth users | Migrated with UUIDs preserved — users must log in again |
| Auth configuration | Manual, printed as a checklist |
| Storage objects | Copied — no reconciliation, no bucket config |
| Edge Functions | Not migrated — listed as manual steps |
| Cron jobs, webhooks | Not migrated — listed as manual steps |
| Downtime | A maintenance window, accepted and documented |
| Restartability | None. A failure means starting over |

---

## 4. Conventions (must match `setup.sh`)

- **YAML config file**, non-interactive by default.
- **Flags are verbs only**: `--config <path>`, `--yes`, `--dry-run`, `--help`, `-v/--verbose`.
  No `--config=foo` form (matches `setup.sh`'s `case` parser).
- **Read-only against the source project. Always, at every layer.** This is a hard
  invariant — enforced by (a) using only read-only `pg_dump`/`pg_restore` flags and
  read-only S3 `GET`/`LIST` via rclone, and (b) a preflight assertion that the source
  DSN is not the target DSN.
- **Refuses to run against a non-empty target.** A preflight check counts relations
  in `public` and rows in `auth.users`; if either is non-zero, abort before touching
  anything.
- **Runs with no TTY attached.** All prompts gated behind `--yes`; colors disabled
  when `[[ -t 1 ]]` is false (same idiom as `setup.sh`).
- **Logging helpers** (`log`/`ok`/`warn`/`die`) copied verbatim from `setup.sh` so the
  two scripts feel like one tool.
- **YAML parsing** via the same `python3 -c 'import yaml'` helper pattern (`cfg_get`/
  `cfg_bool`), so no new runtime dependency is introduced.

---

## 5. Inputs (`env/migrate.example.yml`)

A new example config, separate from `config.example.yml` (migration is an
opt-in operation, not part of install). Copied to `env/migrate.yml` by the
operator and edited.

```yaml
# Migration configuration — copy to env/migrate.yml and edit.
# READ-ONLY against source. The script refuses to write to the source project.

source:
  # Supabase Cloud project ref (found in Dashboard URL / Settings / API).
  project_ref: changeit            # e.g. abcdefghijklmnop

  # Direct Postgres connection string to the Cloud project's pooler.
  # Use the TRANSACTION/SESSION mode URL (port 6543 or 5432 per your pooler).
  # Must be a libpq DSN. The script opens it READ-ONLY.
  db_url: changeit                 # postgresql://postgres.[ref]:[pwd]@db.[ref].supabase.co:6543/postgres

  # S3-compatible storage endpoint credentials (Supabase Cloud S3 API).
  # Found in Dashboard / Settings / Storage.
  storage_endpoint: changeit       # https://[ref].supabase.co/storage/v1
  storage_access_key: changeit
  storage_secret_key: changeit
  storage_region: changeit         # e.g. us-east-1

target:
  # Self-hosted Postgres DSN (the stack this repo deploys).
  # Default matches the local docker-compose service name + default password.
  db_url: postgresql://postgres:postgres@localhost:5432/postgres

  # Self-hosted storage endpoint (Kong /storage/v1).
  storage_endpoint: http://localhost:8000/storage/v1
  storage_access_key: changeit     # from env/supabase.yml s3_protocol_access_key_id
  storage_secret_key: changeit     # from env/supabase.yml s3_protocol_access_key_secret
  storage_region: us-east-1

# Tools — paths to required binaries. Defaults resolve via PATH.
tools:
  pg_dump: pg_dump
  pg_restore: pg_restore
  rclone: rclone
  psql: psql
```

### Validation rules

- `source.project_ref` must not be `changeit`.
- `source.db_url` must not be `changeit` and must start with `postgresql://` (or
  `postgres://`).
- `target.db_url` must start with `postgresql://` and must **not equal**
  `source.db_url` (read-only-source invariant).
- `source.storage_*` and `target.storage_*` must not be `changeit`.
- Required binaries (`pg_dump`, `pg_restore`, `rclone`, `psql`) must be on PATH.

---

## 6. Execution Phases

```
Phase 0: Preflight
  ├─ parse args (--config, --yes, --dry-run, --help, -v)
  ├─ load + validate migrate.yml (cfg_get / cfg_bool helpers)
  ├─ assert required binaries on PATH
  ├─ assert source.db_url != target.db_url
  ├─ assert target is empty (count relations in public + rows in auth.users)
  └─ if --dry-run: print plan and exit 0

Phase 1: Database — schema + data
  ├─ pg_dump source (per-schema, custom format)
  │     flags: --format=custom --no-owner --no-privileges --schema=<name>
  │     + --schema=public --schema=auth --schema=storage --schema=_realtime
  │       --schema=graphql_public --schema=extensions --schema=pgsodium
  │       (best-effort: missing schemas are skipped with a warning, not fatal)
  ├─ pg_restore into target (DSN via --dbname=, archive file as positional)
  │     flags: --dbname=<target_dsn> --no-owner --no-privileges
  │            --clean --if-exists --exit-on-error
  └─ on failure: warn() + add to runtime notes (non-fatal per schema)

Phase 2: Auth users (UUIDs preserved)
  ├─ pg_dump auth.users auth.identities from source (data-only, INSERT copy)
  ├─ pg_restore into target (DSN via --dbname=, archive file as positional)
  └─ NOTE: users must log in again (password hashes migrate, but sessions do not)

Phase 3: Storage objects (rclone copy)
  ├─ configure rclone remote for source S3 endpoint (read-only)
  ├─ configure rclone remote for target S3 endpoint
  ├─ rclone copy source:bucket target:bucket --progress=no
  └─ on failure: warn (storage is best-effort at this layer) + add to manual report

Phase 4: Manual-steps report
  ├─ print a fixed checklist of everything NOT migrated
  └─ exit 0
```

### Read-only-source enforcement

- `pg_dump` is inherently read-only (no `--write` flag exists).
- `rclone copy` (not `sync`, not `move`) — source is never mutated.
- A preflight assertion `source.db_url != target.db_url` prevents the catastrophic
  case of pointing both ends at the same database.
- The script never issues `psql` against the source at all — the only `psql`
  calls are read-only `SELECT count(*)` preflight probes against the **target**
  (to verify it is empty). The source is touched only by `pg_dump` (read-only).

### Non-empty-target refusal

Before any restore, the script runs (against the **target** only):

```sql
SELECT count(*) FROM information_schema.tables
 WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
SELECT count(*) FROM auth.users;
```

If either is non-zero, `die` with a clear message: "target is not empty — Layer 1
migrates into a fresh instance only. Re-provision the target and re-run."

---

## 7. Manual-Steps Report (the contract of this layer)

Printed to stdout at the end, always. The report is the **authoritative list of
what the operator must now do by hand**. It is generated from a fixed template
plus runtime-discovered items (e.g. storage copy failures, missing schemas).

Template (printed verbatim, with runtime substitutions):

```
================================================================================
 MANUAL STEPS — complete these by hand. Migration is NOT finished until you do.
================================================================================

1. AUTH CONFIGURATION (not migrated)
   - [ ] Review and re-create auth providers in the self-hosted Studio:
         Dashboard → Authentication → Providers
   - [ ] Re-create any custom email templates (Dashboard → Auth → Email Templates)
   - [ ] Re-configure SMTP settings (already in env/supabase.yml — verify)
   - [ ] Re-create any MFA / SAML / hooks configuration

2. EDGE FUNCTIONS (not migrated)
   - [ ] List your functions: supabase functions list --project-ref <ref>
   - [ ] Deploy each: supabase functions deploy <name> --project-ref <self-hosted-ref>
         (or copy the source and deploy via the self-hosted CLI)

3. CRON JOBS (not migrated)
   - [ ] Re-create pg_cron jobs: SELECT cron.schedule(...) for each job
   - [ ] Source list: SELECT * FROM cron.job;

4. WEBHOOKS (not migrated)
   - [ ] Re-create any database webhooks (Dashboard → Database → Webhooks)

5. STORAGE BUCKET CONFIGURATION (not migrated — objects only)
   - [ ] Re-create bucket definitions (public/private, file size limits, MIME types)
   - [ ] Re-create any per-bucket RLS policies

6. CLIENT ENV VARS (operator action)
   - [ ] Update your application's NEXT_PUBLIC_SUPABASE_URL / VITE_SUPABASE_URL
         to point at the self-hosted API URL
   - [ ] Update NEXT_PUBLIC_SUPABASE_ANON_KEY / VITE_SUPABASE_ANON_KEY
         to the self-hosted anon key (from env/supabase.yml)

7. USERS MUST LOG IN AGAIN
   - [ ] Notify users that sessions are invalidated; password hashes migrated,
         so existing passwords still work.

RUNTIME NOTES (discovered during this run):
- <list of skipped schemas, storage failures, etc. — empty if none>
================================================================================
```

---

## 8. Error Handling

- `set -euo pipefail` (same as `setup.sh`).
- Every phase wrapped in a function; failures call `die` with the phase name +
  tail of the captured log.
- No retry, no resume (explicitly out of scope). A failure means starting over.
- `--dry-run` prints the plan (phases + commands that would run) and exits 0
  before touching anything.

---

## 9. Testing Strategy

Shell-level tests in `tests/test-migrate.sh`, mirroring `tests/test-setup.sh`'s
shape (sandbox + stubbed binaries). The test harness stubs `pg_dump`, `pg_restore`,
`rclone`, and `psql` so tests run without a real Supabase project or database.

Test categories:
- Config validation (missing file, `changeit` fields, invalid DSN, source==target)
- Preflight (missing binaries, non-empty target refusal)
- Dry-run (no side effects, prints plan)
- Non-interactive (`--yes` with no TTY)
- Help output
- Phase execution with stubs (asserts the right commands are invoked)
- Manual-steps report is always printed
- Read-only-source invariant (no write command ever issued against source DSN)

---

## 10. File Manifest

| Path | Purpose |
|---|---|
| `migrate.sh` | The migration script (root, sibling to `setup.sh`) |
| `env/migrate.example.yml` | Example config (operator copies to `env/migrate.yml`) |
| `docs/designs/migration-layer-1.md` | This design canvas |
| `docs/test-cases/migration-layer-1.md` | Test case document |
| `tests/test-migrate.sh` | Shell-level test harness |
| `README.md` | Add a "Migration from Supabase Cloud" section |

---

## 11. Acceptance Criteria Mapping

| Issue criterion | How this design satisfies it |
|---|---|
| Test project migrates in one command | `./migrate.sh --config env/migrate.yml --yes` |
| Application reconnects after env var update | Manual-steps report item 6 + auth users migrated with UUIDs intact |
| Every unmigrated item in manual-steps report | Section 7 template — fixed + runtime items |
| Source provably never written to | `pg_dump` (read-only) + `rclone copy` (not sync/move) + preflight `source != target` assertion + no write `psql` against source |
| Runs with no TTY | `--yes` gates all prompts; colors off when `! [[ -t 1 ]]` |
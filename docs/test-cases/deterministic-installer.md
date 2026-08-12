# Test Cases: Deterministic Automatic Installer

Feature: Configuration-based deterministic installer (`setup.sh` + `config.example.yml`)
Issue: #87

## Scope

The installer must be usable by both AI agents and humans. The only file a user
must touch is `config.yml` (copied from `config.example.yml`). Required fields
are crystal clear and separated from advanced options.

## Test Scenarios

### TC-SETUP-001: Missing config.yml
- **Given**: no `config.yml` in the project root
- **When**: `bash setup.sh` is run
- **Then**: exits non-zero with a clear error pointing to `config.example.yml`

### TC-SETUP-002: Required fields left as "changeit"
- **Given**: `config.yml` with one or more `required.*` fields still set to `changeit`
- **When**: `bash setup.sh` is run
- **Then**: exits non-zero, listing every field that must be modified

### TC-SETUP-003: Auto-generate secrets (default)
- **Given**: `config.yml` with `secrets.generate: true`
- **When**: `bash setup.sh` is run
- **Then**: `env/supabase.yml` is populated with freshly generated crypto values
  (postgres_db_pwd, sb_jwt_secret, sb_anon_key, sb_service_role_key, etc.) and
  none remain `changeit`

### TC-SETUP-004: User-provided secrets
- **Given**: `config.yml` with `secrets.generate: false` and explicit secret values
- **When**: `bash setup.sh` is run
- **Then**: `env/supabase.yml` uses the provided values verbatim

### TC-SETUP-005: Enable a component (caddy)
- **Given**: `config.yml` with `components.caddy: true`
- **When**: `bash setup.sh` is run
- **Then**: `playbook-supabase.yml` has the `caddy` role uncommented

### TC-SETUP-006: Components disabled by default
- **Given**: `config.yml` with all components `false`
- **When**: `bash setup.sh` is run
- **Then**: `playbook-supabase.yml` keeps all advanced roles commented out

### TC-SETUP-007: Required fields written to env/supabase.yml
- **Given**: `config.yml` with valid required fields
- **When**: `bash setup.sh` is run
- **Then**: `env/supabase.yml` contains the provided deploy_user, site_url,
  api_external_url, smtp_* values and the supabase dashboard domain

### TC-SETUP-008: Dry-run mode
- **Given**: `config.yml` is valid
- **When**: `bash setup.sh --dry-run` is run
- **Then**: no files are modified; the script prints the actions it would take

### TC-SETUP-009: Help output
- **When**: `bash setup.sh --help` is run
- **Then**: prints usage with all supported flags and exits 0

### TC-SETUP-010: Warn on enabled component with placeholder advanced config
- **Given**: `config.yml` with `components.backup: true` but `advanced.backup.s3_bucket_name: changeit`
- **When**: `bash setup.sh` is run
- **Then**: prints a warning that backup component has unconfigured advanced fields

### TC-SETUP-011: config.example.yml is valid YAML
- **When**: `config.example.yml` is parsed
- **Then**: it is valid YAML with `required`, `secrets`, `components`, `advanced` top-level keys

### TC-SETUP-012: Non-interactive (AI-friendly) execution
- **Given**: a valid `config.yml`
- **When**: `bash setup.sh --yes` is run (no prompts)
- **Then**: completes without blocking on stdin

### TC-SETUP-013: Idempotent re-run
- **Given**: `setup.sh` already ran successfully
- **When**: `bash setup.sh` is run again with the same config
- **Then**: completes successfully without duplicating entries or corrupting files

### TC-SETUP-016: log drain enabled by default
- **Given**: a valid `config.yml` (no `required.enable_logging` override)
- **When**: `bash setup.sh` is run
- **Then**: `env/supabase.yml` renders `log_drain_enabled: true`

### TC-SETUP-017: enable_logging: false disables the log drain
- **Given**: a valid `config.yml` with `required.enable_logging: false`
- **When**: `bash setup.sh` is run
- **Then**: `env/supabase.yml` renders `log_drain_enabled: false`, so
  `start-supabase.sh` boots only `docker-compose-supabase.yml` (no log drain)
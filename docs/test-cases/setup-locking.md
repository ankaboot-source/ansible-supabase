# Test Cases: Setup Locking System (Issue #127)

## Goal

Prevent `setup.sh` from regenerating secrets (or clobbering an already-rendered
`env/supabase.yml` with the vanilla template) on a second run, unless the user
explicitly forces regeneration with `--force`.

## Background

Two failure modes the locking system must prevent:

1. **Secret overwrite on second run** — `secrets.generate: true` on a second
   `setup.sh` run generates fresh keys and overwrites the ones already in
   `env/supabase.yml`. Supabase services already configured with the old keys
   crash (JWT verification fails, DB password mismatch, etc.).
2. **Vanilla template clobber when generation disabled** — setting
   `secrets.generate: false` (without providing values) makes `setup.sh` write
   `changeit` placeholders back into `env/supabase.yml`, destroying the
   previously-generated secrets.

## Locking Mechanism

A lock file `env/.setup.lock` is written after the first successful render of
`env/supabase.yml`. On subsequent runs, if the lock file exists and `--force`
was NOT passed:

- The secrets block is skipped entirely (no `set_env_var` calls for any
  `secrets.*` field), preserving whatever is already in `env/supabase.yml`.
- A clear `[lock]` log line tells the user the env is locked and how to
  override (`--force`).

`--force` regenerates everything as if it were the first run (and rewrites the
lock file). `--dry-run` never writes or touches the lock file.

## Test Cases

### TC-LOCK-001: First run writes lock file
**Preconditions:** Fresh sandbox, no `env/.setup.lock`, valid `config.yml`,
`secrets.generate: true`.
**Steps:** Run `setup.sh --yes`.
**Expected:** Exit 0; `env/.setup.lock` exists; secrets in `env/supabase.yml`
are non-`changeit`.

### TC-LOCK-002: Second run preserves secrets (no --force)
**Preconditions:** TC-LOCK-001 state (lock file exists, secrets generated).
**Steps:** Run `setup.sh --yes` again.
**Expected:** Exit 0; secrets in `env/supabase.yml` are byte-identical to the
values after the first run; output contains a `[lock]` notice.

### TC-LOCK-003: --force regenerates secrets
**Preconditions:** TC-LOCK-001 state.
**Steps:** Run `setup.sh --yes --force`.
**Expected:** Exit 0; at least one secret in `env/supabase.yml` differs from
the pre-run value (regenerated); lock file rewritten.

### TC-LOCK-004: Disabling generation does NOT clobber existing secrets
**Preconditions:** TC-LOCK-001 state; then set `secrets.generate: false` in
`config.yml` (leave `secrets.*` values as `changeit`).
**Steps:** Run `setup.sh --yes`.
**Expected:** Exit 0; secrets in `env/supabase.yml` are unchanged (still the
generated values from the first run, NOT `changeit`); output contains `[lock]`
notice.

### TC-LOCK-005: --dry-run never writes a lock file
**Preconditions:** Fresh sandbox, no lock file, valid `config.yml`.
**Steps:** Run `setup.sh --dry-run --yes`.
**Expected:** Exit 0; `env/.setup.lock` does NOT exist.

### TC-LOCK-006: --force on first run behaves like normal first run
**Preconditions:** Fresh sandbox, no lock file.
**Steps:** Run `setup.sh --yes --force`.
**Expected:** Exit 0; lock file created; secrets generated.

### TC-LOCK-007: Lock file is valid JSON with expected fields
**Preconditions:** TC-LOCK-001 state.
**Expected:** `env/.setup.lock` parses as JSON and contains at minimum a
`rendered_at` timestamp and the `config_file` path.

### TC-LOCK-008: generate-keys.sh refuses without --force when lock exists
**Preconditions:** TC-LOCK-001 state (lock file exists).
**Steps:** Run `generate-keys.sh` (no args).
**Expected:** Non-zero exit; prints a message instructing to use `--force`;
`env/supabase.yml` secrets unchanged.

### TC-LOCK-009: generate-keys.sh --force regenerates when lock exists
**Preconditions:** TC-LOCK-001 state.
**Steps:** Run `generate-keys.sh --force`.
**Expected:** Exit 0; secrets regenerated (differ from pre-run values).

### TC-LOCK-010: generate-keys.sh runs freely when no lock exists
**Preconditions:** Fresh sandbox, no lock file.
**Steps:** Run `generate-keys.sh`.
**Expected:** Exit 0; secrets generated.
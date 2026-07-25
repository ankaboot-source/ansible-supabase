# Determinist Automatic Installation

> **Issue:** [ankaboot-source/ansible-supabase#87](https://github.com/ankaboot-source/ansible-supabase/issues/87) — *Determinist Automatic Installation*
> **Status:** Draft / Planning
> **Date:** 2026-07-25
> **License:** MIT (inherits repo license)

---

## 1. Problem

The current installation flow is simple but **not deterministic** and **not friendly to first-time users**:

1. Clone the repository.
2. Edit `env/supabase.yml` (263 lines, ~40 `#REQUIRED` fields, many defaulting to the literal placeholder `changeit`).
3. Run `sh generate-keys.sh` to fill in 10 cryptographic values.
4. Manually set the remaining required fields (`deploy_user`, `docker_users`, `site_url`, `api_external_url`, SMTP, and per-role SSO/S3/LUKS values).
5. Run `sudo bash install.sh`.

### Pain points

- **No guided path.** A new user must read and understand the entire `env/supabase.yml` (and `docs/advanced-docs.md`) before they can begin. There is no wizard, no questionnaire, no "minimal vs. advanced" separation.
- **No validation before deploy.** `install.sh` does not check for leftover `changeit` placeholders, missing DNS, closed ports 80/443, or absent system users. Failures surface mid-deploy inside Ansible, where they are hard to diagnose.
- **No component selection.** The 6 opt-in roles (`caddy`, `monitor`, `ufw`, `luks`, `fail2ban`, `backup`) are enabled by manually uncommenting lines in `playbook-supabase.yml`. The installer has no knowledge of which roles are active.
- **Not AI-usable.** An AI agent cannot reliably drive the current flow: it would have to parse free-form YAML comments, guess which fields are required per role, and edit a playbook by uncommenting lines. There is no machine-readable contract for "what must I provide to deploy component X?"
- **Secrets are mixed with config.** `generate-keys.sh` writes secrets directly into `env/supabase.yml` via `sed -i`, so the single config file ends up holding both user-provided values and generated secrets with no separation.

The result: installs that *appear* to work but fail at runtime, or installs that succeed but silently leave insecure defaults (`changeit`) in production.

---

## 2. Goals

### Primary goals

1. **Deterministic.** Given the same installer inputs, the same set of components, and a clean host, the deployment either fully succeeds or fails fast with an actionable error — never silently ships with `changeit` placeholders.
2. **Automatic.** The installer generates the necessary environment configuration from a small, explicit set of inputs and deploys the selected components without manual YAML editing.
3. **Usable by AI and humans.** The installer exposes a single, well-documented contract (a config schema + a CLI) that both a human and an AI agent can drive equivalently. No hidden state, no "edit this file then run that script" implicit steps.
4. **Clear separation of concerns.** The few things a user *must* decide are crystal clear and visually separated from advanced options. A minimal secure deployment needs ≤ ~10 decisions; everything else is opt-in and clearly labeled.

### Non-goals (explicitly out of scope for this issue)

- Multi-host / cluster deployment. The playbook targets `localhost` only; this issue does not change that.
- A GUI / web-based installer. The deliverable is a CLI / script-based installer.
- Replacing Ansible. The installer still produces `env/supabase.yml` and drives `ansible-playbook`; it does not rewrite the roles.
- Changing the role internals or the deployed Supabase service set (11 containers).
- Secret management backends (Vault, SOPS, cloud KMS). Generated secrets continue to live in the env file, consistent with the current `generate-keys.sh` approach.

---

## 3. Approach

### 3.1 Core idea

Introduce a **single installer entrypoint** — `setup.sh` (new) — that wraps the existing `install.sh` + `generate-keys.sh` flow behind a **configuration-driven, validating, component-aware** layer. The installer treats `env/supabase.yml` as its *output*, not its *input*.

```
                 ┌──────────────────────────────────────────────┐
   inputs ──────▶│            setup.sh (new)                     │
   (installer    │  ┌──────────────────────────────────────┐    │
   config +      │  │ 1. Load installer config             │    │
   CLI flags)    │  │ 2. Validate inputs + host preflight    │    │
                 │  │ 3. Select components (roles)          │    │
                 │  │ 4. Generate secrets (reuse gen-keys)   │    │
                 │  │ 5. Render env/supabase.yml from schema │    │
                 │  │ 6. Render playbook with selected roles │    │
                 │  │ 7. Preflight check (no changeit left)  │    │
                 │  │ 8. Hand off to install.sh              │    │
                 │  └──────────────────────────────────────┘    │
                 └──────────────────────────────────────────────┘
```

`install.sh` and `generate-keys.sh` are **kept and reused**, not removed — preserving backward compatibility for users who prefer the manual flow.

### 3.2 The installer config (the "deterministic" input)

A new, small, **human-and-AI-friendly** config file — `installer.yml` (or `installer.json`) — that contains *only* the decisions a user must make. It is the single input to `setup.sh`.

**Two clearly separated sections:**

```yaml
# ─────────────────────────────────────────────────────────────
# REQUIRED — you MUST set these. A minimal secure deployment
# needs nothing else. (~10 fields)
# ─────────────────────────────────────────────────────────────
required:
  deploy_user: ""          # e.g. "supabase" — must exist on the host
  site_url: ""             # e.g. "https://sb.example.com"
  api_external_url: ""     # e.g. "https://api.example.com"
  smtp:
    host: ""
    port: 587
    user: ""
    password: ""
    admin_email: ""

# ─────────────────────────────────────────────────────────────
# OPTIONAL / ADVANCED — leave commented to use safe defaults.
# Uncomment a component's block to enable it and be prompted
# for its required values.
# ─────────────────────────────────────────────────────────────
# components:
#   caddy:        # reverse proxy + TLS + SSO
#     enabled: false
#     sso_provider: ""      # github | gitlab | discord | generic
#     root_domain: ""
#     ...
#   monitor:
#     enabled: false
#     ...
#   ufw:    { enabled: false }
#   luks:   { enabled: false, device: "", passphrase: "" }
#   fail2ban: { enabled: false }
#   backup: { enabled: false, s3_endpoint: "", s3_bucket: "", ... }
```

**Why this is deterministic:** every field has an explicit type, a documented default, and a clear "required vs. optional" label. There are no `changeit` placeholders in `installer.yml` — empty required fields are a hard validation error *before* anything is deployed.

### 3.3 Component selection model

The installer maps `installer.yml → components` to the existing role set:

| `installer.yml` component | Ansible role | Always-on? |
|---|---|---|
| (implicit) | `docker` | yes |
| (implicit) | `supabase` | yes |
| `caddy` | `caddy` | opt-in |
| `monitor` | `monitor` | opt-in |
| `ufw` | `ufw` | opt-in |
| `luks` | `luks` | opt-in (gated by `supabase_encryption.enabled`) |
| `fail2ban` | `fail2ban` | opt-in |
| `backup` | `backup` | opt-in |

The installer renders `playbook-supabase.yml` (or a generated `playbook-runtime.yml`) with exactly the selected roles uncommented — replacing the current "manually uncomment lines" step with a deterministic, config-driven render. The two always-on roles (`docker`, `supabase`) are never optional.

### 3.4 Validation layers (the "deterministic" guarantee)

The installer runs three validation passes and **fails fast** on any error:

1. **Input validation** — `installer.yml` parses, all `required` fields are non-empty and well-typed, no `changeit`/empty values in required slots, per-component required fields present only when the component is enabled.
2. **Host preflight** — runs *before* Ansible: checks the target is Debian/Ubuntu, `sudo` works, ports 80/443 are reachable, DNS for `site_url`/`api_external_url` resolves to this host (warn, not fail, if mismatched), the `deploy_user` exists (or can be created), and Ansible is installed (or installable).
3. **Render preflight** — after generating `env/supabase.yml` and the playbook, scan the rendered env file for any remaining `changeit` placeholder or empty `#REQUIRED` field. If found, abort with a precise list of offending keys. Only then hand off to `install.sh`.

### 3.5 Secret generation

Reuse the existing `generate-keys.sh` logic (or inline its 10 secret generations) so secrets are produced deterministically and written into the rendered `env/supabase.yml`. The installer does **not** invent new secret formats — it uses the same values `generate-keys.sh` already produces, preserving compatibility with the roles.

### 3.6 AI-usable contract

To make the installer equally drivable by an AI agent:

- **`setup.sh --print-schema`** prints the JSON Schema of `installer.yml` (required fields, types, defaults, per-component requirements). An AI agent can introspect this without reading prose docs.
- **`setup.sh --validate installer.yml`** runs pass 1 only and exits non-zero with a structured (machine-parseable) error list on failure — so an AI can iterate on the config without deploying.
- **`setup.sh --dry-run`** runs passes 1–3 and prints the *plan* (selected roles, rendered env file path, the exact `ansible-playbook` command) without executing — so an AI (or human) can preview before committing.
- **`setup.sh --non-interactive`** never prompts; missing required fields are errors, not prompts. (Interactive mode is available for humans who prefer prompts.)
- All installer output is plain, line-oriented, prefix-tagged text (`[OK]`, `[WARN]`, `[ERROR]`, `[PLAN]`) for easy parsing.

### 3.7 Backward compatibility

- `install.sh` continues to work exactly as today for users who manually edit `env/supabase.yml`.
- `generate-keys.sh` continues to work standalone.
- `setup.sh` is additive: it calls into the existing scripts rather than replacing them.
- No changes to role internals, the 11 deployed containers, or `playbook-supabase.yml`'s role list (the installer renders a *copy* with selected roles uncommented, or toggles them via an Ansible `--extra-vars` mechanism — implementation detail for the build phase).

---

## 4. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | **Drift between `installer.yml` schema and `env/supabase.yml` / role defaults.** If a role adds a new required var, the installer won't know and will silently omit it. | Medium | High | The schema is generated/derived from the `#REQUIRED` comments in `env/supabase.yml` (or a single source-of-truth manifest) rather than hand-maintained. Add a CI check that diffs the schema against the env file's `#REQUIRED` markers. |
| R2 | **Secrets still live in a plaintext env file.** The installer does not improve the secret-storage posture; it only makes generation deterministic. | High | Medium | Out of scope per non-goals, but the spec calls it out: document that `env/supabase.yml` remains a secret-bearing file and must be `.gitignore`d / chmod-restricted. The installer should `chmod 600` the rendered file. |
| R3 | **Preflight checks give false confidence** (e.g., DNS resolves now but not at deploy time; port 80 open now but blocked later). | Medium | Medium | Preflight is a *best-effort gate*, not a guarantee. The installer prints a clear "preflight is a snapshot, not a deploy-time guarantee" notice and never claims success beyond "checks passed at T0". |
| R4 | **Two config files confuse users** (`installer.yml` vs. `env/supabase.yml`). | Medium | Medium | `env/supabase.yml` becomes a *generated artifact* when using `setup.sh`; the README is updated to say "edit `installer.yml`, not `env/supabase.yml`" when using the new flow. The manual flow remains documented as the "advanced" path. |
| R5 | **Breaking the existing manual flow.** Any change to `install.sh`/`generate-keys.sh`/`playbook-supabase.yml` could break current users. | Low | High | `setup.sh` is purely additive. The existing scripts are *called*, not rewritten. The playbook is rendered to a *new* file (`playbook-runtime.yml`) or driven via `--extra-vars`, leaving `playbook-supabase.yml` untouched. |
| R6 | **AI-driven installs run destructive ops without human confirmation.** `luks` (disk encryption), `backup` (overwrites S3), and the `docker` role's `containers_to_destroy` are irreversible. | Medium | High | `--non-interactive` mode refuses to enable `luks` or `backup` without an explicit `--i-understand-irreversible` flag (or an `irreversible_confirmed: true` field in `installer.yml`). The installer prints a prominent warning listing every irreversible action before handoff. |
| R7 | **Cross-platform assumptions.** Preflight assumes Debian/Ubuntu + apt; the roles already assume this, but the installer must not silently no-op on other distros. | Low | Medium | Preflight hard-fails on non-Debian/Ubuntu with a clear message pointing to the manual flow. |

---

## 5. Validation

This section defines **how we know the feature works** — the observable success criteria, independent of implementation details.

### 5.1 Functional acceptance criteria

- [ ] **AC1 — Minimal deploy from config.** Given an `installer.yml` with only the `required` block filled, `setup.sh` generates a valid `env/supabase.yml` (no `changeit`, no empty `#REQUIRED`), renders a playbook with only `docker` + `supabase` roles, and successfully hands off to `install.sh` on a clean Debian/Ubuntu host.
- [ ] **AC2 — Component opt-in.** Enabling `caddy` in `installer.yml` causes the rendered playbook to include the `caddy` role and the installer to require/validate the caddy-specific fields (`SSO_PROVIDER`, `root_domain`, etc.). Disabling it omits the role and does *not* prompt for caddy fields.
- [ ] **AC3 — Fail-fast on missing required.** An `installer.yml` with an empty `site_url` causes `setup.sh` to exit non-zero *before* any Ansible run, with a message naming the offending field. No partial deployment occurs.
- [ ] **AC4 — Fail-fast on leftover placeholders.** If the rendered `env/supabase.yml` still contains `changeit` for any reason (e.g., a role added a new var not in the schema), the render preflight aborts with the list of offending keys.
- [ ] **AC5 — Dry-run is side-effect-free.** `setup.sh --dry-run` prints the selected roles, the rendered env file path, and the exact `ansible-playbook` command, and writes no files / runs no Ansible.
- [ ] **AC6 — Schema introspection.** `setup.sh --print-schema` emits a valid JSON Schema that an external tool can validate an `installer.yml` against.
- [ ] **AC7 — Non-interactive AI path.** `setup.sh --non-interactive --validate installer.yml` exits 0 on a valid config and non-zero with a parseable error list on an invalid one, with no prompts and no side effects.
- [ ] **AC8 — Backward compatibility.** Running `install.sh` directly (without `setup.sh`) on a hand-edited `env/supabase.yml` still works exactly as before; no behavior change.
- [ ] **AC9 — Irreversible-op guard.** Enabling `luks` or `backup` in `--non-interactive` mode without explicit confirmation causes a hard failure with a clear message.

### 5.2 Verification approach (for the build phase)

- **Unit-level:** schema loader, validator, and env renderer are pure functions testable in isolation (input config → output YAML string). Test with a matrix of: minimal config, each component enabled alone, all components enabled, invalid configs.
- **Integration-level:** a `--dry-run` end-to-end test on a throwaway container (Debian/Ubuntu) that asserts the rendered `env/supabase.yml` has zero `changeit` and the rendered playbook lists exactly the expected roles.
- **Preflight-level:** mocked host checks (DNS resolve, port reachability, user existence) with both passing and failing fixtures.
- **Manual smoke:** a real deploy on a fresh VM using only `installer.yml` + `setup.sh`, confirming the 11 Supabase containers come up healthy.

### 5.3 Out-of-scope validation (explicitly not required by this issue)

- Performance benchmarks of the installer.
- Multi-host / cluster deploy validation.
- Upgrade/migration from an existing manual install to the installer-driven flow (documented as a follow-up, not a gate for this issue).

---

## 6. Open questions (to resolve before/during build)

1. **Config format:** `installer.yml` (YAML, consistent with the repo) vs. `installer.json` (easier JSON Schema tooling)? *Lean: YAML for humans, with a JSON Schema published alongside for AI/tooling.*
2. **Playbook rendering strategy:** generate a new `playbook-runtime.yml` vs. drive role selection via `ansible-playbook --extra-vars`/tags vs. templating `playbook-supabase.yml` in place? *Lean: generate a separate runtime playbook to keep the source playbook pristine.*
3. **Schema source of truth:** derive the `installer.yml` schema from the `#REQUIRED` comments in `env/supabase.yml` (DRY, but fragile parsing) vs. maintain a separate `installer.schema.yml` manifest (explicit, but can drift)? *Lean: separate manifest + CI drift check (R1).*
4. **Interactive prompts:** how much of the "human" experience should be prompt-driven vs. "edit the file then run"? *Lean: support both — `--interactive` prompts for missing required fields; default is file-driven + `--validate`.*
5. **Should `setup.sh` be bash (consistent with `install.sh`/`generate-keys.sh`) or Python (better schema/validation tooling)?** *Lean: bash wrapper calling a small Python helper for schema/validate/render, to keep the entrypoint consistent while gaining real tooling. Open for maintainer input.*

---

## 7. Implementation scope summary (for the build phase)

This spec covers **issue #87 only**. The build phase will produce:

1. `setup.sh` — the new installer entrypoint (CLI flags: `--validate`, `--dry-run`, `--print-schema`, `--non-interactive`, `--interactive`, component selection).
2. `installer.yml` — the new user-facing config (with a documented `required` block and commented `components` block).
3. `installer.schema.json` (or `.yml`) — the machine-readable schema, used by `--print-schema` and `--validate`.
4. A renderer that turns `installer.yml` → `env/supabase.yml` (reusing `generate-keys.sh` logic for secrets) and → a runtime playbook with selected roles.
5. Preflight checks (input, host, render) with fail-fast behavior.
6. README updates: a new "Quick start with `setup.sh`" section ahead of the manual flow, with the manual flow relabeled as "Advanced / manual".
7. CI check for schema↔env-file drift (R1 mitigation).

**Not produced by this issue:** role changes, new Supabase services, multi-host support, a GUI, or secret-backend integration.
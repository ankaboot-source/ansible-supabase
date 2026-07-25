# Spec: Default README Install Instructions Must Include Everything by Default

- **Issue:** ankaboot-source/ansible-supabase#89
- **Issue URL:** https://github.com/ankaboot-source/ansible-supabase/issues/89
- **Branch:** `looper/planner/89-default-readme-install-instructions`
- **Base branch:** `main`
- **Date:** 2026-07-25
- **Scope:** `README.md` install instructions (with alignment checks against `playbook-supabase.yml`, `env/supabase.yml`, and `docs/advanced-docs.md`)

---

## 1. Problem

The README's **Quick Start** currently presents a *minimal* deployment path as the default and relegates security, SSO/auth, encryption, monitoring, firewall, and backups to `docs/advanced-docs.md` under an "advanced features" framing. It ends with an explicit disclaimer:

> ⚠️ Security Notice: This minimal setup exposes the Supabase dashboard without any authentication. Anyone who can reach your server can access the Studio UI. For production deployments, enable basic auth, SSO, firewall rules, or the full Caddy reverse proxy — see docs/advanced-docs.md.

This contradicts the stated purpose of the repository: **to provide a ready-to-use, full-featured Supabase with security, encryption, and SSO/auth.** The default instructions should not ship an insecure path as the primary flow and then warn the user about it.

Concrete inconsistencies between the README and the shipped defaults:

1. **README "minimal" Caddy example** (no auth, no IP allow-list, no OIDC) does **not** match the actual `env/supabase.yml`, which ships with `oidc_enabled: true`, a `basicauth` block on `/project/default`, and an `allowed_ips` list. A user following the README literally diverges from the shipped config.
2. **Playbook defaults** (`playbook-supabase.yml`) enable only `docker` and `supabase`; `caddy`, `monitor`, `luks`, `fail2ban`, `backup`, and `ufw` are commented out. The README never tells the user these are part of the intended stack — it calls them "advanced."
3. **README Quick Start** never mentions SSO provider setup, the `auth.example.com` subdomain, `jwt_shared_key`, LUKS, backups, or the firewall — even though `env/supabase.yml` reserves variables for all of them and the repo's goal is to deliver them.
4. The **security disclaimer** frames the default as unsafe, which is the opposite of the repo's value proposition.

Net effect: a new user following the README gets an insecure dashboard and is told to go read a separate doc to fix it, instead of being guided through the secure, full-featured deployment as the default.

## 2. Goals

1. **Secure-by-default Quick Start.** The README's default install instructions guide the user through the full-featured, secured deployment (Caddy reverse proxy + SSO/auth, basic auth / IP allow-list, UFW firewall, LUKS encryption, monitoring, S3 backups, fail2ban) as the **primary** path — not as an "advanced" opt-in.
2. **Simple AND complete.** The README stays approachable: a single linear flow, tight tables, collapsible detail sections, and deep links into `docs/advanced-docs.md` for exhaustive reference. No wall of text; no missing steps.
3. **Remove the insecure-default framing.** Eliminate the "⚠️ Security Notice: this minimal setup exposes the dashboard…" disclaimer from the default flow. The minimal/no-auth path, if retained at all, becomes an explicitly labeled **opt-out** for local/testing use only — never the default.
4. **Consistency with shipped config.** README examples must match the actual defaults in `env/supabase.yml` and the role set in `playbook-supabase.yml`. Where the shipped default is a placeholder (`changeit`), the README must say so and link to the generator/section that fills it.
5. **Preserve `docs/advanced-docs.md` as the reference.** The README summarizes; the advanced doc remains the canonical deep dive. The README links to it per feature rather than duplicating it.

## 3. Non-Goals

- Rewriting `docs/advanced-docs.md` (out of scope — only cross-references may be adjusted).
- Changing the actual role implementations, templates, or Ansible logic.
- Removing the minimal/no-auth option entirely (it stays available, just not as the default).
- Rebranding, marketing copy, or non-install sections of the README (License, "What Gets Deployed" table, etc. — updated only if they become inconsistent).

## 4. Approach

### 4.1 README restructure

Replace the current Quick Start with a **secure-by-default, full-featured** flow. Keep it scannable with numbered steps, tables, and collapsible `<details>` blocks for the long per-feature config.

Proposed outline for the new Quick Start:

1. **Prerequisites** — expand to include the *full* set:
   - Debian/Ubuntu server with root/sudo
   - **Three** DNS A records: `sb.example.com` (Studio + API), `auth.example.com` (SSO endpoint), `monitor.example.com` (Grafana) — the third only if monitoring is enabled
   - Ports 80/443 reachable (Caddy auto-TLS + reverse proxy)
   - A registered OAuth2 app (GitHub / GitLab / Discord / generic OIDC) for SSO
   - (Optional) a separate block device for LUKS at-rest encryption
   - (Optional) an S3-compatible bucket for backups
2. **Clone** — unchanged.
3. **Generate keys** — `sh generate-keys.sh` — unchanged, but note it fills the Supabase crypto vars only; Caddy/SSO keys are generated in step 5.
4. **Enable the full role set** — show the *intended* `playbook-supabase.yml` with all roles uncommented (caddy, monitor, luks, fail2ban, backup, ufw), with a one-line note that any role can be commented out if unused. This is the single biggest change: the README's default playbook is the full stack, not `docker` + `supabase` only.
5. **Configure `env/supabase.yml`** — present the **secure default** as the primary example:
   - System user + Supabase secrets (auto-generated)
   - Public URLs (`site_url`, `api_external_url`)
   - SMTP
   - **SSO provider** (pick one; show GitHub as the canonical example, link to advanced doc for GitLab/Discord/generic) — `SSO_PROVIDER`, client id/secret, allow list, `base_auth_domain`, `root_domain`, `jwt_shared_key`
   - **Caddy `projects`** with `oidc_enabled: true`, dashboard upstream `oidc: true`, API routes `oidc: false`, plus the `basicauth` + `allowed_ips` fallbacks — matching the shipped `env/supabase.yml`
   - **UFW firewall** rules (allow 80/443/SSH; deny internal ports)
   - **LUKS** (`supabase_encryption.enabled: true` + device/mount vars) — with a clear "skip if no extra disk" note
   - **Monitoring** (Grafana auth mode + SMTP for alerts)
   - **S3 backups** (remote/provider/keys/endpoint/bucket + cron)
   - **Fail2ban** (defaults are fine)
   - Use collapsible `<details>` sections per feature so the page stays readable.
6. **Deploy** — `sudo ./install.sh` (and `-d` dry-run) — unchanged.
7. **Post-deploy verification** — short checklist: `docker ps`, Caddy TLS, SSO login round-trip, Grafana reachable, backup cron present, UFW status.

### 4.2 Handling the minimal path

Move the current no-auth Caddy example into a clearly labeled **"Minimal / testing-only setup"** collapsible section near the bottom of the Quick Start, with an explicit warning that it is **not for production** and that the default flow above is the supported one. This satisfies "stay simple" (people who want a quick local test can find it) without making it the default.

### 4.3 Remove the disclaimer

Delete the `> ⚠️ Security Notice …` block from the default flow. Any security caveats move into the minimal/testing section where they belong.

### 4.4 "What Gets Deployed" + "Advanced Features" sections

Keep the container table. Reframe the "Advanced Features" table as the **"Included Features"** table (they are part of the default stack now), and ensure each row links to the relevant `docs/advanced-docs.md` anchor.

### 4.5 Consistency pass

- Verify every README YAML snippet matches `env/supabase.yml` defaults (or explicitly notes a placeholder to replace).
- Verify the role list shown matches `playbook-supabase.yml` when fully uncommented.
- Verify all `docs/advanced-docs.md` anchor links resolve.

### 4.6 Out-of-scope alignment (flag, don't fix)

If during implementation it becomes clear that `playbook-supabase.yml` or `env/supabase.yml` *defaults* should actually be changed (e.g., uncomment roles by default, switch Grafana from anonymous to basic auth), **flag it in the spec's Risks section and do not change it in this issue's PR** — that's a separate decision with backward-compat implications. This issue is about the **README instructions**, not the shipped defaults.

## 5. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **README length / complexity** — full-featured flow is long and may overwhelm new users. | Medium | Use collapsible `<details>` blocks per feature; keep the top-level flow to ~6 numbered steps; push detail into `docs/advanced-docs.md`. |
| **Divergence from shipped defaults** — README shows full stack but `playbook-supabase.yml` ships roles commented out. | High | The README explicitly shows the user *uncommenting* roles; we do **not** change the playbook defaults in this PR (see 4.6). Document the gap clearly. |
| **Required-infra barrier** — SSO app, 3 subdomains, optional LUKS disk/S3 bucket raise the entry cost. | Medium | Mark optional prerequisites clearly; keep the minimal/testing path available; link to provider setup docs. |
| **Backward-compat surprise** — if a later PR flips playbook defaults, existing users upgrading could break. | Low (this PR) | This PR is README-only; no behavior change. Flag the defaults question for a separate issue. |
| **Stale links / anchors** — `docs/advanced-docs.md` anchors may drift. | Low | Validate all anchor links during implementation. |
| **Markdown rendering** — collapsible sections don't render on all viewers. | Low | GitHub renders `<details>`; that's the primary surface. Keep content readable when collapsed. |
| **Scope creep into advanced-docs.md** | Low | Non-goal; only cross-references may be touched. |

## 6. Validation

1. **Render check** — view the updated `README.md` on GitHub (or a local Markdown renderer that supports `<details>`); confirm the Quick Start reads as a single linear, secure-by-default flow.
2. **Disclaimer removed** — `grep -i "Security Notice" README.md` returns no match in the default flow (only, optionally, inside the minimal/testing section).
3. **Config consistency** — every YAML snippet in the README is reconciled against `env/supabase.yml`; placeholders (`changeit`) are explicitly called out.
4. **Playbook consistency** — the role list shown in the README matches `playbook-supabase.yml` with all roles uncommented.
5. **Link integrity** — all `docs/advanced-docs.md#anchor` links resolve (manual click-through or anchor grep).
6. **Scope adherence** — `git diff --stat` shows changes only to `README.md` (and this spec). No changes to roles, templates, `env/supabase.yml`, or `playbook-supabase.yml`.
7. **Issue closure criteria** — the README's default install instructions include security, SSO/auth, encryption, monitoring, firewall, and backups by default; the README is both simple and complete; the insecure-default disclaimer is gone from the primary flow.

## 7. Implementation Checklist

- [ ] Rewrite README Quick Start as secure-by-default, full-featured flow (steps 1–7 in §4.1).
- [ ] Add collapsible per-feature config sections (SSO, Caddy, UFW, LUKS, monitoring, backups, fail2ban).
- [ ] Move the no-auth Caddy example into a labeled "Minimal / testing-only" section with a production warning.
- [ ] Remove the `⚠️ Security Notice` disclaimer from the default flow.
- [ ] Reframe "Advanced Features" table as "Included Features" with anchor links to `docs/advanced-docs.md`.
- [ ] Reconcile every YAML snippet against `env/supabase.yml`; mark placeholders.
- [ ] Validate all markdown anchor links.
- [ ] Confirm `git diff --stat` is README-only (plus this spec).

## 8. Open Questions (for implementation, not blocking this spec)

1. Should the minimal/no-auth path be retained at all, or removed entirely? — *Spec assumes retained as a labeled testing-only opt-out; confirm with maintainer if needed.*
2. Should a follow-up issue flip `playbook-supabase.yml` defaults to uncomment all roles? — *Out of scope here; flagged in §4.6.*
3. Should `env/supabase.yml` defaults (e.g., Grafana anonymous → basic auth) be tightened in a separate PR? — *Out of scope here; flagged in §4.6.*
# Contributing

Contributions are welcome, and the bar is deliberately low. Bug reports, a fix for
a template that broke on your distro, a role that handles your provider — all
useful.

## You do not need a server

The test suite stubs out Ansible entirely, so the whole shell-level surface runs on
your laptop in a few seconds:

```bash
bash tests/test-setup.sh     # the deterministic installer
bash tests/test-backup.sh    # the backup role's rendering and guards
bash tests/test-migrate.sh   # migrate.sh argument handling and invariants
```

That covers config validation, secret generation, playbook regeneration and the
migration script's safety rails. If your change is in that territory, a green run
is enough — no VPS required.

For linting:

```bash
pip install ansible ansible-lint yamllint shellcheck-py
ansible-galaxy collection install -r requirements.yml

yamllint .
ansible-lint
shellcheck -S error setup.sh install.sh migrate.sh generate-keys.sh tests/*.sh
ansible-playbook playbook-supabase.yml -e @env/supabase.yml --syntax-check
```

CI runs exactly these, plus a real deployment on a throwaway runner.

## How the configuration flows

Getting this wrong is the most common source of a broken PR, so it is worth thirty
seconds:

```
config.yml  ──>  setup.sh  ──>  env/supabase.yml  ──>  ansible-playbook
                     │
                     └────────>  playbook-supabase.yml   (regenerated from
                                                          component toggles)
```

Users edit **only** `config.yml`. `setup.sh` validates it, renders variables into
`env/supabase.yml`, regenerates `playbook-supabase.yml` from the component toggles,
then hands off to `install.sh`.

**Adding a new variable** therefore means touching more than one file:

1. `config.example.yml` — the user-facing template, with a comment explaining it
2. `setup.sh` — read it and render it
3. `roles/<role>/defaults/main.yml` — a sensible default so it is optional
4. `docs/advanced-docs.md` — the reference entry

[`AGENTS.md`](AGENTS.md) documents this flow in more depth, along with the pitfalls
that have already bitten us — Jinja whitespace, Postgres SSL, Caddy SSO, pgBackRest
in-container quirks. It is written for coding agents but reads fine for humans, and
skimming the "Known Pitfalls" section will likely save you an afternoon.

## Pull requests

- **Small and focused beats complete.** One concern per PR.
- **Tests for behavioural changes.** If you change what `setup.sh` or `migrate.sh`
  does, add a case to the matching `tests/` script. If you change a template, say
  in the PR how you verified it renders.
- **Say what you actually ran.** "Deployed on Debian 12 with `caddy` and `backup`
  enabled" tells a reviewer more than a checklist of ticked boxes.
- **Say what you did not test.** Nobody has every combination of provider, distro
  and component. An honest gap is fine; a silent one costs someone else a debugging
  session.

Draft PRs are welcome if you want a direction check before finishing.

## Reporting bugs

Include the component toggles from your `config.yml` (**without the secrets**), your
distro and version, and the failing Ansible task with its output. `sudo bash
setup.sh --dry-run` output is often the fastest way to show what the installer
thinks your configuration is.

For anything security-related, do not open a public issue — see
[SECURITY.md](SECURITY.md).

## A note on scope

This project targets Debian and Ubuntu, with Arch support landing. RHEL-family
distributions are out of scope for now — SELinux changes enough of the picture that
half-support would be worse than none.

It also stays deliberately close to upstream Supabase: the official compose stack is
rendered, not forked. Changes that fork upstream behaviour are a hard sell, because
someone has to keep the fork alive at every Supabase release.

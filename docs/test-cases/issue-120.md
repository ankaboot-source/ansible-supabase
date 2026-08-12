# Test Cases — Issue #120: Instance Manifest + SSH stdio Agent

Tracks the acceptance criteria from [issue #120](https://github.com/ankaboot-source/ansible-supabase/issues/120). Each test maps to one or more acceptance checkboxes.

## TC-MANIFEST-001: Fresh install produces a valid manifest
**Acceptance:** Fresh install on all 3 server targets produces a manifest valid against the schema.
**Steps:**
1. Run the full playbook on a fresh Ubuntu 24.04, Debian 12, and Arch server.
2. Read `/etc/supabase/instance.json`.
3. Validate against the schema (schema_version=1, required fields present).
**Expected:** Valid JSON with all fields: `schema_version`, `generated_at`, `generated_by`, `supabase.{version,installed_at}`, `db.{host,port_direct,port_pooler,tenant_id,user,dbname,sslmode}`, `paths.{docker_dir,functions_volume,env_file}`, `containers.{db,edge_runtime,kong,auth,storage,rest}`, `endpoints.{api,studio}`, `secrets.*`.
**Targets:** Ubuntu 24.04, Ubuntu 22.04, Debian 12, Arch.

## TC-MANIFEST-002: `--tags manifest` regenerates without touching the stack
**Acceptance:** `--tags manifest` regenerates it without touching the stack.
**Steps:**
1. After a full deploy, note the running container IDs: `docker ps -q`.
2. Run `ansible-playbook playbook-supabase.yml --tags manifest -e @env/supabase.yml`.
3. Check container IDs again: `docker ps -q`.
**Expected:** Manifest `generated_at` updated; container IDs unchanged (no restart).

## TC-MANIFEST-003: Second full run updates `generated_at`, byte-identical otherwise
**Acceptance:** A second full run updates `generated_at` and is otherwise byte-identical.
**Steps:**
1. After a full deploy, copy the manifest: `cp /etc/supabase/instance.json /tmp/run1.json`.
2. Run the full playbook again.
3. Diff: `diff <(jq 'del(.generated_at)' /tmp/run1.json) <(jq 'del(.generated_at)' /etc/supabase/instance.json)`.
**Expected:** Empty diff (only `generated_at` changed). `installed_at` preserved.

## TC-MANIFEST-004: No `.env` value appears in the manifest
**Acceptance:** Automated check: no value from `.env` appears anywhere in manifest.
**Steps:**
1. After a full deploy, extract every `KEY=VALUE` from `/home/<deploy_user>/supabase/docker/.env`.
2. For each value (non-empty, non-placeholder), `grep -F -c '<value>' /etc/supabase/instance.json`.
3. Also rely on the role's built-in leak assertions (4 `grep -F` checks for `postgres_db_pwd`, `sb_jwt_secret`, `sb_anon_key`, `sb_service_role_key`).
**Expected:** Zero matches for every secret value. The role's assertion tasks fail the run if any leak is detected.

---

## TC-SSH-001: Key cannot open a shell
**Acceptance:** `ssh -i <key> <host> whoami` fails — the key cannot open a shell.
**Steps:**
1. `ssh -i ~/.ssh/supabase-agent-<host> <alias> whoami`
**Expected:** Fails (non-zero exit). The `command="..."` restriction in authorized_keys forces the agent binary, ignoring the requested command.

## TC-SSH-002: Port forwarding refused
**Acceptance:** `ssh -i <key> -L 9999:localhost:9999 <host>` fails — forwarding is refused.
**Steps:**
1. `ssh -i ~/.ssh/supabase-agent-<host> -L 9999:localhost:9999 -fN <alias>` (or without `-fN`).
**Expected:** Fails. The `no-port-forwarding` restriction in authorized_keys blocks it.

## TC-SSH-003: MCP byte test
**Acceptance:** Piping an MCP `initialize` into `ssh <alias> supabase-agent` returns a stream whose first byte is `{`. Distro-agnostic.
**Steps:**
1. `printf '%s' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' | ssh <alias> supabase-agent | head -c 1 | od -c | head -1`
**Expected:** First byte is `{` (0000000   {). No shell preamble, no MOTD, no banner pollutes stdout.
**Targets:** Ubuntu 24.04, Debian 12, Arch.

---

## TC-SECRET-001: `info` on terminal shows real values
**Acceptance:** `supabase-selfhosted info` on a terminal shows real values.
**Steps:**
1. SSH into the server with a TTY: `ssh <user>@<host>`.
2. Run `supabase-selfhosted info`.
**Expected:** Real connection strings, anon key, service_role key, JWT secret, dashboard credentials shown.

## TC-SECRET-002: Piped/redirected/over ssh shows `••••` + reference
**Acceptance:** Piped, redirected, or run over `ssh <alias> supabase-selfhosted info`, it shows `••••` and the reference.
**Steps:**
1. `supabase-selfhosted info | cat`
2. `supabase-selfhosted info > /tmp/out.txt; cat /tmp/out.txt`
3. `ssh <user>@<host> supabase-selfhosted info` (no TTY)
**Expected:** All three show `••••` plus `env_file` + `key` reference for each secret.

## TC-SECRET-003: `--show-secrets` reveals in all 3 cases
**Acceptance:** `--show-secrets` reveals in all three of those cases.
**Steps:**
1. `supabase-selfhosted info --show-secrets | cat`
2. `supabase-selfhosted info --show-secrets > /tmp/out.txt; cat /tmp/out.txt`
3. `ssh <user>@<host> supabase-selfhosted info --show-secrets`
**Expected:** All three show real values.

## TC-SECRET-004: No MCP tool returns a secret value
**Acceptance:** No MCP tool returns a secret value.
**Steps:**
1. Connect via `ssh <alias> supabase-agent`.
2. Call `tools/list` — confirm no tool claims to return secret values.
3. Call each tool (`list_tables`, `describe_table`, `query`, `list_containers`, `container_status`, `get_manifest`).
4. Inspect every response for any value matching a known secret.
**Expected:** No secret value appears in any MCP response. The `get_env_var` tool does NOT exist.

---

## TC-DOCS-001: Clean Manjaro client yields working agent connection
**Acceptance:** Following `docs/connect-your-agent.md` from a clean Manjaro machine yields a working agent connection.
**Steps:**
1. On a clean Manjaro machine, install openssh if missing: `sudo pacman -S openssh`.
2. Follow `docs/connect-your-agent.md` steps 1-4.
3. Run `sh scripts/verify-connection.sh ~/.ssh/supabase-agent-<host> supabase-agent`.
**Expected:** All checks pass. MCP byte test returns `{`.

## TC-DOCS-002: Clean macOS client yields working agent connection
**Acceptance:** Same from a clean macOS machine.
**Steps:**
1. On a clean macOS machine, follow `docs/connect-your-agent.md` steps 1-4.
2. Run `sh scripts/verify-connection.sh ~/.ssh/supabase-agent-<host> supabase-agent`.
**Expected:** All checks pass. POSIX-clean script works on BSD userland.

## TC-DOCS-003: `verify-connection.sh` is POSIX-clean
**Acceptance:** `scripts/verify-connection.sh` is POSIX-clean and passes on both GNU and BSD userlands.
**Steps:**
1. `sh -n scripts/verify-connection.sh` (syntax check).
2. `dash -n scripts/verify-connection.sh` (if dash available — catches bashisms).
3. `grep -nE '\[\[|echo -e|\$\(<' scripts/verify-connection.sh` (bashism scan).
4. Run on Linux (GNU userland) and macOS (BSD userland).
**Expected:** No syntax errors, no bashisms, passes on both.

---

## TC-DOCKER-001: Docker role installs on Arch
**Acceptance:** (implicit) Docker role supports Arch.
**Steps:**
1. Run the playbook on a fresh Arch server.
2. Check `docker compose version` succeeds (compose v2).
3. Check `systemctl is-active docker` is `active`.
**Expected:** Docker + compose v2 installed via pacman, service running.

## TC-DOCKER-002: Docker role still works on Debian family
**Acceptance:** (regression) Existing Ubuntu/Debian support unchanged.
**Steps:**
1. Run the playbook on a fresh Ubuntu 24.04 and Debian 12 server.
2. Check `docker compose version` succeeds.
3. Check `systemctl is-active docker` is `active`.
**Expected:** Docker + compose v2 installed via apt CE repo, service running.

## TC-BOOTSTRAP-001: Python bootstrap on minimal images
**Acceptance:** (implicit) First play bootstraps Python on minimal targets.
**Steps:**
1. Run the playbook on a minimal Ubuntu cloud image (no python3) and on Arch (python only).
**Expected:** Bootstrap play installs python3/python before the main play runs `gather_facts`.
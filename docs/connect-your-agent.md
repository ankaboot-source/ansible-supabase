# Connect Your AI Agent

Connect Claude Code, Codex, opencode, or pi to your self-hosted Supabase via
SSH stdio. The Ansible role `agent_access` provisions a
dedicated, command-restricted SSH key on the server. Your agent runs the
remote command `supabase-agent`, which speaks MCP-over-stdio through the
authenticated SSH channel.

The agent config — `{ command, args }` — is identical for every agent. Only
the file you put it in differs.

---

## Prerequisites

- The server is already deployed via `ansible-supabase` (the
  `agent_access` role must have run).
- You have the deployment output: a **private key** and an **SSH config
  block** containing `Host supabase-agent`, `HostName`, `User`, and
  `IdentityFile`.
- Your local machine has an OpenSSH client (`ssh -V` should print a version).
  On Manjaro, install it with `sudo pacman -S openssh` if it is missing.

---

## Step 1 — Install the private key

> **`~/.ssh` must be mode `0700`.** If the directory is group- or
> world-readable, `ssh` refuses to use keys inside it. The error message
> misleadingly points at the key file (`Permissions ... are too open`),
> not at the directory. Run `chmod 0700 ~/.ssh` first if needed.

Create the key file with the correct mode, then paste the private key
printed by the deployment:

```sh
# Replace <host> with the server's name (e.g. myserver, prod, vps1)
install -m 0600 /dev/null ~/.ssh/supabase-agent-<host>
${EDITOR:-vi} ~/.ssh/supabase-agent-<host>
# paste the key, save, exit
```

The path is `~/.ssh/supabase-agent-<host>`, mode `0600`. Never share this
file or check it into version control.

---

## Step 2 — Add the SSH config block

The deployment also prints an `Host supabase-agent` block. Paste it into
`~/.ssh/config` (create the file with mode `0600` if it does not exist):

```
Host supabase-agent
  HostName <your-server-ip-or-domain>
  User <deploy_user>
  IdentityFile ~/.ssh/supabase-agent-<host>
  IdentitiesOnly yes
  ControlMaster auto
  ControlPath ~/.ssh/sockets/supabase-agent-%r@%h:%p
  ControlPersist 10m
```

`ControlPath` points to `~/.ssh/sockets/`, so the directory must exist or
SSH will fail the connection silently. Create it once:

```sh
mkdir -p ~/.ssh/sockets
chmod 0700 ~/.ssh
chmod 0700 ~/.ssh/sockets
```

Replace `<host>`, `<your-server-ip-or-domain>`, and `<deploy_user>` with
the values from your deployment output. The alias (`supabase-agent`) is
the literal name used by all four agents in Step 3 — do not rename it
unless you also update the agent config.

> **macOS** — OpenSSH is preinstalled; `ControlMaster` works the same
> way. The config block is identical. No changes needed.

---

## Step 3 — Configure your agent

All four agents take the same `command` + `args` shape:

```
command:  ssh
args:     [supabase-agent, supabase-agent]
```

The first `supabase-agent` is the SSH alias. The second is the command
the server runs, which starts the MCP server on stdio. The file you put
this in differs per agent.

**Claude Code** — `.mcp.json` in the project root, or globally:

```json
{
  "mcpServers": {
    "supabase": {
      "command": "ssh",
      "args": ["supabase-agent", "supabase-agent"]
    }
  }
}
```

Or via the CLI: `claude mcp add supabase -- ssh supabase-agent supabase-agent`

**Codex** — `~/.codex/config.toml`:

```toml
[[mcp_servers]]
name = "supabase"
command = "ssh"
args = ["supabase-agent", "supabase-agent"]
```

**opencode** — `~/.config/opencode/opencode.json` (or in the project's
`opencode.json`):

```json
{
  "mcp": {
    "supabase": {
      "type": "local",
      "command": ["ssh", "supabase-agent", "supabase-agent"]
    }
  }
}
```

**pi** — `~/.pi/agent/mcp.json` (check your version's docs for the
exact path):

```json
{
  "mcpServers": {
    "supabase": {
      "command": "ssh",
      "args": ["supabase-agent", "supabase-agent"]
    }
  }
}
```

> The exact config file paths and JSON keys can change between agent
> versions. If a path above does not match your install, consult your
> agent's MCP documentation for the current location — but the
> `command` / `args` shape is universal and will not change.

Restart your agent after editing the config so it picks up the new MCP
server.

---

## Step 4 — Verify

From the repository checkout (the same one you used to deploy), run the
verification script:

```sh
./scripts/verify-connection.sh ~/.ssh/supabase-agent-<host> supabase-agent
```

The script checks, in order:

1. `~/.ssh` is mode `0700`.
2. `~/.ssh/sockets/` exists (creates it if missing).
3. The private key file exists and is mode `0600`.
4. `~/.ssh/config` has a `Host supabase-agent` block.
5. `ssh ... whoami` is **rejected** (the command restriction blocks
   shell access — this must fail).
6. `ssh ... -L 9999:localhost:9999 true` is **rejected** (port
   forwarding is blocked).
7. An MCP `initialize` request piped into `ssh ... supabase-agent`
   returns a JSON object (first byte is `{`).

The script exits `0` on success and `1` if any check fails. It is
POSIX-clean and works on both Linux (GNU) and macOS (BSD) userland — it
does not branch on `uname` and contains no bashisms.

---

## Security model: read-only is enforced by the database

The `agent_access` MCP server connects to Postgres as a **dedicated read-only
role (`agent_reader`)**, *not* the `postgres` superuser. This is a
**database-enforced** boundary, not just SSH or a SQL filter:

- The `agent_reader` role is provisioned with `SELECT`-only grants on every
  schema (`public`, `auth`, `storage`, `realtime`, `graphql`, `vault`,
  `_analytics`, `supabase_functions`).
- Every query the agent runs is additionally wrapped in
  `BEGIN; SET TRANSACTION READ ONLY; ... COMMIT;`, so Postgres itself rejects
  any write — `INSERT`, `UPDATE`, `DELETE`, or DDL — even if a grant were
  misconfigured.
- New tables created **after** deployment are automatically readable thanks to
  `ALTER DEFAULT PRIVILEGES` — no cron job or trigger is needed.

### Reading tables in a custom schema

The agent is pre-granted access to the standard Supabase schemas. If you create
your **own schema** and want the agent to read it, run these as the
`postgres` (or `supabase_admin`) superuser:

```sql
GRANT USAGE ON SCHEMA <schema> TO agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA <schema> TO agent_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA <schema> GRANT SELECT ON TABLES TO agent_reader;
```

The `ALTER DEFAULT PRIVILEGES` line makes any **future** table in that schema
readable too. Repeat the `GRANT ... ON ALL TABLES` line whenever you add tables
to an existing custom schema if you don't want to rely on the default
privileges.

> **Why not use Studio's MCP for the agent?** The built-in Studio MCP
> (`/mcp` behind Kong) is convenient and works over an SSH tunnel, but its
> read-only is **transport-level only** — it runs through Studio's `postgres`
> superuser connection and has no DB-side read-only mode. `agent_access` is
> the hardened option because read-only is enforced by the role and the
> read-only transaction, independent of the `postgres` superuser.

---

## Troubleshooting

**`Permission denied (publickey)`**

Two common causes, both about file modes:

- The private key is not mode `0600`. Run `chmod 0600 ~/.ssh/supabase-agent-<host>`.
- `~/.ssh` is not mode `0700`. Run `chmod 0700 ~/.ssh`. Note that the
  error message from `ssh` points at the key file, not the directory —
  the directory is the real culprit.

**`Could not resolve hostname supabase-agent` / `ssh: Could not connect`**

- The `Host supabase-agent` block is missing from `~/.ssh/config`. Add
  it from Step 2.
- The server is down, or port `22` is blocked. Test with
  `ssh -v -i ~/.ssh/supabase-agent-<host> <user>@<host> true` (replace
  `<host>` with the IP or domain from the config block) — the
  unrestricted key from your server admin can do this; the agent key
  cannot.
- `~/.ssh/sockets/` does not exist and `ControlPath` is failing
  silently. Run `mkdir -p ~/.ssh/sockets`.

**`bash: supabase-agent: command not found`**

The `agent_access` role did not run successfully on the
server, or its install task was skipped. Re-run the full playbook:

```sh
./setup.sh && ./install.sh
```

**MCP server returns non-JSON or hangs**

The first byte of the response should be `{`. If it is something else,
or if the script times out on Step 7, the remote `supabase-agent`
binary may be missing or broken. SSH to the server with an
unrestricted key and check:

```sh
sudo -iu <deploy_user> command -v supabase-agent
sudo -iu <deploy_user> supabase-agent < /dev/null
```

The second command should print a JSON-RPC error to stderr (or exit
non-zero) because no `initialize` was sent — that confirms the binary
is present and runnable.

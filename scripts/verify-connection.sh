#!/bin/sh
# verify-connection.sh — Confirm the agent SSH key + alias are set up
# correctly, the command restriction is in effect, and the remote MCP
# server responds with JSON.
#
# Usage: verify-connection.sh <key-path> <host-alias>
# Example: verify-connection.sh ~/.ssh/supabase-agent-myserver supabase-agent
#
# POSIX-clean. Works on GNU (Linux) and BSD (macOS) userland.
# Does not branch on `uname` and contains no bashisms.

set -u

# ---- output helpers (avoid echo -e; use printf) -----------------------
RED=""
GREEN=""
YELLOW=""
RESET=""
if [ -t 1 ]; then
  RED=$(printf '\033[31m')
  GREEN=$(printf '\033[32m')
  YELLOW=$(printf '\033[33m')
  RESET=$(printf '\033[0m')
fi

info()  { printf '%s==>%s %s\n' "$YELLOW" "$RESET" "$1"; }
pass()  { printf '%s   OK%s  %s\n' "$GREEN"  "$RESET" "$1"; }
fail()  { printf '%s FAIL%s  %s\n' "$RED"    "$RESET" "$1"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

# ---- argument handling -----------------------------------------------
usage() {
  cat <<'EOF'
Usage: verify-connection.sh <key-path> <host-alias>

  <key-path>   Path to the private key (e.g. ~/.ssh/supabase-agent-myserver)
  <host-alias> The SSH alias from ~/.ssh/config (e.g. supabase-agent)

Example:
  verify-connection.sh ~/.ssh/supabase-agent-myserver supabase-agent
EOF
  exit 2
}

[ $# -eq 2 ] || usage

KEY_PATH=$1
HOST_ALIAS=$2

# Expand a leading "~" or "~/" to $HOME. Don't use readlink -f (BSD).
expand_tilde() {
  case "$1" in
    '~')       printf '%s' "$HOME" ;;
    '~/'*)     printf '%s/%s' "$HOME" "${1#~/}" ;;
    *)         printf '%s' "$1" ;;
  esac
}

KEY_PATH=$(expand_tilde "$KEY_PATH")
HOME_DIR=${HOME:-/tmp}

SSH_DIR="$HOME_DIR/.ssh"
SOCKETS_DIR="$SSH_DIR/sockets"
CONFIG_FILE="$SSH_DIR/config"

# ---- preconditions: tools --------------------------------------------
if ! command -v ssh >/dev/null 2>&1; then
  fail "ssh is not installed (On Manjaro: sudo pacman -S openssh)"
  printf '\nSome checks failed.\n'
  exit 1
fi

# ---- check 1: ~/.ssh exists and is mode 0700 -------------------------
info "Check 1: $SSH_DIR exists and is mode 0700"
if [ ! -d "$SSH_DIR" ]; then
  fail "$SSH_DIR does not exist. Run: mkdir -p -m 0700 $SSH_DIR"
else
  # Portable mode check: read the mode field from `ls -ld` and compare
  # it to the canonical 0700 string. ls -ld mode format is consistent
  # enough across GNU/BSD that a plain string match works.
  ls_perm=$(ls -ld "$SSH_DIR" 2>/dev/null | awk '{print $1}')
  case "$ls_perm" in
    drwx------)
      pass "$SSH_DIR is mode 0700"
      ;;
    *)
      fail "$SSH_DIR has permissions '$ls_perm'. The SSH client refuses to read keys from a directory that is group- or world-accessible. Run: chmod 0700 $SSH_DIR  (NB: the error from ssh points at the key file, but the directory is the real cause.)"
      ;;
  esac
fi

# ---- check 2: ~/.ssh/sockets exists ---------------------------------
info "Check 2: $SOCKETS_DIR exists (required by ControlPath)"
if [ -d "$SOCKETS_DIR" ]; then
  pass "$SOCKETS_DIR exists"
else
  printf '   ... creating %s\n' "$SOCKETS_DIR"
  if mkdir -p "$SOCKETS_DIR" 2>/dev/null; then
    chmod 0700 "$SOCKETS_DIR" 2>/dev/null
    pass "created $SOCKETS_DIR"
  else
    fail "could not create $SOCKETS_DIR. Run: mkdir -p -m 0700 $SOCKETS_DIR"
  fi
fi

# ---- check 3: private key exists and is mode 0600 --------------------
info "Check 3: private key $KEY_PATH exists and is mode 0600"
if [ ! -f "$KEY_PATH" ]; then
  fail "$KEY_PATH does not exist. Paste the key from the deployment output and chmod 0600 it."
elif [ -L "$KEY_PATH" ]; then
  # symlink: check the target instead
  target=$(ls -ld "$KEY_PATH" | awk '{print $NF}')
  fail "$KEY_PATH is a symlink to $target. Replace it with a real file (mode 0600)."
else
  case "$(ls -l "$KEY_PATH" | awk '{print $1}')" in
    -rw-------)
      pass "$KEY_PATH is mode 0600"
      ;;
    *)
      actual=$(ls -l "$KEY_PATH" | awk '{print $1}')
      fail "$KEY_PATH has permissions '$actual'. Must be 0600. Run: chmod 0600 $KEY_PATH"
      ;;
  esac
fi

# ---- check 4: ~/.ssh/config has a Host <alias> block ----------------
info "Check 4: $CONFIG_FILE has a Host $HOST_ALIAS block"
if [ ! -f "$CONFIG_FILE" ]; then
  fail "$CONFIG_FILE does not exist. Create it (mode 0600) and paste the Host block from Step 2."
else
  if grep -Eq "^[[:space:]]*Host[[:space:]]+([^#]*[[:space:]])?$HOST_ALIAS([[:space:]]|$)" "$CONFIG_FILE"; then
    pass "Host $HOST_ALIAS found in $CONFIG_FILE"
  else
    fail "no 'Host $HOST_ALIAS' line in $CONFIG_FILE. Add the block from Step 2."
  fi
fi

# If prerequisites are broken, the remaining checks are pointless and
# the byte test will produce a confusing failure. Bail out with a
# summary.
if [ "$FAILURES" -gt 0 ]; then
  printf '\nPrerequisites failed (%d). Fix the above and re-run.\n' "$FAILURES"
  exit 1
fi

# ---- check 5: ssh <alias> whoami does NOT open a shell ----------------
# The key is command-restricted (command="<agent>" in authorized_keys),
# so sshd IGNORES the requested command and always runs the agent, which
# answers MCP JSON (starts with `{`). A real shell would have answered
# `whoami` with a username, so JSON is the proof of the restriction —
# NOT ssh's exit code: a forced command always exits with the agent's
# code (0 on EOF). stdin is piped, never a TTY, so the forced agent
# cannot block this check.
info "Check 5: ssh $HOST_ALIAS whoami runs the agent, not a shell (command restriction)"
mcp_sc5='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify-c5","version":"0.1.0"}}}'
resp_c5=$(printf '%s\n' "$mcp_sc5" | ssh -i "$KEY_PATH" \
      -o BatchMode=yes \
      -o ConnectTimeout=10 \
      -o ClearAllForwardings=yes \
      "$HOST_ALIAS" whoami 2>/dev/null)
rc_c5=$?
if [ "$rc_c5" -ne 0 ]; then
  fail "ssh exited $rc_c5 — is the key/alias correct?"
elif [ "${resp_c5#\{}" != "$resp_c5" ]; then
  pass "shell blocked — the forced command returned MCP JSON, not a username"
else
  fail "expected MCP JSON from the forced command, got: '$(printf '%.40s' "$resp_c5")' — the command restriction may not be in effect."
fi

# ---- check 6: port forwarding is unusable ---------------------------
# The key carries `no-port-forwarding`. A forced command makes ssh's exit
# code the agent's (0 on EOF), so a -L attempt cannot be judged by exit
# status. Instead: while an agent session (created with -L) is alive,
# connect to the local listen port and send a probe that would reach the
# server loopback IF forwarding were allowed. With the restriction in
# force, sshd refuses the direct-tcpip channel, the local connection is
# dropped immediately and no bytes come back. Requires `nc`; degrades to
# an informational pass when absent.
info "Check 6: ssh $HOST_ALIAS -L forward is unusable (no-port-forwarding)"
lport=19999
if command -v nc >/dev/null 2>&1; then
  # Keep the session alive for ~2s: `sleep` holds the pipe open so the
  # forced agent keeps reading stdin instead of exiting at EOF.
  ( printf '%s' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify-c6","version":"0.1.0"}}}'
    printf '\n'
    sleep 2 ) | \
    ssh -i "$KEY_PATH" \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o ClearAllForwardings=yes \
        -L "$lport":127.0.0.1:3001 \
        "$HOST_ALIAS" true >/dev/null 2>&1 &
  spid=$!
  sleep 1
  if ! kill -0 "$spid" 2>/dev/null; then
    fail "ssh session did not stay up for the forward probe — check key/alias and that local port $lport is free"
  else
    # Probe: forwarded, the server's Studio (127.0.0.1:3001) answers with
    # an HTTP response; refused, the local connection dies with no data.
    got=$(printf 'GET / HTTP/1.0\r\n\r\n' | nc -w 2 127.0.0.1 "$lport" | head -c 1 2>/dev/null)
    if [ -n "$got" ]; then
      fail "a byte reached the server loopback — no-port-forwarding is not in effect. Re-run the role."
    else
      pass "forward dropped — no data reached the server loopback (no-port-forwarding enforced)"
    fi
  fi
  kill "$spid" 2>/dev/null
  wait "$spid" 2>/dev/null
else
  pass "nc not found — skipped active forward probe (manual: ssh -L 9999:localhost:3001 $HOST_ALIAS, connect locally, expect no bytes back)"
fi

# ---- check 7: byte test — MCP responds with JSON --------------------
# Pipe an `initialize` request into `ssh ... supabase-agent` and check
# the first byte of the response is `{`. We use head -c 1, which exits
# after one byte and closes the pipe; ssh gets SIGPIPE and exits. This
# is portable and avoids depending on the `timeout` command (which
# macOS lacks).
info "Check 7: ssh $HOST_ALIAS supabase-agent responds to MCP initialize"
mcp_request='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"0.1.0"}}}'

# Run ssh in the background, read one byte, kill ssh. Using a temp
# file for the response avoids subshell / pipe issues across shells.
resp_tmp=$(mktemp 2>/dev/null) || resp_tmp="/tmp/verify-conn.$$"
trap 'rm -f "$resp_tmp"' EXIT HUP INT TERM

# shellcheck disable=SC2086
printf '%s\n' "$mcp_request" | ssh -i "$KEY_PATH" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ClearAllForwardings=yes \
    "$HOST_ALIAS" supabase-agent >"$resp_tmp" 2>/dev/null &
ssh_pid=$!

# Give ssh up to 5 seconds to produce a first byte. Read one byte at a
# time from the response file using `head -c N` in a loop with a sleep
# budget — portable, no `inotifywait` / `timeout` dependency.
got_byte=0
i=0
while [ "$i" -lt 50 ]; do
  if [ -s "$resp_tmp" ]; then
    # File has data; read one byte and check it.
    first=$(head -c 1 "$resp_tmp" 2>/dev/null)
    if [ -n "$first" ]; then
      got_byte=1
      break
    fi
  fi
  # Bail if ssh already exited without writing.
  if ! kill -0 "$ssh_pid" 2>/dev/null; then
    break
  fi
  i=$((i + 1))
  sleep 0.1
done

# Clean up ssh (it may still be running if head -c 1 closed the pipe).
kill "$ssh_pid" 2>/dev/null
wait "$ssh_pid" 2>/dev/null

if [ "$got_byte" -eq 0 ]; then
  fail "no response from 'ssh $HOST_ALIAS supabase-agent' within 5s. The remote binary is missing or unreachable. Run on the server: command -v supabase-agent"
else
  case "$first" in
    '{')
      pass "MCP server responded with JSON (first byte: '{')"
      ;;
    *)
      fail "MCP server response does not start with '{'. Got: '$first'. Re-run the role or check the remote binary."
      ;;
  esac
fi

# ---- summary ---------------------------------------------------------
printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf '%sAll checks passed.%s You can now connect your agent.\n' "$GREEN" "$RESET"
  exit 0
else
  printf '%s%d check(s) failed.%s See above for details.\n' "$RED" "$FAILURES" "$RESET"
  exit 1
fi

# Design Canvas: Secure MCP Remote Access

## Problem

The Supabase MCP (Model Context Protocol) server endpoint (`/mcp` →
`http://studio:3000/api/mcp`) can be exposed to the public Internet. A naive
`ip-restriction` allow list of `127.0.0.1`/`::1` does not work here because
Docker source-NATs every host-originated connection to the Docker bridge gateway
IP before it reaches Kong — so Kong never sees a loopback source. The allow list
must contain that gateway IP instead. The `/api/mcp` direct route stays fully
blocked so remote clients can only reach the endpoint via an SSH tunnel.

## Goal

Provide a secure remote-access solution so authorized clients can connect to the
MCP server **without** requiring the service to be publicly accessible.

## Approach: SSH Tunnel (Port Forwarding)

SSH tunneling is the chosen mechanism because:

1. **Zero public exposure** — the MCP endpoint stays bound to localhost; no new
   public ports, no reverse-proxy route, no public DNS record.
2. **Reuses existing infrastructure** — SSH (port 22) is always allowed through
   the UFW firewall and is already required to administer the server.
3. **Strong authentication** — SSH key authentication is the same trust boundary
   already used for server administration.
4. **No new services to deploy or maintain** — unlike a VPN (WireGuard/Tailscale)
   or an OAuth proxy, an SSH tunnel needs no daemon, no certificates, and no
   configuration drift.
5. **Standard practice** — SSH port forwarding is the canonical pattern for
   reaching internal/admin services (databases, dashboards) from remote clients.

## Design

### Kong layer (defense-in-depth)

The `/mcp` Kong route is restricted to host-originated traffic via the
`ip-restriction` plugin. Because of Docker bridge NAT, connections from the host
(including SSH tunnels) appear to Kong with the compose network gateway IP as
the source. The compose file pins the network subnet (`172.28.0.0/16`) so the
gateway is deterministically `172.28.0.1`, and `mcp_allowed_ips` defaults to that
gateway. External clients keep their real public IP, which is not in the allow
list, so they stay blocked. The `/api/mcp` direct route stays fully blocked
(request-termination 403) so the only reachable path is `/mcp` from the server
itself. Set `mcp_allowed_ips: []` to fully disable `/mcp`.

### Firewall layer

Port `8000` (Kong) remains in `firewall_deny` by default. Even if an operator
accidentally opens it, the Kong IP restriction still blocks external clients.

### Caddy layer

The MCP endpoint is **never** reverse-proxied through Caddy. There is no public
subdomain or TLS termination for `/mcp`. This is enforced by documentation and
by the absence of any `/mcp` path in the example Caddy upstream configurations.

### Client access

Authorized clients connect via SSH local port forwarding:

```bash
ssh -L 8080:localhost:8000 deploy_user@sb.example.com
# Then point the MCP client at http://localhost:8080/mcp
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `mcp_allowed_ips` | `[172.28.0.1]` | IPs allowed to reach `/mcp` via Kong. Default is the Docker bridge gateway (host-originated traffic incl. SSH tunnels). Set `[]` to fully disable. Must match the pinned subnet gateway in `docker-compose-supabase.yml.j2`. |

## Out of scope

- VPN setup (WireGuard/Tailscale) — documented as an alternative but not
  implemented as a role.
- OAuth/SSO protection for MCP — MCP is a server-to-server protocol; interactive
  OIDC login does not fit the client model.
- mTLS at the Kong layer — possible future enhancement, not required for the
  SSH-tunnel approach.
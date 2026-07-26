# Design Canvas: Secure MCP Remote Access

## Problem

The Supabase MCP (Model Context Protocol) server endpoint (`/mcp` →
`http://studio:3000/api/mcp`) can be exposed to the public Internet. The current
Kong configuration blocks the endpoint by default but only offers a commented-out
IP-allow-list mechanism that requires the service to be publicly reachable for
remote clients to connect.

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

The `/mcp` Kong route is restricted to localhost (`127.0.0.1`, `::1`) via the
`ip-restriction` plugin. This is configurable through `mcp_allowed_ips` so
operators can tighten or relax the allow list, but the **default is localhost
only**. The `/api/mcp` direct route stays fully blocked (request-termination
403) so the only reachable path is `/mcp` from the server itself.

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
| `mcp_allowed_ips` | `[127.0.0.1, ::1]` | IPs allowed to reach `/mcp` via Kong. Keep localhost-only for SSH-tunnel access. |

## Out of scope

- VPN setup (WireGuard/Tailscale) — documented as an alternative but not
  implemented as a role.
- OAuth/SSO protection for MCP — MCP is a server-to-server protocol; interactive
  OIDC login does not fit the client model.
- mTLS at the Kong layer — possible future enhancement, not required for the
  SSH-tunnel approach.
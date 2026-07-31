# Test Cases: Secure MCP Remote Access

## Overview

Verifies that the Supabase MCP endpoint is secured against public Internet
exposure while remaining reachable to authorized clients via SSH tunnel.

## Test Scenarios

### TC-MCP-001: Kong `/api/mcp` direct route is blocked

- **Given** the rendered `kong.yml`
- **When** a request targets `/api/mcp`
- **Then** the `mcp-blocker` service applies `request-termination` with
  `status_code: 403`
- **And** the response message is `Access is forbidden.`

### TC-MCP-002: Kong `/mcp` route is restricted to host-originated traffic by default

- **Given** the rendered `kong.yml` with no `mcp_allowed_ips` override
- **When** the template is rendered
- **Then** the `mcp` service has an `ip-restriction` plugin
- **And** the `allow` list contains the Docker bridge gateway `172.28.0.1`
  (Docker source-NATs host connections to the gateway; `127.0.0.1` is never seen)
- **And** there is **no** `request-termination` plugin on the `mcp` service

### TC-MCP-003: `mcp_allowed_ips` override is honored

- **Given** `env/supabase.yml` sets `mcp_allowed_ips: [10.0.0.5, 172.28.0.1]`
- **When** the template is rendered
- **Then** the `ip-restriction` `allow` list contains `10.0.0.5` and
  `172.28.0.1`

### TC-MCP-004: Default `mcp_allowed_ips` is the Docker bridge gateway

- **Given** `roles/supabase/defaults/main.yml`
- **When** the defaults are loaded
- **Then** `mcp_allowed_ips` equals `[172.28.0.1]` (matches the pinned compose subnet gateway)

### TC-MCP-005: Kong config YAML is syntactically valid

- **Given** the rendered `kong.yml` (default variables)
- **When** parsed as YAML
- **Then** parsing succeeds without errors

### TC-MCP-006: Kong config renders with custom allowed IPs

- **Given** `mcp_allowed_ips: [192.168.1.10, 10.0.0.0/24]`
- **When** the template is rendered
- **Then** the `ip-restriction` `allow` list contains both entries
- **And** the rendered YAML is syntactically valid

### TC-MCP-007: Ansible playbook syntax is valid

- **Given** `playbook-supabase.yml` and the role tasks
- **When** `ansible-playbook --syntax-check` runs
- **Then** it reports no syntax errors

### TC-MCP-008: Firewall denies Kong port by default

- **Given** the example `firewall_deny` in `env/supabase.yml`
- **When** the UFW role applies the deny rules
- **Then** port `8000` (Kong) is denied from external IPs
- **And** only SSH (port 22) is allowed for remote administration

### TC-MCP-009: Documentation describes SSH tunnel access

- **Given** `docs/advanced-docs.md`
- **When** a reader follows the "Secure MCP Remote Access" section
- **Then** the `ssh -L` command is documented
- **And** the MCP client URL pattern `http://localhost:<port>/mcp` is shown

### TC-MCP-010: MCP is not exposed via Caddy

- **Given** the example `projects` configuration in `env/supabase.yml`
- **When** the Caddyfile is rendered
- **Then** no upstream path includes `/mcp`
- **And** the MCP endpoint is only reachable through Kong on localhost
# Monitor Role
## What This Role Does

- Deploys **Grafana**, **Prometheus**, and **Loki** using Docker
- Configures Grafana datasources:
  - Prometheus (metrics)
  - Loki (logs)
- Installs and configures:
  - Node Exporter
  - cAdvisor
  - Postgres Exporter
  - Promtail
- Automatically provisions and includes several useful dashboards

## Authentication & Access

Grafana is **secured by default** using **GitHub OAuth**.

#### GitHub OAuth (Default)

Required variables:
- GitHub Client ID
- GitHub Client Secret
- Allowed GitHub organizations

Reference:  
https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/github/

#### Anonymous Access (Optional)

- Enabling it will allow everyone to access the dashboard 
- Role (Admin / Viewer) is configurable



## Configuration

All settings are configured via [env/supabase.yml](https://github.com/ankaboot-source/ansible-supabase/blob/main/env/supabase.yml#L9), update them accordingly.

# Ansible Supabase & Monitoring Stack

This repository provides an Ansible-based automation toolkit for deploying a self-hosted Supabase stack, Docker, a Caddy reverse proxy with [caddy-security](https://github.com/authcrunch/authcrunch.github.io) for OAuth2-protected access, and a full monitoring suite (Grafana, Prometheus, Loki, and exporters).
It is built for fast, repeatable, production-ready deployments on fresh Ubuntu servers.


---

<details open>
<summary><h2>🚀 Features</h2></summary>
  
### **Docker Role**
- Installs and configures Docker & Docker Compose.

### **Supabase Role**
- Deploys the entire Supabase ecosystem with Docker Compose.
- Generates all required configuration files (docker-compose.yml, kong.yml, .env) via Jinja2 templates.
- Allows templates customization to disable unused services or apply configuration changes dynamically.

### **Monitor Role**
A full observability solution including:

- **Grafana** (with auto-provisioned dashboards & datasources)
- **Prometheus**
- **Node Exporter**
- **cAdvisor**
- **Blackbox Exporter**
- **Postgres Exporter**
- **Loki** (logs)
- **Promtail**

Includes ready-made Grafana provisioning:
- Datasources  
- Dashboards  
- Monitoring docker-compose stack  

### **Caddy Role**
- Installs and configure Caddy reverse proxy + [caddy-security](https://github.com/authcrunch/authcrunch.github.io) module.
- Provides automatic TLS/HTTPS for Supabase and Grafana endpoints.
- Protects Supabase dashboard with OAuth2 Single Sign-On (SSO), with support for three provider options: GitHub, GitLab, and Discord.

---

</details>

<details open>
<summary><h2>🛠 Requirements</h2></summary>

- Ubuntu 20.04+
- 2 domain name records (recommended for reverse proxying Supabase and Grafana)
- Register Oauth2 application within one of our supported provider options:
  
  - GitHub
  - GitLab
  - Discord

---

</details>

<details open>
<summary><h2> 📥 Installation</h2></summary>

### **1. Clone the repository**
```bash
https://github.com/ankaboot-source/ansible-supabase.git
cd ansible-supabase
```
### **2. Configure environment variables**
Edit the main environment file:
>
> [env/supabase.yml](https://github.com/ankaboot-source/ansible-supabase/blob/main/env/supabase.yml)
>
### **3. Running the Playbooks**
Use the install script:
```bash
sudo bash install.sh -e supabase -p
```
Options:
- -e supabase → loads env/supabase.yml
- -p → prompts for SSH/sudo password

This executes all roles:
  - Docker
  - Caddy
  - Monitoring
  - Supabase

</details>

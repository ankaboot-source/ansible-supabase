# Ansible Supabase & Monitoring stack

This repository provides an Ansible-based automation toolkit for deploying a self-hosted Supabase stack, Docker, a Caddy reverse proxy with [caddy-security](https://github.com/authcrunch/authcrunch.github.io) for OAuth2-protected access, and a full monitoring suite (Grafana, Prometheus, Loki, and their agents).

It is built for fast, repeatable, production-ready deployments on fresh Debian-based servers.

## 📑 Table of Contents

- [🚀 Features](#-features)
  - [Docker Role](#docker-role)
  - [Supabase Role](#supabase-role)
  - [Monitor Role](#monitor-role)
  - [Caddy Role](#caddy-role)
- [🛠 Requirements](#-requirements)
- [📥 Installation](#--installation)
  - [1. Clone the repository](#1-clone-the-repository)
  - [2. Register OAuth2 Application](#2-register-oauth2-application)
  - [3. Caddy SSO and DNS configuration](#3-Caddy-SSO-and-DNS-configuration)
  - [4. Monitor role configuration](#4-Monitor-role-configuration)
  - [5. Configure environment variables](#5-configure-environment-variables) 
  - [6. Starting up the roles](#6-Starting-up-the-roles)
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

- **Grafana** (with provisioned dashboards & datasources)
- **Prometheus**
- **Node Exporter**
- **cAdvisor**
- **Postgres Exporter**
- **Loki** (logs)
- **Promtail**

### **Caddy Role**
- Installs and configure Caddy reverse proxy + [caddy-security](https://github.com/authcrunch/authcrunch.github.io) module.
- Provides automatic TLS/HTTPS for Supabase and Grafana endpoints.
- Protects Supabase dashboard with OAuth2 Single Sign-On (SSO), with support for three provider options: GitHub, GitLab, and Discord.

---

</details>
<details open>
<summary><h2>🛠 Requirements</h2></summary>

- Debian-based systems
- 3 subdomains records, one for authentication and two for reverse proxying Supabase and Grafana.
- Register Oauth2 application within one of the supported providers:

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
### **2. Register OAuth2 Application**


Below are the steps for each provider. After creating the app, you will receive:
- **Client ID**
- **Client Secret**

You will later place these values inside your `env/supabase.yml`.


#### **GitHub**
1. Go to: https://github.com/settings/developers
2. Click **"OAuth Apps" → "New OAuth app"**
3. Set Redirect URI : https://your-supabase-domain/auth/oauth2/github/authorization-code-callback
4. Set Home page URL : https://your-supabase-domain/project/default

#### **GitLab**
1. Go to: https://gitlab.com/-/profile/applications
2. Click **"Add new application"**
3. Set Redirect URI : https://your-supabase-domain/auth/oauth2/gitlab/authorization-code-callback
4. Enable openid, profile and email scopes

#### **Discord**
1. Go to: https://discord.com/developers/applications
2. Create a new application
3. Set Redirect URI : https://your-supabase-domain/auth/oauth2/discord/authorization-code-callback

#### **Sources:**
- GitHub : https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0007-github
- GitLab : https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0009-gitlab
- Discord : https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0013-discord
---

### **3. Caddy SSO and DNS configuration**

- Refer to [caddy/README.md](https://github.com/ankaboot-source/ansible-supabase/blob/main/roles/caddy/README.md).

### **4. Monitor role configuration**

- Refer to [monitor/README.md](https://github.com/ankaboot-source/ansible-supabase/blob/main/roles/monitor/README.md).

### **5. Configure environment variables**
All roles configurations are within the following file, make sure to update variables tagged with `#REQUIRED`
>
> [env/supabase.yml](https://github.com/ankaboot-source/ansible-supabase/blob/main/env/supabase.yml)
>

### **6. Starting up the roles**
Use the following script to install Ansible, Git and execute all roles:

```bash
sudo ./install.sh
```
</details>

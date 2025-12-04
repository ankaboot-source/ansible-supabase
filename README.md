# Ansible Supabase & Monitoring Stack

This repository provides an Ansible-based automation toolkit for deploying a self-hosted Supabase stack, Docker, a Caddy reverse proxy with [caddy-security](https://github.com/authcrunch/authcrunch.github.io) for OAuth2-protected access, and a full monitoring suite (Grafana, Prometheus, Loki, and exporters).

It is built for fast, repeatable, production-ready deployments on fresh Ubuntu servers.



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
  - [3. Configure environment variables](#3-configure-environment-variables)
  - [4. Running the Playbooks](#4-running-the-playbooks)


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
- 2 domain name records are required for reverse proxying Supabase and Grafana (Up to you to use 2 domain, 2 subdomains or mixed)
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
### **2. Register OAuth2 Application**

To protect the Supabase dashboard with OAuth2 SSO, you must create an OAuth2 application with **one** of the supported providers:

- **GitHub**
- **GitLab**
- **Discord**

Below are the steps for each provider. After creating the app, you will receive:
- **Client ID**
- **Client Secret**

You will later place these values inside your `env/supabase.yml`.


#### **GitHub OAuth App**
1. Go to: https://github.com/settings/developers  
2. Click **"OAuth Apps" → "New OAuth app"**
3. Set Redirect URI : https://your-supabase-domain/auth/oauth2/github/authorization-code-callback
4. Set Home page URL : https://your-supabase-domain/project/default

#### **GitLab OAuth App**
1. Go to: https://gitlab.com/-/profile/applications
2. Click **"Add new application"**
3. Set Redirect URI : https://your-supabase-domain/auth/oauth2/gitlab/authorization-code-callback
4. Enable openid, profile and email scopes

#### **Discord OAuth2**
1. Go to: https://discord.com/developers/applications  
2. Create a new application
3. Set Redirect URI : https://your-supabase-domain/auth/oauth2/discord/authorization-code-callback

---
**More Informations:**
- GitHub : https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0007-github
- GitLab : https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0009-gitlab
- Discord : https://docs.authcrunch.com/docs/authenticate/oauth/backend-oauth2-0013-discord
  
### **3. Configure environment variables**
Edit the main environment file:
>
> [env/supabase.yml](https://github.com/ankaboot-source/ansible-supabase/blob/main/env/supabase.yml)
>
### **4. Running the Playbooks**
Use the install script:
```bash
sudo ./install.sh
```
This will install Ansible, Git and executes all roles below:
  - Docker
  - Caddy
  - Monitoring
  - Supabase

</details>

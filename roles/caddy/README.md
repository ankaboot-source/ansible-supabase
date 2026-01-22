# Caddy SSO Reverse Proxy Setup

This role contains a **Caddy** configuration (templated with **Ansible**) that provides:

- OAuth (SSO) authentication for multiple providers.
- Role-based authorization
- Path-based reverse proxying
- Support for multiple projects
- Optional security per project

The setup is dynamic and allows you to easily add new projects with or without SSO protection.

## How to enable Oauth Protection
>❗**Important** All the following configurations are within [env/supabase.yml](https://github.com/ankaboot-source/ansible-supabase/blob/main/env/supabase.yml)

1. Set `SSO_PROVIDER` variable to your desired provider (GitLab, GitHub, Discord)

2. Configure the provider section after registring an Oauth app:
    <details>
    <summary><h5>GitLab</h5></summary>

    - gitlab_domain (e.g. gitlab.domain.com, gitlab.com )

    - gitlab_oauth_client_id

    - gitlab_oauth_secret

    - gitlab_allow_list → allowed GitLab users
    
    - gitlab_group_filters → allowed GitLab groups
    </details>
    <details>
    <summary><h5>GitHub</h5></summary>
    
    - github_oauth_client_id
    
    - github_oauth_client_secret
    
    - github_allow_list → allowed GitHub users
    </details>
    <details>
    <summary><h5>Discord</h5></summary>
 
    - discord_oauth_client_id

    - discord_oauth_client_secret

    - admin_role_id → Admin user ID

    - discord_guild_id → Discord server ID
    </details>

3. Set base_auth_domain and root_domain

    - **base_auth_domain** The domain used for authentication endpoints (e.g. auth.example.com).
    - **root_domain** The domain used for storing cookies (e.g. example.com).
> ℹ️ **Important** The root_domain must be set to the root level so that authentication cookies are accessible across all subdomains belonging to different projects.

4. Set `secure: true` in the project section.

## Project Configuration

Each project has its own settings:

- **project_subdomain**: Subdomain where the project (dashboard, UI, Api...) will be reverse proxied

- **backend**: Upstream service for API or specific paths

- **frontend**: Upstream service for the main UI / dashboard

- **paths**: List of path patterns to proxy to backend (usefull for supabase)

- **log_file**: File name for access logs

- **secure**: If true, SSO + authorization is enabled; if false, project is public (applies only on frontend, backend is not meant to be protected with OAuth)

If you need to use caddy as reverse proxy for other services, you just need to add another project in env/supabase.yml, and adjust it accordingly.

PS: if you want to only reverse proxy frontends, you can just keep `backend` variable **empty** in env/supabase.yml and make sure to set `paths: []` e.g.:

```yaml
  project_2:
    log_file: project 2-access
    domain: "www.domain2.org"
    backend:
    paths: []
    frontend: "localhost:5000"
    secure: true
```

-- agent_reader.sql — dedicated read-only PostgreSQL role for the supabase-agent
-- MCP server.
--
-- The MCP agent connects to the database as this role instead of the `postgres`
-- superuser, so the "read-only" boundary is ENFORCED BY THE DATABASE, not just
-- by the MCP server's own SQL filtering. This role can SELECT from every schema
-- Supabase manages, but can never INSERT/UPDATE/DELETE/DDL.
--
-- Provisioning runs as the `supabase_admin` superuser (see
-- roles/agent_access/tasks/main.yml) AFTER the supabase role has brought the DB
-- container up. It is idempotent: re-running on an existing deploy is a no-op.

-- 1. Create the role if it does not yet exist.
--    LOGIN so psql can connect as this user (the agent connects with `-U
--    agent_reader`). NOINHERIT + NOLOGIN are deliberately NOT used: LOGIN is
--    required for a direct connection, and we want the role to hold exactly the
--    privileges we grant it below.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'agent_reader') THEN
    CREATE ROLE agent_reader LOGIN;
    RAISE NOTICE 'created role agent_reader';
  ELSE
    RAISE NOTICE 'role agent_reader already exists — skipping creation';
  END IF;
END
$$;

-- 2. USAGE on every schema the agent should be able to read.
--    Without USAGE, the SELECT grants below are useless.
GRANT USAGE ON SCHEMA
  public,
  auth,
  storage,
  realtime,
  graphql,
  vault,
  _analytics,
  supabase_functions
  TO agent_reader;

-- 3. One-time catch-up: grant SELECT on all CURRENT tables in those schemas, so
--    tables that already exist (created before this role was provisioned) are
--    readable. This covers both Supabase's system schemas and any pre-existing
--    public tables.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA storage TO agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA realtime TO agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA graphql TO agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA vault TO agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA _analytics TO agent_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA supabase_functions TO agent_reader;

-- 4. Auto-cover EVERY FUTURE table via ALTER DEFAULT PRIVILEGES.
--    This is the key mechanism: any table created from now on (by an app
--    migration, manual DDL, or `migrate.sh` restore) is automatically granted
--    SELECT to agent_reader. No cron job or trigger is needed.
--
--    Default privileges are scoped per owning role, so we issue one FOR ROLE
--    clause per role that can create tables in each schema:
--      - postgres          -> owns `public` (normal app DDL via the postgres role)
--      - supabase_admin    -> superuser that OWNs auth/storage/graphql/vault and
--                             performs `migrate.sh` restores (safety: whichever
--                             owner emits restored tables, they are covered)
--      - supabase_auth_admin      -> owns `auth`
--      - supabase_storage_admin   -> owns `storage`
--      - supabase_realtime_admin  -> owns `realtime`
--      - supabase_functions_admin -> owns `supabase_functions`
--    Running as the `supabase_admin` superuser permits setting default
--    privileges on behalf of all these roles.

-- postgres (public — normal application DDL)
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES TO agent_reader;

-- supabase_admin (public RESTORE via migrate.sh; plus system schemas it owns)
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT SELECT ON TABLES TO agent_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT SELECT ON TABLES TO agent_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA vault GRANT SELECT ON TABLES TO agent_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA _analytics GRANT SELECT ON TABLES TO agent_reader;

-- Supabase service roles (their own schemas)
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT SELECT ON TABLES TO agent_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_storage_admin IN SCHEMA storage GRANT SELECT ON TABLES TO agent_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_realtime_admin IN SCHEMA realtime GRANT SELECT ON TABLES TO agent_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_functions_admin IN SCHEMA supabase_functions GRANT SELECT ON TABLES TO agent_reader;
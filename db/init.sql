-- Initialize database users and roles

-- Create admin role if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_admin') THEN
        CREATE ROLE app_admin WITH LOGIN PASSWORD 'admin_password';
    END IF;
END
$$;

-- Grant necessary permissions to the admin role
ALTER ROLE app_admin WITH SUPERUSER;

-- Create application role if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user WITH LOGIN PASSWORD 'app_password';
    END IF;
END
$$;

-- Create extension for secure password storage
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Set timezone to UTC
SET timezone = 'UTC';

-- Comments for documentation
COMMENT ON ROLE app_admin IS 'Administrative role for managing app database';
COMMENT ON ROLE app_user IS 'Application role for normal database operations';
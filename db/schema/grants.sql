SET client_encoding = 'UTF8';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector;
    END IF;
END $$;

ALTER ROLE inspector LOGIN PASSWORD 'NetoSQL2025';

GRANT ALL ON SCHEMA khorunzhii_food TO inspector;
GRANT ALL ON ALL TABLES IN SCHEMA khorunzhii_food TO inspector;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA khorunzhii_food TO inspector;

GRANT USAGE ON SCHEMA exts TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA exts TO inspector;

GRANT USAGE ON SCHEMA information_schema, pg_catalog TO inspector;

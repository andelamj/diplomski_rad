-- Read-only korisnik za Power BI
CREATE USER powerbi_user WITH PASSWORD 'UPISI_LOZINKU';
GRANT CONNECT ON DATABASE film_dw TO powerbi_user;
GRANT USAGE ON SCHEMA dw TO powerbi_user;
GRANT SELECT ON ALL TABLES IN SCHEMA dw TO powerbi_user;

-- Prava powerbi_usera
SELECT table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'powerbi_user'
ORDER BY table_schema, table_name;

-- Prava powerbi_usera
SELECT table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'postgres'
ORDER BY table_schema, table_name;

-- Preuzmi ulogu powerbi_usera
SET ROLE post;

-- Pokušaj INSERT - treba baciti grešku
INSERT INTO dw.dim_zanr (zanr_id, naziv) VALUES (9999, 'Test');

SELECT *
FROM pg_user;

GRANT SELECT ON ALL TABLES IN SCHEMA dw TO powerbi_user;

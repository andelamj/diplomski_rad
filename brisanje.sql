TRUNCATE film, osoba, uspjesnost_filmova, zanr, film_zanr, trziste RESTART IDENTITY CASCADE;
TRUNCATE dw.fact_uspjesnost_filmova, dw.bridge_film_osoba, dw.bridge_film_zanr, dw.dim_film, dw.dim_osoba, dw.dim_zanr, dw.dim_trziste RESTART IDENTITY CASCADE;
DELETE FROM etl_log WHERE naziv_procesa = 'etl_film_to_staging';
INSERT INTO etl_log (naziv_procesa, zadnji_run) VALUES ('etl_film_to_staging', '1900-01-01');
DELETE FROM etl_log WHERE naziv_procesa = 'tmdb_zadnja_stranica';

DROP TABLE IF EXISTS dw.fact_uspjesnost_filmova_2024;
DROP TABLE IF EXISTS dw.fact_uspjesnost_filmova_2025;
DROP TABLE IF EXISTS dw.fact_uspjesnost_filmova_2026;

TRUNCATE staging.stg_film,
         staging.stg_zanr,
         staging.stg_film_zanr,
         staging.stg_osoba,
         staging.stg_film_osoba,
         staging.stg_trziste,
         staging.stg_uspjesnost_filmova;
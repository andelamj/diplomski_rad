--relacijska tablica
select * from public.film
where film_id=2

--staging
select * from staging.stg_film
where film_id=2

--scd2
select * from dw.dim_film
where film_id=2

--skladiste podataka
select * from dw.fact_uspjesnost_filmova
where film_key=3179

--etl_log 
select * from public.etl_log

--explain analyze
EXPLAIN ANALYZE
SELECT *
FROM dw.fact_uspjesnost_filmova
WHERE datum_unosa >= CURRENT_DATE - INTERVAL '7 days';

-- Preuzmi ulogu powerbi_usera
SET ROLE post;

-- Pokušaj INSERT - treba baciti grešku
INSERT INTO dw.dim_zanr (zanr_id, naziv) VALUES (9999, 'Test');


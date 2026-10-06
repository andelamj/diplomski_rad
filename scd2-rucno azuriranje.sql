-- =====================================================
-- 1. STANJE PRIJE: izvorna baza i skladište
-- =====================================================
SELECT film_id, naziv, json_meta->>'ocjena' AS ocjena, updated_at
FROM film
WHERE film_id = 100;

SELECT film_key, film_id, naziv, json_meta->>'ocjena' AS ocjena,
       valid_from, valid_to, is_current
FROM dw.dim_film
WHERE film_id = 100
ORDER BY film_key;


-- =====================================================
-- 2. PROMJENA U IZVORNOJ BAZI (simulacija nove ocjene)
-- =====================================================
UPDATE film
SET json_meta = jsonb_set(json_meta, '{ocjena}', '9.1')
WHERE film_id = 100;

-- provjera: ocjena je promijenjena, a okidač je ažurirao updated_at
SELECT film_id, naziv, json_meta->>'ocjena' AS ocjena, updated_at
FROM film
WHERE film_id = 100;


-- =====================================================
-- 3. POKRENI ETL
-- =====================================================
-- U pgAdminu: File → Open → 04_etl.sql, pa F5.
-- Ili u psql-u:
-- \i 'C:/Users/Korisnik/Desktop/diplomski/ETL/04_etl.sql'


-- =====================================================
-- 4. STANJE POSLIJE: dvije verzije istog filma
-- =====================================================
SELECT film_key, film_id, naziv, json_meta->>'ocjena' AS ocjena,
       valid_from, valid_to, is_current
FROM dw.dim_film
WHERE film_id = 100
ORDER BY film_key;


-- =====================================================
-- 5. ETL ZAPISNIK
-- =====================================================
SELECT etl_log_id, naziv_procesa, zadnji_run, status, broj_redaka
FROM etl_log
ORDER BY etl_log_id DESC
LIMIT 3;
-- filmove u bazi
SELECT film_id, naziv, datum_izlaska, prod_kuca,
       json_meta->>'ocjena' AS ocjena,
       json_meta->>'tmdb_id' AS tmdb_id
FROM film
ORDER BY created_at DESC;


-- SCD2 radi (povijest promjena filma)

UPDATE film 
SET json_meta = jsonb_set(json_meta, '{ocjena}', '9.9')
WHERE film_id = 1;

SELECT film_id, naziv, valid_from, valid_to, is_current
FROM dw.dim_film
WHERE film_id = 1
ORDER BY valid_from;

SELECT DISTINCT f.film_key
FROM dw.fact_uspjesnost_filmova f
JOIN dw.dim_film df ON df.film_key = f.film_key
WHERE df.film_id = 1;

-- Top filmovi po prihodu
SELECT * FROM dw.v_top_filmovi LIMIT 10;

-- Prihod po žanru
SELECT * FROM dw.v_prihod_po_zanru ORDER BY ukupni_prihod DESC;

-- Prihod po tržištu
SELECT trziste, drzava, SUM(ukupni_prihod) AS ukupno
FROM dw.v_prihod_po_trzisstu
GROUP BY trziste, drzava
ORDER BY ukupno DESC;

-- Prava powerbi_usera
SELECT table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'powerbi_user'
AND table_schema = 'dw';

-- postavimo usera: powerbi_usera
SET ROLE powerbi_user;

--INSERT 
INSERT INTO dw.dim_zanr (zanr_id, naziv) VALUES (9999, 'Test');

-- Svi indeksi u public shemi
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename;

-- Svi indeksi u dw shemi
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'dw'
ORDER BY tablename;

-- Svi indeksi u dw shemi
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE tablename= 'film';

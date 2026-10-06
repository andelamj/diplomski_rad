-- ============================================================
-- 04_etl.sql
-- ETL proces — inkrementalno punjenje staging -> DW
-- ============================================================

-- ===========================================================
-- KORAK 1: Očisti staging
-- ===========================================================
TRUNCATE staging.stg_film,
         staging.stg_zanr,
         staging.stg_film_zanr,
         staging.stg_osoba,
         staging.stg_film_osoba,
         staging.stg_trziste,
         staging.stg_uspjesnost_filmova;

-- ===========================================================
-- KORAK 2 + 3: Punjenje staginga (novi i azurirani zapisi)
-- ===========================================================
DO $$
DECLARE
    v_last_run TIMESTAMP;
BEGIN
    SELECT zadnji_run INTO v_last_run
    FROM etl_log
    WHERE naziv_procesa = 'etl_film_to_staging'
    ORDER BY etl_log_id DESC
    LIMIT 1;

    INSERT INTO staging.stg_film
    SELECT film_id, naziv, datum_izlaska, trajanje_min,
           prod_kuca, json_meta, created_at
    FROM film
    WHERE created_at > v_last_run
       OR updated_at > v_last_run;

    INSERT INTO staging.stg_zanr
    SELECT DISTINCT z.zanr_id, z.naziv, z.created_at
    FROM zanr z
    JOIN film_zanr fz ON fz.zanr_id = z.zanr_id
    JOIN staging.stg_film sf ON sf.film_id = fz.film_id;

    INSERT INTO staging.stg_film_zanr
    SELECT fz.film_id, fz.zanr_id
    FROM film_zanr fz
    JOIN staging.stg_film sf ON sf.film_id = fz.film_id;

    INSERT INTO staging.stg_osoba
    SELECT DISTINCT o.osoba_id, o.tmdb_person_id, o.ime, o.prezime, o.created_at
    FROM osoba o
    JOIN film_osoba fo ON fo.osoba_id = o.osoba_id
    JOIN staging.stg_film sf ON sf.film_id = fo.film_id;

    INSERT INTO staging.stg_film_osoba
    SELECT fo.film_id, fo.osoba_id, fo.uloga
    FROM film_osoba fo
    JOIN staging.stg_film sf ON sf.film_id = fo.film_id;

    INSERT INTO staging.stg_trziste
    SELECT DISTINCT t.trziste_id, t.naziv, t.drzava, t.created_at
    FROM trziste t
    JOIN uspjesnost_filmova uf ON uf.trziste_id = t.trziste_id
    WHERE uf.created_at >= v_last_run;

    INSERT INTO staging.stg_uspjesnost_filmova
    SELECT uspjesnost_filmova_id, film_id, trziste_id,
           datum, prihod, br_gledatelja, created_at
    FROM uspjesnost_filmova
    WHERE created_at >= v_last_run;

END $$;

-- ===========================================================
-- KORAK 4: Load u DW dimenzije
-- ===========================================================

-- Dummy osoba za filmove bez glumca
INSERT INTO dw.dim_osoba (osoba_id, ime, prezime)
OVERRIDING SYSTEM VALUE
VALUES (0, 'Nepoznat', 'Glumac')
ON CONFLICT (osoba_id) DO NOTHING;

-- dim_zanr (Type 1)
INSERT INTO dw.dim_zanr (zanr_id, naziv)
SELECT zanr_id, naziv FROM staging.stg_zanr
ON CONFLICT (zanr_id) DO UPDATE
    SET naziv = EXCLUDED.naziv;

-- dim_osoba (Type 1)
INSERT INTO dw.dim_osoba (osoba_id, ime, prezime)
SELECT osoba_id, ime, prezime FROM staging.stg_osoba
ON CONFLICT (osoba_id) DO UPDATE
    SET ime     = EXCLUDED.ime,
        prezime = EXCLUDED.prezime;

-- dim_trziste (Type 1)
INSERT INTO dw.dim_trziste (trziste_id, naziv, drzava)
SELECT trziste_id, naziv, drzava FROM staging.stg_trziste
ON CONFLICT (trziste_id) DO UPDATE
    SET naziv  = EXCLUDED.naziv,
        drzava = EXCLUDED.drzava;

-- dim_film (SCD2)
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM staging.stg_film LOOP

        UPDATE dw.dim_film
        SET    is_current = FALSE,
               valid_to   = CURRENT_DATE - 1
        WHERE  film_id    = rec.film_id
          AND  is_current = TRUE
          AND  json_meta IS DISTINCT FROM rec.json_meta;

        INSERT INTO dw.dim_film (
            film_id, naziv, datum_izlaska, trajanje_min,
            prod_kuca, json_meta, valid_from, valid_to, is_current
        )
        SELECT
            rec.film_id, rec.naziv, rec.datum_izlaska, rec.trajanje_min,
            rec.prod_kuca, rec.json_meta,
            CURRENT_DATE, '9999-12-31', TRUE
        WHERE NOT EXISTS (
            SELECT 1 FROM dw.dim_film
            WHERE film_id    = rec.film_id
              AND is_current = TRUE
              AND json_meta  = rec.json_meta
        );
    END LOOP;
END $$;

-- ===========================================================
-- KORAK 5: Kreiraj particiju za godinu datum_unosa
-- ===========================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT DISTINCT created_at::DATE AS datum_unosa
        FROM uspjesnost_filmova
        WHERE created_at IS NOT NULL
    LOOP
        PERFORM dw.kreiraj_particiju_ako_ne_postoji(r.datum_unosa);
    END LOOP;
END $$;

-- ===========================================================
-- KORAK 6: Load u fact_uspjesnost_filmova
-- (bez osoba_key/zanr_key -- ta veza sada ide preko bridge
--  tablica, vidi KORAK 6b, jer je jedan film moze imati vise
--  glumaca/zanrova, a LIMIT 1 je gubio podatke)
-- ===========================================================
INSERT INTO dw.fact_uspjesnost_filmova (
    film_key, trziste_key, vrijeme_key,
    prihod, br_gledatelja, datum_unosa, datum_izlaska
)
SELECT
    df.film_key,
    dt.trziste_key,
    dv.vrijeme_key,
    sbo.prihod,
    sbo.br_gledatelja,
    sbo.created_at::DATE,
    df.datum_izlaska
FROM staging.stg_uspjesnost_filmova sbo
JOIN dw.dim_film df ON df.film_id = sbo.film_id AND df.is_current = TRUE
JOIN dw.dim_trziste dt ON dt.trziste_id = sbo.trziste_id
LEFT JOIN dw.dim_vrijeme dv ON dv.datum =
    CASE WHEN sbo.datum >= '2000-01-01' THEN sbo.datum ELSE NULL END
WHERE NOT EXISTS (
    SELECT 1 FROM dw.fact_uspjesnost_filmova f
    JOIN dw.dim_film d ON d.film_key = f.film_key
    WHERE d.film_id     = df.film_id
      AND f.trziste_key = dt.trziste_key
      AND f.datum_unosa = sbo.created_at::DATE
);

-- ===========================================================
-- KORAK 6b: Load u bridge tablice (film <-> osoba, film <-> zanr)
-- Puni SVE osobe/zanrove po filmu iz staginga, ne samo prvi
-- pronadjeni -- ovime se rjesava LIMIT 1 problem.
-- ===========================================================
INSERT INTO dw.bridge_film_osoba (film_key, osoba_key, uloga)
SELECT DISTINCT
    df.film_key,
    dop.osoba_key,
    sfo.uloga
FROM staging.stg_film_osoba sfo
JOIN dw.dim_film  df  ON df.film_id = sfo.film_id AND df.is_current = TRUE
JOIN dw.dim_osoba dop ON dop.osoba_id = sfo.osoba_id
ON CONFLICT DO NOTHING;

INSERT INTO dw.bridge_film_zanr (film_key, zanr_key)
SELECT DISTINCT
    df.film_key,
    dz.zanr_key
FROM staging.stg_film_zanr sfz
JOIN dw.dim_film df ON df.film_id = sfz.film_id AND df.is_current = TRUE
JOIN dw.dim_zanr dz ON dz.zanr_id = sfz.zanr_id
ON CONFLICT DO NOTHING;

-- ===========================================================
-- KORAK 7: Ažuriraj ETL log
-- ===========================================================
INSERT INTO etl_log (naziv_procesa, zadnji_run, status, broj_redaka)
VALUES (
    'etl_film_to_staging',
    NOW(),
    'success',
    (SELECT COUNT(*) FROM staging.stg_film)
);

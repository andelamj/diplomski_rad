-- ============================================================
-- Top filmovi po prihodu
-- ============================================================
CREATE OR REPLACE VIEW dw.v_top_filmovi AS
SELECT df_current.naziv AS film,
    df_current.datum_izlaska,
    df_current.prod_kuca,
    dv.mjesec,
    dv.godina,
    sum(f.prihod) AS ukupni_prihod,
    sum(f.br_gledatelja) AS ukupno_gledatelja
FROM dw.fact_uspjesnost_filmova f
JOIN dw.dim_film df ON df.film_key = f.film_key
JOIN dw.dim_film df_current ON df_current.film_id = df.film_id AND df_current.is_current = true
LEFT JOIN dw.dim_vrijeme dv ON dv.datum = df_current.datum_izlaska
GROUP BY df_current.film_id, df_current.naziv, df_current.datum_izlaska, df_current.prod_kuca, dv.mjesec, dv.godina
ORDER BY (sum(f.prihod)) DESC;
-- ============================================================
-- Top glumci po gledanosti
-- ============================================================
CREATE OR REPLACE VIEW dw.v_top_glumci_filma AS
SELECT o.osoba_key,
    o.osoba_id,
    o.ime,
    o.prezime,
    fact.trziste_key,
    sum(fact.br_gledatelja) AS ukupno_gledatelja,
    sum(fact.prihod) AS ukupni_prihod,
    count(DISTINCT fact.film_key) AS broj_filmova
FROM dw.fact_uspjesnost_filmova fact
JOIN dw.bridge_film_osoba b ON b.film_key = fact.film_key
JOIN dw.dim_osoba o ON o.osoba_key = b.osoba_key
WHERE b.uloga = 'glumac'
GROUP BY o.osoba_key, o.osoba_id, o.ime, o.prezime, fact.trziste_key;

-- ============================================================
-- Zanrovi: profitabilnost po filmu vs gledanost (scatter)
-- ============================================================
CREATE OR REPLACE VIEW dw.v_zanr_scatter AS
SELECT z.naziv AS zanr,
    round(sum(fact.prihod) / NULLIF(count(DISTINCT fact.film_key), 0)::numeric, 2) AS prosjek_prihod_po_filmu,
    sum(fact.br_gledatelja) AS ukupno_gledatelja,
    count(DISTINCT fact.film_key) AS broj_filmova
FROM dw.fact_uspjesnost_filmova fact
JOIN dw.bridge_film_zanr b ON b.film_key = fact.film_key
JOIN dw.dim_zanr z ON z.zanr_key = b.zanr_key
GROUP BY z.naziv;

-- ============================================================
-- Prihod po tržištu
-- ============================================================
CREATE OR REPLACE VIEW dw.v_prihod_po_trzistu AS
SELECT dt.naziv AS trziste,
    dt.drzava,
    dv.godina,
    dv.mjesec,
    sum(f.prihod) AS ukupni_prihod,
    sum(f.br_gledatelja) AS ukupno_gledatelja
FROM dw.fact_uspjesnost_filmova f
JOIN dw.dim_trziste dt ON dt.trziste_key = f.trziste_key
JOIN dw.dim_vrijeme dv ON dv.vrijeme_key = f.vrijeme_key
GROUP BY dt.naziv, dt.drzava, dv.godina, dv.mjesec;
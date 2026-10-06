-- ============================================================
-- 03_data_warehouse.sql
-- Data Warehouse — dimenzije i fakt tablica (star schema)
-- ============================================================

CREATE SCHEMA IF NOT EXISTS dw;

-- -----------------------------------------------------------
-- dim_film  (SCD2 — pamti povijest promjena)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_film (
    film_key        SERIAL PRIMARY KEY,
    film_id         INT           NOT NULL,  
    naziv           VARCHAR(255)  NOT NULL,
    datum_izlaska   DATE,
    trajanje_min    INT,
    prod_kuca       VARCHAR(255),
    json_meta       JSONB,
    -- SCD2 stupci
    valid_from      DATE          NOT NULL,
    valid_to        DATE          NOT NULL DEFAULT '9999-12-31',
    is_current      BOOLEAN       NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_dim_film_id
    ON dw.dim_film(film_id);
CREATE INDEX IF NOT EXISTS idx_dim_film_current
    ON dw.dim_film(film_id, is_current);

-- -----------------------------------------------------------
-- dim_osoba  (Type 1)
-- Napomena: "uloga" je uklonjena odavde jer je svojstvo VEZE
-- osoba<->film (ista osoba moze biti glumac u jednom filmu, a
-- redatelj u drugom) -- ta veza se sada ispravno modelira u
-- bridge_film_osoba.uloga, a ne kao atribut osobe.
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_osoba (
    osoba_key   SERIAL PRIMARY KEY,
    osoba_id    INT          NOT NULL UNIQUE,
    ime         VARCHAR(100) NOT NULL,
    prezime     VARCHAR(100) NOT NULL
);

-- -----------------------------------------------------------
-- dim_zanr  (Type 1)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_zanr (
    zanr_key    SERIAL PRIMARY KEY,
    zanr_id     INT          NOT NULL UNIQUE,
    naziv       VARCHAR(100) NOT NULL
);

-- -----------------------------------------------------------
-- dim_trziste  (Type 1)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_trziste (
    trziste_key SERIAL PRIMARY KEY,
    trziste_id  INT          NOT NULL UNIQUE,
    naziv       VARCHAR(150) NOT NULL,
    drzava      VARCHAR(100) NOT NULL
);

-- -----------------------------------------------------------
-- dim_vrijeme  (Type 1 — unaprijed popunjena)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_vrijeme (
    vrijeme_key SERIAL PRIMARY KEY,
    datum       DATE    NOT NULL UNIQUE,
    dan         INT     NOT NULL,   
    dan_tjedna  INT     NOT NULL,  
    tjedan      INT     NOT NULL,   
    mjesec      INT     NOT NULL,
    naziv_mj    VARCHAR(20) NOT NULL,
    kvartal     INT     NOT NULL,
    godina      INT     NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_dim_vrijeme_datum
    ON dw.dim_vrijeme(datum);

-- Punjenje dim_vrijeme za 2000–2030
INSERT INTO dw.dim_vrijeme (
    datum, dan, dan_tjedna, tjedan,
    mjesec, naziv_mj, kvartal, godina
)
SELECT
    d::DATE,
    EXTRACT(DAY   FROM d)::INT,
    EXTRACT(ISODOW FROM d)::INT,
    EXTRACT(WEEK  FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    TO_CHAR(d, 'Month'),
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(YEAR  FROM d)::INT
FROM generate_series(
    '2000-01-01'::DATE,
    '2030-12-31'::DATE,
    '1 day'::INTERVAL
) AS t(d)
ON CONFLICT (datum) DO NOTHING;

-- -----------------------------------------------------------
-- fact_uspjesnost_filmova
-- Napomena: bez osoba_key/zanr_key -- ta veza ide preko bridge
-- tablica (vidi nize), jer jedan film moze imati vise
-- glumaca/zanrova (M:N), a direktni FK u fact tablici bi to
-- prisiljavao na 1:1 i gubio podatke.
-- -----------------------------------------------------------
CREATE TABLE dw.fact_uspjesnost_filmova (
    fact_key        SERIAL,
    film_key        INT           NOT NULL REFERENCES dw.dim_film(film_key),
    trziste_key     INT           NOT NULL REFERENCES dw.dim_trziste(trziste_key),
    vrijeme_key     INT           REFERENCES dw.dim_vrijeme(vrijeme_key),
    prihod          NUMERIC(15,2) NOT NULL DEFAULT 0,
    br_gledatelja   INT           NOT NULL DEFAULT 0,
	datum_izlaska   DATE NOT NULL,
    datum_unosa     DATE          NOT NULL DEFAULT CURRENT_DATE
) PARTITION BY RANGE (datum_unosa);



CREATE INDEX IF NOT EXISTS idx_fact_film      ON dw.fact_uspjesnost_filmova(film_key);
CREATE INDEX IF NOT EXISTS idx_fact_trziste   ON dw.fact_uspjesnost_filmova(trziste_key);
CREATE INDEX IF NOT EXISTS idx_fact_vrijeme   ON dw.fact_uspjesnost_filmova(vrijeme_key);
CREATE INDEX IF NOT EXISTS idx_fact_unosa     ON dw.fact_uspjesnost_filmova(datum_unosa);
CREATE INDEX IF NOT EXISTS idx_fact_izlaska ON dw.fact_uspjesnost_filmova(datum_izlaska);

-- -----------------------------------------------------------
-- bridge_film_osoba / bridge_film_zanr
-- Rjesavaju M:N vezu film <-> osoba i film <-> zanr (jedan
-- film moze imati vise glumaca/redatelja/scenarista/producenata
-- i vise zanrova; fact tablica vise ne prisiljava na 1:1)
-- -----------------------------------------------------------
CREATE TABLE dw.bridge_film_osoba (
    film_key   INT NOT NULL REFERENCES dw.dim_film(film_key),
    osoba_key  INT NOT NULL REFERENCES dw.dim_osoba(osoba_key),
    uloga      VARCHAR(20) NOT NULL
        CHECK (uloga IN ('glumac', 'redatelj', 'scenarist', 'producent')),
    PRIMARY KEY (film_key, osoba_key, uloga)
);

CREATE TABLE dw.bridge_film_zanr (
    film_key   INT NOT NULL REFERENCES dw.dim_film(film_key),
    zanr_key   INT NOT NULL REFERENCES dw.dim_zanr(zanr_key),
    PRIMARY KEY (film_key, zanr_key)
);

CREATE INDEX IF NOT EXISTS idx_bridge_film_osoba_film  ON dw.bridge_film_osoba(film_key);
CREATE INDEX IF NOT EXISTS idx_bridge_film_osoba_osoba ON dw.bridge_film_osoba(osoba_key);
CREATE INDEX IF NOT EXISTS idx_bridge_film_zanr_film   ON dw.bridge_film_zanr(film_key);
CREATE INDEX IF NOT EXISTS idx_bridge_film_zanr_zanr   ON dw.bridge_film_zanr(zanr_key);
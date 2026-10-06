-- ============================================================
-- 02_staging.sql
-- Staging sloj — privremene tablice, brišu se nakon loada
-- ============================================================

CREATE SCHEMA IF NOT EXISTS staging;

-- -----------------------------------------------------------
-- stg_film
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.stg_film (
    film_id         INT,
    naziv           VARCHAR(255),
    datum_izlaska   DATE,
    trajanje_min    INT,
    prod_kuca       VARCHAR(255),
    json_meta       JSONB,
    created_at      TIMESTAMP,
    updated_at      TIMESTAMP
);

-- -----------------------------------------------------------
-- stg_zanr
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.stg_zanr (
    zanr_id     INT,
    naziv       VARCHAR(100),
    created_at  TIMESTAMP
);

-- -----------------------------------------------------------
-- stg_film_zanr
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.stg_film_zanr (
    film_id     INT,
    zanr_id     INT
);

-- -----------------------------------------------------------
-- stg_osoba
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS staging.stg_osoba (
    osoba_id        INT,
    tmdb_person_id  INT,
    ime             VARCHAR(100),
    prezime         VARCHAR(100),
    created_at      TIMESTAMP
);

-- -----------------------------------------------------------
-- stg_film_osoba
-- -----------------------------------------------

CREATE TABLE IF NOT EXISTS staging.stg_film_osoba (
    film_id     INT,
    osoba_id    INT,
    uloga       VARCHAR(50)
);

-- -----------------------------------------------------------
-- stg_trziste
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.stg_trziste (
    trziste_id  INT,
    naziv       VARCHAR(150),
    drzava      VARCHAR(100),
    created_at  TIMESTAMP
);

-- -----------------------------------------------------------
-- stg_uspjesnost_filmova
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.stg_uspjesnost_filmova (
    uspjesnost_filmova_id INT,
    film_id         INT,
    trziste_id      INT,
    datum           DATE,
    prihod          NUMERIC(15,2),
    br_gledatelja   INT,
    created_at      TIMESTAMP
);
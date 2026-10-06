-- ============================================================
-- 01_relacijska_baza.sql
-- Source layer — relacijska baza (public shema)
-- ============================================================

-- -----------------------------------------------------------
-- zanr
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS zanr (
    zanr_id     SERIAL PRIMARY KEY,
    naziv       VARCHAR(100) NOT NULL UNIQUE,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------
-- film
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS film (
    film_id         SERIAL PRIMARY KEY,
    naziv           VARCHAR(255) NOT NULL,
    datum_izlaska   DATE,
    trajanje_min    INT,
    prod_kuca       VARCHAR(255),
    json_meta       JSONB,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Trigger za automatsko azuriranje updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_film_updated_at
BEFORE UPDATE ON film
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

-- -----------------------------------------------------------
-- film_zanr  (N:M)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS film_zanr (
    film_id     INT NOT NULL REFERENCES film(film_id),
    zanr_id     INT NOT NULL REFERENCES zanr(zanr_id),
    PRIMARY KEY (film_id, zanr_id)
);

-- -----------------------------------------------------------
-- osoba
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS osoba (
    osoba_id        SERIAL PRIMARY KEY,
    tmdb_person_id  INT UNIQUE,
    ime             VARCHAR(100) NOT NULL,
    prezime         VARCHAR(100) NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);


-- -----------------------------------------------------------
-- film_osoba  (N:M bridge -- film <-> osoba, s ulogom kao
-- svojstvom same veze, ne osobe)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS film_osoba (
    film_id     INT NOT NULL REFERENCES film(film_id),
    osoba_id    INT NOT NULL REFERENCES osoba(osoba_id),
    uloga       VARCHAR(50) NOT NULL
                CHECK (uloga IN ('glumac', 'redatelj', 'scenarist', 'producent')),
    PRIMARY KEY (film_id, osoba_id, uloga)
);

CREATE INDEX IF NOT EXISTS idx_film_osoba_film  ON film_osoba(film_id);
CREATE INDEX IF NOT EXISTS idx_film_osoba_osoba ON film_osoba(osoba_id);

-- -----------------------------------------------------------
-- trziste
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS trziste (
    trziste_id  SERIAL PRIMARY KEY,
    naziv       VARCHAR(150) NOT NULL UNIQUE,
    drzava      VARCHAR(100) NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------
-- uspjesnost_filmova
-- -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS uspjesnost_filmova (
    uspjesnost_filmova_id   SERIAL PRIMARY KEY,
    film_id         INT  NOT NULL REFERENCES film(film_id),
    trziste_id      INT  NOT NULL REFERENCES trziste(trziste_id),
    datum           DATE NOT NULL,
    prihod          NUMERIC(15,2) NOT NULL DEFAULT 0,
    br_gledatelja   INT           NOT NULL DEFAULT 0,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------
-- Indeksi za ubrzanje ETL upita
-- -----------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_film_created
    ON film(created_at);

CREATE INDEX IF NOT EXISTS idx_film_updated
    ON film(updated_at);

CREATE INDEX IF NOT EXISTS idx_osoba_created
    ON osoba(created_at);

CREATE INDEX IF NOT EXISTS idx_box_office_created
    ON uspjesnost_filmova(created_at);

CREATE INDEX IF NOT EXISTS idx_uspjesnost_filmova_film
    ON uspjesnost_filmova(film_id);

-- -----------------------------------------------------------
-- ETL kontrolna tablica (pamti zadnji uspješni run)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS etl_log (
    etl_log_id      SERIAL PRIMARY KEY,
    naziv_procesa   VARCHAR(100) NOT NULL,
    zadnji_run      TIMESTAMP    NOT NULL DEFAULT '1900-01-01',
    status          VARCHAR(20)  NOT NULL DEFAULT 'success',
    broj_redaka     INT,
    poruka          TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO etl_log (naziv_procesa, zadnji_run)
VALUES ('etl_film_to_staging', '1900-01-01');
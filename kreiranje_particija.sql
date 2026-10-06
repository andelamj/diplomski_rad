CREATE OR REPLACE FUNCTION dw.kreiraj_particiju_ako_ne_postoji(p_datum DATE)
RETURNS VOID AS $$
DECLARE
    v_naziv     TEXT;
    v_od        DATE;
    v_do        DATE;
BEGIN
    -- Ime particije po godini
    v_naziv := 'fact_uspjesnost_filmova_' || TO_CHAR(p_datum, 'YYYY');
    v_od    := DATE_TRUNC('year', p_datum)::DATE;
    v_do    := (DATE_TRUNC('year', p_datum) + INTERVAL '1 year')::DATE;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'dw'
          AND c.relname = v_naziv
    ) THEN
        EXECUTE format(
            'CREATE TABLE dw.%I PARTITION OF dw.fact_uspjesnost_filmova
             FOR VALUES FROM (%L) TO (%L)',
            v_naziv, v_od, v_do
        );
    END IF;
END;
$$ LANGUAGE plpgsql;
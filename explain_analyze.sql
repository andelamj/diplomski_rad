EXPLAIN ANALYZE
SELECT *
FROM dw.fact_uspjesnost_filmova
WHERE datum_unosa >= CURRENT_DATE - INTERVAL '7 days';
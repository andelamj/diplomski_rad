-- 1. fact tablica
DELETE FROM dw.fact_uspjesnost_filmova
WHERE film_key IN (SELECT film_key FROM dw.dim_film WHERE film_id =2964 );

-- 2. dim_film
DELETE FROM dw.dim_film WHERE film_id = 2964;

-- 3. relacijska baza
DELETE FROM uspjesnost_filmova WHERE film_id = 2964;
DELETE FROM film_zanr WHERE film_id = 2964;
DELETE FROM osoba WHERE film_id = 2964;
DELETE FROM film WHERE film_id = 2964;
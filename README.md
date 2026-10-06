# Skladište podataka za analizu uspješnosti filmova

Diplomski rad: Projektiranje i implementacija skladišta podataka za analizu uspješnosti filmova uz primjenu sustava PostgreSQL i programa Power BI Desktop.

Podaci o filmovima preuzimaju se s platforme TMDB (The Movie Database), a podaci o prihodima i broju gledatelja po tržištima simulirani su za potrebe analize. Izvještaji u Power BI-ju omogućuju analizu uspješnosti filmova prema prihodima, žanrovima i tržištima te analizu uspješnosti glumaca.

## Tehnologije
- PostgreSQL
- Power BI Desktop
- PowerShell (ETL skripte, TMDB API)

## Struktura projekta
- korak1-relacijske tablice.sql: relacijske tablice
- korak 2-staging tablice.sql: staging tablice
- korak3-dw tablice.sql: tablice skladišta podataka (zvjezdasta shema)
- zvjezdasta_shema_dw.pgerd: ER dijagram skladišta
- kreiranje_particija.sql i optimizacija.sql: particioniranje i optimizacija
- scd2-rucno azuriranje.sql: sporo mijenjajuće dimenzije (SCD tip 2)
- mapa ETL: skripte za inicijalno punjenje, tjedno punjenje novih filmova i ažuriranje podataka

## Pokretanje ETL skripti
Za pokretanje skripti iz mape ETL potrebno je upisati vlastiti TMDB API ključ i lozinku baze na mjestima označenima s "UPISI_SVOJ_TMDB_API_KLJUC" i "UPISI_LOZINKU".
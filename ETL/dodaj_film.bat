@echo off
SET PGPASSWORD=UPISI_LOZINKU

:: ============================================================
:: dodaj_film.bat
:: Dodaje jedan film po TMDB ID-u
:: Pokretanje: dodaj_film.bat 27205
:: ============================================================
IF "%1"=="" (
    SET /P TMDB_ID=Upisi TMDB ID: 
) ELSE (
    SET TMDB_ID=%1
)

SET LOGDIR=C:\Users\Korisnik\Desktop\diplomski\ETL\log
IF NOT EXIST %LOGDIR% mkdir %LOGDIR%

FOR /F "tokens=2 delims==" %%I IN ('wmic os get localdatetime /value') DO SET datetime=%%I
SET DATUM=%datetime:~0,8%

echo [%date% %time%] Dodajem film s TMDB ID: %TMDB_ID%

powershell -ExecutionPolicy Bypass -File "C:\Users\Korisnik\Desktop\diplomski\ETL\dodaj_film.ps1" -tmdb_id %TMDB_ID%

"C:\PostgreSQL\bin\psql.exe" -h localhost -p 5432 -U postgres -d film_dw -f "C:\Users\Korisnik\Desktop\diplomski\ETL\04_etl.sql"

echo [%date% %time%] Film dodan u DW!
pause
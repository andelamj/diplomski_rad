@echo off
SET PGPASSWORD=UPISI_LOZINKU

:: ============================================================
:: azuriranje_filmova.bat
:: Svake veceri — azurira postojece filmove (SCD2)
:: Task Scheduler: svaki dan u 00:00
:: ============================================================
SET LOGDIR=C:\Users\Korisnik\Desktop\diplomski\ETL\log
IF NOT EXIST %LOGDIR% mkdir %LOGDIR%

:: Dohvati datum u ispravnom formatu
FOR /F "tokens=2 delims==" %%I IN ('wmic os get localdatetime /value') DO SET datetime=%%I
SET DATUM=%datetime:~0,8%

echo [%date% %time%] Start azuriranja filmova >> %LOGDIR%\azuriranje_%DATUM%.log

:: Korak 1 — azuriraj filmove s TMDB-a
powershell -ExecutionPolicy Bypass -File "C:\Users\Korisnik\Desktop\diplomski\ETL\azuriranje_filmova.ps1"

:: ETL u DW
"C:\PostgreSQL\bin\psql.exe" -h localhost -p 5432 -U postgres -d film_dw -f "C:\Users\Korisnik\Desktop\diplomski\ETL\04_etl.sql"
echo [%date% %time%] Kraj azuriranja >> %LOGDIR%\azuriranje_%DATUM%.log
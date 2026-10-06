@echo off
SET PGPASSWORD=UPISI_LOZINKU

:: ============================================================
:: novi_filmovi_tjedni.bat
:: Jednom tjedno — dodaje nove filmove iz zadnjih 7 dana
:: Task Scheduler: svaki ponedjeljak u 01:00
:: ============================================================
SET LOGDIR=C:\Users\Korisnik\Desktop\diplomski\ETL\log
IF NOT EXIST %LOGDIR% mkdir %LOGDIR%

FOR /F "tokens=2 delims==" %%I IN ('wmic os get localdatetime /value') DO SET datetime=%%I
SET DATUM=%datetime:~0,8%

echo [%date% %time%] Start tjednog punjenja >> %LOGDIR%\tjedni_%DATUM%.log

powershell -ExecutionPolicy Bypass -File "C:\Users\Korisnik\Desktop\diplomski\ETL\novi_filmovi.ps1"

"C:\PostgreSQL\bin\psql.exe" -h localhost -p 5432 -U postgres -d film_dw -f "C:\Users\Korisnik\Desktop\diplomski\ETL\04_etl.sql" >> %LOGDIR%\tjedni_%DATUM%.log 2>&1

echo [%date% %time%] Kraj tjednog punjenja >> %LOGDIR%\tjedni_%DATUM%.log

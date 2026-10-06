@echo off
SET PGPASSWORD=UPISI_LOZINKU
:: ============================================================
:: punjenje_inicijalno.bat
:: Inicijalno punjenje — pokrenuti JEDNOM
:: ============================================================
SET LOGDIR=C:\Users\Korisnik\Desktop\diplomski\ETL\log
IF NOT EXIST %LOGDIR% mkdir %LOGDIR%

FOR /F "tokens=2 delims==" %%I IN ('wmic os get localdatetime /value') DO SET datetime=%%I
SET DATUM=%datetime:~0,8%

echo [%date% %time%] Start inicijalnog punjenja >> %LOGDIR%\inicijalno_%DATUM%.log

powershell -ExecutionPolicy Bypass -File "C:\Users\Korisnik\Desktop\diplomski\ETL\punjenje_inicijalno.ps1"

echo [%date% %time%] Kraj inicijalnog punjenja >> %LOGDIR%\inicijalno_%DATUM%.log


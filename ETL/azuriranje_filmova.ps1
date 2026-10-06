# ============================================================
# azuriranje_filmova.ps1
# Svake veceri provjerava sve filmove u bazi
# i azurira ih ako se promijenio prihod, ocjena ili broj glasova (SCD2 trigger)
# ============================================================

$API_KEY    = "UPISI_SVOJ_TMDB_API_KLJUC"
$PGHOST     = "localhost"
$PGPORT     = "5432"
$PGDATABASE = "film_dw"
$PGUSER     = "postgres"
$PGPASSWORD = "UPISI_LOZINKU"
$PSQL       = "C:\PostgreSQL\bin\psql.exe"
$TMPDIR     = "C:\Users\Korisnik\Desktop\diplomski\ETL\tmp"
$LOG        = "C:\Users\Korisnik\Desktop\diplomski\ETL\log\azuriranje_" + (Get-Date -Format "yyyyMMdd") + ".log"

$env:PGPASSWORD = $PGPASSWORD

if (!(Test-Path $TMPDIR)) { New-Item -ItemType Directory -Path $TMPDIR | Out-Null }
if (!(Test-Path "C:\Users\Korisnik\Desktop\diplomski\ETL\log")) {
    New-Item -ItemType Directory -Path "C:\Users\Korisnik\Desktop\diplomski\ETL\log" | Out-Null
}

function Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $LOG -Value $line -Encoding UTF8
}

function RunSQL($sqlFile) {
    & $PSQL -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -f $sqlFile 2>&1
}

function RunSQLCmd($sql) {
    & $PSQL -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -A -c $sql 2>&1
}

function CleanText($text) {
    return ($text -replace "[^\x00-\x7F]", "" -replace "'", "''").Trim()
}

function ToDecimal($val) {
    try { 
        $str = ($val -replace '\s','') -replace ',', '.'
        return [decimal]::Parse($str, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch { 
        return [decimal]0 
    }
}

$trzista = @(
    @{ naziv="SAD";                    drzava="SAD";       udio=0.35; cijena=12 },
    @{ naziv="Kina";                   drzava="Kina";      udio=0.25; cijena=5  },
    @{ naziv="Ujedinjeno Kraljevstvo"; drzava="UK";        udio=0.08; cijena=10 },
    @{ naziv="Njemacka";               drzava="Njemacka";  udio=0.05; cijena=9  },
    @{ naziv="Francuska";              drzava="Francuska"; udio=0.05; cijena=9  },
    @{ naziv="Japan";                  drzava="Japan";     udio=0.05; cijena=11 },
    @{ naziv="Hrvatska";               drzava="Hrvatska";  udio=0.01; cijena=6  },
    @{ naziv="Ostatak svijeta";        drzava="Ostalo";    udio=0.16; cijena=7  }
)

Log "Start provjere i azuriranja filmova"

$tmdb_ids_raw = RunSQLCmd "SELECT json_meta->>'tmdb_id' FROM film WHERE json_meta->>'tmdb_id' IS NOT NULL;"
$tmdb_ids = $tmdb_ids_raw | Where-Object { $_ -match '^\s*\d+\s*$' } | ForEach-Object { $_.Trim() }

Log "Ukupno filmova za provjeru: $($tmdb_ids.Count)"

$azurirano = 0
$isto      = 0

foreach ($tmdb_id in $tmdb_ids) {

    $stari_prihod_raw  = (RunSQLCmd "SELECT (json_meta->>'prihod')::NUMERIC FROM film WHERE json_meta->>'tmdb_id' = '$tmdb_id';" | Select-Object -Last 1 | Out-String).Trim()
    $stara_ocj_raw     = (RunSQLCmd "SELECT (json_meta->>'ocjena')::NUMERIC FROM film WHERE json_meta->>'tmdb_id' = '$tmdb_id';" | Select-Object -Last 1 | Out-String).Trim()
    $stari_glasovi_raw = (RunSQLCmd "SELECT (json_meta->>'broj_glasova')::INT FROM film WHERE json_meta->>'tmdb_id' = '$tmdb_id';" | Select-Object -Last 1 | Out-String).Trim()

    $stari_prihod_num  = ToDecimal $stari_prihod_raw
    $stara_ocj_num     = ToDecimal $stara_ocj_raw
    $stari_glasovi_num = ToDecimal $stari_glasovi_raw

    try {
        $d = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/movie/$tmdb_id`?api_key=$API_KEY&language=en-US" -Method Get
    } catch {
        Log "GRESKA dohvat film $tmdb_id"
        continue
    }

    $novi_prihod_num  = ToDecimal ($d.revenue)
    $nova_ocj_num     = ToDecimal ($d.vote_average)
    $novi_glasovi_num = ToDecimal ($d.vote_count)

    $prihod_razlicito  = $novi_prihod_num -ne $stari_prihod_num
    $ocj_razlicito     = [math]::Round($nova_ocj_num, 2) -ne [math]::Round($stara_ocj_num, 2)
    $glasovi_razlicito = $novi_glasovi_num -ne $stari_glasovi_num

    if ($prihod_razlicito -or $ocj_razlicito -or $glasovi_razlicito) {

        $naziv     = CleanText $d.title
        $datum     = if ($d.release_date -and $d.release_date -ne "") { "'$($d.release_date)'" } else { "NULL" }
        $trajanje  = if ($d.runtime -gt 0) { $d.runtime } else { "NULL" }
        $prod_kuca = if ($d.production_companies.Count -gt 0) { CleanText $d.production_companies[0].name } else { "" }

        $json_meta = (@{
            tmdb_id      = [int]$tmdb_id
            ocjena       = $d.vote_average
            broj_glasova = $d.vote_count
            popularnost  = $d.popularity
            prihod       = [long]$novi_prihod_num
            nagrade      = @()
            festivali    = @()
        } | ConvertTo-Json -Compress) -replace "'", "''"

        $uspjesnost_sql = ""
        foreach ($t in $trzista) {
            $tn       = $t.naziv -replace "'", "''"
            $td       = $t.drzava -replace "'", "''"
            $prihod_t = [math]::Round($novi_prihod_num * $t.udio, 2)
            $gleda_t  = if ($t.cijena -gt 0) { [math]::Round($prihod_t / $t.cijena) } else { 0 }
            $uspjesnost_sql += @"

    INSERT INTO trziste (naziv, drzava) VALUES ('$tn', '$td') ON CONFLICT (naziv) DO NOTHING;
    INSERT INTO uspjesnost_filmova (film_id, trziste_id, datum, prihod, br_gledatelja, created_at)
    SELECT v_film_id, trziste_id, $datum, $prihod_t, $gleda_t, NOW()
    FROM trziste WHERE naziv = '$tn';
"@
        }

        $sqlFile = "$TMPDIR\azur_$tmdb_id.sql"
        $sqlContent = @"
DO `$`$
DECLARE
    v_film_id INT;
    v_count   INT;
BEGIN
    UPDATE film
    SET json_meta    = '$json_meta'::jsonb,
        naziv        = '$naziv',
        trajanje_min = $trajanje,
        prod_kuca    = '$prod_kuca'
    WHERE json_meta->>'tmdb_id' = '$tmdb_id'
    RETURNING film_id INTO v_film_id;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'NO_UPDATE';
    END IF;

    DELETE FROM uspjesnost_filmova WHERE film_id = v_film_id;
$uspjesnost_sql
END
`$`$;
"@
        Set-Content -Path $sqlFile -Value $sqlContent -Encoding UTF8
        $result = RunSQL $sqlFile

        if ($LASTEXITCODE -eq 0) {
            Log "Azuriran film: $naziv (prihod: $stari_prihod_num->$novi_prihod_num, ocj: $stara_ocj_num->$nova_ocj_num, glasovi: $stari_glasovi_num->$novi_glasovi_num)"
            $azurirano++
        } elseif ($result -match "NO_UPDATE") {
            $isto++
        } else {
            Log "GRESKA azuriranje: $naziv"
            Log "$result"
        }

        Remove-Item $sqlFile -ErrorAction SilentlyContinue
    } else {
        $isto++
    }
}

Log "Zavrseno - azurirano: $azurirano, bez promjena: $isto"
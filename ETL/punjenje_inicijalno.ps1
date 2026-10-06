# ============================================================
# punjenje_inicijalno.ps1
# Inicijalno punjenje — filmovi od 2024. do 2026.
# FAZA 1: Unos filmova po godinama s odgovarajucim prihodom i datumom
#   - 2024 filmovi: created_at = 2024-12-31, prihod * 0.6
#   - 2025 filmovi: created_at = 2025-12-31, prihod * 0.9
#   - 2026 filmovi: created_at = TODAY,      prihod * 1.0
# FAZA 2: Azuriranje 2024 filmova
#   - ETL reset + azuriraj s created_at = 2025-12-31, prihod * 0.9
#   - ETL reset + azuriraj s created_at = TODAY,      prihod * 1.0
# FAZA 3: Azuriranje 2025 filmova
#   - ETL reset + azuriraj s created_at = TODAY,      prihod * 1.0
# Pokrenuti JEDNOM za inicijalno punjenje baze
# ============================================================

$API_KEY    = "UPISI_SVOJ_TMDB_API_KLJUC"
$PGHOST     = "localhost"
$PGPORT     = "5432"
$PGDATABASE = "film_dw"
$PGUSER     = "postgres"
$PGPASSWORD = "UPISI_LOZINKU"
$PSQL       = "C:\PostgreSQL\bin\psql.exe"
$TMPDIR     = "C:\Users\Korisnik\Desktop\diplomski\ETL\tmp"
$LOG        = "C:\Users\Korisnik\Desktop\diplomski\ETL\log\inicijalno_" + (Get-Date -Format "yyyyMMdd") + ".log"
$ETL_SQL    = "C:\Users\Korisnik\Desktop\diplomski\ETL\04_etl.sql"

$env:PGPASSWORD = $PGPASSWORD
$DANAS = (Get-Date -Format "yyyy-MM-dd")

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

function ResetETLLog($datum) {
    RunSQLCmd "DELETE FROM etl_log WHERE naziv_procesa = 'etl_film_to_staging'; INSERT INTO etl_log (naziv_procesa, zadnji_run) VALUES ('etl_film_to_staging', '$datum');" | Out-Null
    Log "ETL log resetiran na $datum"
}

function PokreniETL() {
    Log "Pokrecam ETL..."
    & $PSQL -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -f $ETL_SQL 2>&1 | Where-Object { $_ -notmatch 'NOTICE' }
    Log "ETL zavrsen"
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

# Konfiguracija po godini
$godine = @(
    @{ od="2024-01-01"; do="2024-12-31"; datum_unosa="2024-12-31"; postotak=0.6; max_pages=100 },
    @{ od="2025-01-01"; do="2025-12-31"; datum_unosa="2025-12-31"; postotak=0.9; max_pages=100 },
    @{ od="2026-01-01"; do=$DANAS;       datum_unosa=$DANAS;        postotak=1.0; max_pages=100 }
)

# ============================================================
# FAZA 1: Unos filmova
# ============================================================
Log "============================================================"
Log "FAZA 1: Unos filmova po godinama"
Log "============================================================"

$ukupno_dodano     = 0
$ukupno_preskoceno = 0
$razlozi_stats      = @{}

foreach ($g in $godine) {

    Log "==============================="
    Log "Punjenje $($g.od) - $($g.do) | datum_unosa=$($g.datum_unosa) | prihod=$($g.postotak*100)%"
    Log "==============================="

    $dodano     = 0
    $preskoceno = 0
    $page       = 1

    while ($page -le $g.max_pages) {

        $url = "https://api.themoviedb.org/3/discover/movie?api_key=$API_KEY&language=en-US&sort_by=revenue.desc&primary_release_date.gte=$($g.od)&primary_release_date.lte=$($g.do)&page=$page"

        try {
            $response = Invoke-RestMethod -Uri $url -Method Get
        } catch {
            Log "GRESKA pri dohvatu stranice $page"
            break
        }

        if ($response.results.Count -eq 0) {
            Log "Nema vise filmova na stranici $page"
            break
        }

        Log "Stranica $page od $([math]::Min($g.max_pages, $response.total_pages))"

        foreach ($film in $response.results) {
            $tmdb_id = $film.id

            try {
                $d = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/movie/$tmdb_id`?api_key=$API_KEY&language=en-US" -Method Get
            } catch {
                Log "GRESKA detalji film $tmdb_id"
                continue
            }

            try {
                $filmska_ekipa = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/movie/$tmdb_id/credits?api_key=$API_KEY" -Method Get
            } catch {
                $filmska_ekipa = $null
            }

            $naziv     = CleanText $d.title
            $datum     = if ($d.release_date -and $d.release_date -ne "") { "'$($d.release_date)'" } else { "NULL" }
            $trajanje  = if ($d.runtime -gt 0) { $d.runtime } else { "NULL" }
            $prod_kuca = if ($d.production_companies.Count -gt 0) { CleanText $d.production_companies[0].name } else { "" }
            $prihod    = if ($d.revenue -gt 0) { $d.revenue } else { 0 }

            # Preskoci filmove bez osnovnih podataka ili bez filmske ekipe
                       # Preskoci filmove bez osnovnih podataka ili bez filmske ekipe
            $razlozi = @()
            if ($datum -eq "NULL")       { $razlozi += "nema datum izlaska" }
            if ($prihod -eq 0)           { $razlozi += "nema prihod (revenue=0)" }
            if ($d.genres.Count -eq 0)   { $razlozi += "nema zanr" }
            if ($naziv -eq "")           { $razlozi += "nema naziv" }
            if (-not $filmska_ekipa) {
                $razlozi += "greska pri dohvatu credits"
            } elseif ($filmska_ekipa.crew.Count -eq 0 -and $filmska_ekipa.cast.Count -eq 0) {
                $razlozi += "nema clanova filmske ekipe (cast/crew prazno)"
            }

             foreach ($r in $razlozi) {
                if ($razlozi_stats.ContainsKey($r)) { $razlozi_stats[$r]++ } else { $razlozi_stats[$r] = 1 }
            }

            if ($razlozi.Count -gt 0) {
                Log "Preskocen film (nepotpuni podaci) [tmdb_id=$tmdb_id]: $naziv -- razlog: $($razlozi -join '; ')"
                $preskoceno++
                continue
            }

            $prihod_godisnji = [math]::Round($prihod * $g.postotak, 0)

            $json_meta = (@{
                tmdb_id      = $tmdb_id
                ocjena       = $d.vote_average
                broj_glasova = $d.vote_count
                popularnost  = $d.popularity
                prihod       = $prihod_godisnji
                nagrade      = @()
                festivali    = @()
            } | ConvertTo-Json -Compress) -replace "'", "''"

            $zanr_sql = ""
            foreach ($z in $d.genres) {
                $zn = CleanText $z.name
                $zanr_sql += @"

    INSERT INTO zanr (naziv) VALUES ('$zn') ON CONFLICT (naziv) DO UPDATE SET naziv=EXCLUDED.naziv;
    INSERT INTO film_zanr (film_id, zanr_id)
    SELECT v_film_id, zanr_id FROM zanr WHERE naziv = '$zn'
    ON CONFLICT DO NOTHING;
"@
            }

            $osoba_sql = ""
            $dir = $filmska_ekipa.crew | Where-Object { $_.job -eq "Director" } | Select-Object -First 1
            if ($dir) {
                $parts = $dir.name -split " ", 2
                $ime  = CleanText $parts[0]
                $prez = if ($parts.Count -gt 1) { CleanText $parts[1] } else { "" }
                $osoba_sql += @"

    INSERT INTO osoba (tmdb_person_id, ime, prezime) VALUES ($($dir.id), '$ime', '$prez')
    ON CONFLICT (tmdb_person_id) DO UPDATE SET ime = EXCLUDED.ime, prezime = EXCLUDED.prezime;
    INSERT INTO film_osoba (film_id, osoba_id, uloga)
    SELECT v_film_id, osoba_id, 'redatelj' FROM osoba WHERE tmdb_person_id = $($dir.id)
    ON CONFLICT DO NOTHING;
"@
            }
            $scen = $filmska_ekipa.crew | Where-Object { $_.job -eq "Screenplay" -or $_.job -eq "Writer" } | Select-Object -First 1
            if ($scen) {
                $parts = $scen.name -split " ", 2
                $ime  = CleanText $parts[0]
                $prez = if ($parts.Count -gt 1) { CleanText $parts[1] } else { "" }
                $osoba_sql += @"

    INSERT INTO osoba (tmdb_person_id, ime, prezime) VALUES ($($scen.id), '$ime', '$prez')
    ON CONFLICT (tmdb_person_id) DO UPDATE SET ime = EXCLUDED.ime, prezime = EXCLUDED.prezime;
    INSERT INTO film_osoba (film_id, osoba_id, uloga)
    SELECT v_film_id, osoba_id, 'scenarist' FROM osoba WHERE tmdb_person_id = $($scen.id)
    ON CONFLICT DO NOTHING;
"@
            }
            $prod = $filmska_ekipa.crew | Where-Object { $_.job -eq "Producer" } | Select-Object -First 1
            if ($prod) {
                $parts = $prod.name -split " ", 2
                $ime  = CleanText $parts[0]
                $prez = if ($parts.Count -gt 1) { CleanText $parts[1] } else { "" }
                $osoba_sql += @"

    INSERT INTO osoba (tmdb_person_id, ime, prezime) VALUES ($($prod.id), '$ime', '$prez')
    ON CONFLICT (tmdb_person_id) DO UPDATE SET ime = EXCLUDED.ime, prezime = EXCLUDED.prezime;
    INSERT INTO film_osoba (film_id, osoba_id, uloga)
    SELECT v_film_id, osoba_id, 'producent' FROM osoba WHERE tmdb_person_id = $($prod.id)
    ON CONFLICT DO NOTHING;
"@
            }
            foreach ($gl in ($filmska_ekipa.cast | Select-Object -First 3)) {
                $parts = $gl.name -split " ", 2
                $ime  = CleanText $parts[0]
                $prez = if ($parts.Count -gt 1) { CleanText $parts[1] } else { "" }
                $osoba_sql += @"

    INSERT INTO osoba (tmdb_person_id, ime, prezime) VALUES ($($gl.id), '$ime', '$prez')
    ON CONFLICT (tmdb_person_id) DO UPDATE SET ime = EXCLUDED.ime, prezime = EXCLUDED.prezime;
    INSERT INTO film_osoba (film_id, osoba_id, uloga)
    SELECT v_film_id, osoba_id, 'glumac' FROM osoba WHERE tmdb_person_id = $($gl.id)
    ON CONFLICT DO NOTHING;
"@
            }

            # Ako nema niti jedne osobe nakon parsiranja, preskoèi film
            if ($osoba_sql -eq "") {
                Log "Preskocen film (nema osoba): $naziv"
                $preskoceno++
                continue
            }

            $uspjesnost_sql = ""
            foreach ($t in $trzista) {
                $tn       = $t.naziv -replace "'", "''"
                $td       = $t.drzava -replace "'", "''"
                $prihod_t = [math]::Round($prihod_godisnji * $t.udio, 2)
                $gleda_t  = if ($t.cijena -gt 0) { [math]::Round($prihod_t / $t.cijena) } else { 0 }

                $uspjesnost_sql += @"

    INSERT INTO trziste (naziv, drzava) VALUES ('$tn', '$td') ON CONFLICT (naziv) DO NOTHING;
    INSERT INTO uspjesnost_filmova (film_id, trziste_id, datum, prihod, br_gledatelja, created_at)
    SELECT v_film_id, trziste_id, $datum, $prihod_t, $gleda_t, '$($g.datum_unosa)'::timestamp
    FROM trziste WHERE naziv = '$tn';
"@
            }

            $sqlFile = "$TMPDIR\film_$tmdb_id.sql"
            $sqlContent = @"
DO `$`$
DECLARE
    v_film_id INT;
BEGIN
    PERFORM 1 FROM film
    WHERE json_meta->>'tmdb_id' = '$tmdb_id';

    IF NOT FOUND THEN
        INSERT INTO film (naziv, datum_izlaska, trajanje_min, prod_kuca, json_meta)
        VALUES ('$naziv', $datum, $trajanje, '$prod_kuca', '$json_meta'::jsonb)
        RETURNING film_id INTO v_film_id;
$zanr_sql
$osoba_sql
$uspjesnost_sql
    ELSE
        NULL;
    END IF;
END
`$`$;
"@
            Set-Content -Path $sqlFile -Value $sqlContent -Encoding UTF8
            $result = RunSQL $sqlFile

            if ($LASTEXITCODE -eq 0) {
                Log "Dodan film: $naziv ($($g.datum_unosa))"
                $dodano++
            } else {
                Log "GRESKA za film: $naziv"
                Log "$result"
            }

            Remove-Item $sqlFile -ErrorAction SilentlyContinue
        }

        if ($page -ge $response.total_pages) { break }
        $page++
    }

    Log "Period $($g.od)-$($g.do) zavrsen — dodano: $dodano, preskoceno: $preskoceno"
    $ukupno_dodano     += $dodano
    $ukupno_preskoceno += $preskoceno
}

Log "FAZA 1 zavrsena — ukupno dodano: $ukupno_dodano, preskoceno: $ukupno_preskoceno"

Log "============================================================"
Log "Statistika preskocenih filmova po razlogu:"
foreach ($r in ($razlozi_stats.Keys | Sort-Object)) {
    Log ("  {0}: {1}" -f $r, $razlozi_stats[$r])
}
Log "============================================================"

ResetETLLog "1900-01-01"
PokreniETL

# ============================================================
# FAZA 2a: Azuriranje 2024 filmova za 2025
# ============================================================
Log "============================================================"
Log "FAZA 2a: Azuriranje 2024 filmova — created_at=2025-12-31, prihod=90%"
Log "============================================================"

$film_ids_2024 = RunSQLCmd "SELECT film_id, (json_meta->>'prihod')::NUMERIC, datum_izlaska::TEXT FROM film WHERE datum_izlaska BETWEEN '2024-01-01' AND '2024-12-31';"
$film_ids_2024 = $film_ids_2024 | Where-Object { $_ -match '^\s*\d+' } | ForEach-Object { $_.Trim() }

foreach ($red in $film_ids_2024) {
    $dijelovi  = $red -split '\|'
    if ($dijelovi.Count -lt 3) { continue }
    $film_id   = $dijelovi[0].Trim()
    $prihod_60 = [decimal]$dijelovi[1].Trim()
    $datum     = "'$($dijelovi[2].Trim())'"

    $prihod_90 = [math]::Round($prihod_60 / 0.6 * 0.9, 0)

    $uspjesnost_sql = "DELETE FROM uspjesnost_filmova WHERE film_id = $film_id;`n"
    foreach ($t in $trzista) {
        $tn       = $t.naziv -replace "'", "''"
        $prihod_t = [math]::Round($prihod_90 * $t.udio, 2)
        $gleda_t  = if ($t.cijena -gt 0) { [math]::Round($prihod_t / $t.cijena) } else { 0 }
        $uspjesnost_sql += @"

INSERT INTO trziste (naziv, drzava) VALUES ('$tn', '$($t.drzava)') ON CONFLICT (naziv) DO NOTHING;
INSERT INTO uspjesnost_filmova (film_id, trziste_id, datum, prihod, br_gledatelja, created_at)
SELECT $film_id, trziste_id, $datum, $prihod_t, $gleda_t, '2025-12-31'::timestamp
FROM trziste WHERE naziv = '$tn';
"@
    }

    $sqlFile = "$TMPDIR\azur2025_$film_id.sql"
    $sqlContent = @"
UPDATE film SET json_meta = jsonb_set(json_meta, '{prihod}', '$prihod_90') WHERE film_id = $film_id;
$uspjesnost_sql
"@
    Set-Content -Path $sqlFile -Value $sqlContent -Encoding UTF8
    RunSQL $sqlFile | Out-Null
    Remove-Item $sqlFile -ErrorAction SilentlyContinue
}

Log "FAZA 2a zavrsena"
ResetETLLog "1900-01-01"
PokreniETL

# ============================================================
# FAZA 2b: Azuriranje 2024 filmova za 2026
# ============================================================
Log "============================================================"
Log "FAZA 2b: Azuriranje 2024 filmova — created_at=$DANAS, prihod=100%"
Log "============================================================"

$film_ids_2024 = RunSQLCmd "SELECT film_id, (json_meta->>'prihod')::NUMERIC, datum_izlaska::TEXT FROM film WHERE datum_izlaska BETWEEN '2024-01-01' AND '2024-12-31';"
$film_ids_2024 = $film_ids_2024 | Where-Object { $_ -match '^\s*\d+' } | ForEach-Object { $_.Trim() }

foreach ($red in $film_ids_2024) {
    $dijelovi  = $red -split '\|'
    if ($dijelovi.Count -lt 3) { continue }
    $film_id   = $dijelovi[0].Trim()
    $prihod_90 = [decimal]$dijelovi[1].Trim()
    $datum     = "'$($dijelovi[2].Trim())'"

    $prihod_100 = [math]::Round($prihod_90 / 0.9, 0)

    $uspjesnost_sql = "DELETE FROM uspjesnost_filmova WHERE film_id = $film_id;`n"
    foreach ($t in $trzista) {
        $tn       = $t.naziv -replace "'", "''"
        $prihod_t = [math]::Round($prihod_100 * $t.udio, 2)
        $gleda_t  = if ($t.cijena -gt 0) { [math]::Round($prihod_t / $t.cijena) } else { 0 }
        $uspjesnost_sql += @"

INSERT INTO uspjesnost_filmova (film_id, trziste_id, datum, prihod, br_gledatelja, created_at)
SELECT $film_id, trziste_id, $datum, $prihod_t, $gleda_t, '$DANAS'::timestamp
FROM trziste WHERE naziv = '$tn';
"@
    }

    $sqlFile = "$TMPDIR\azur2026a_$film_id.sql"
    $sqlContent = @"
UPDATE film SET json_meta = jsonb_set(json_meta, '{prihod}', '$prihod_100') WHERE film_id = $film_id;
$uspjesnost_sql
"@
    Set-Content -Path $sqlFile -Value $sqlContent -Encoding UTF8
    RunSQL $sqlFile | Out-Null
    Remove-Item $sqlFile -ErrorAction SilentlyContinue
}

Log "FAZA 2b zavrsena"
ResetETLLog "1900-01-01"
PokreniETL

# ============================================================
# FAZA 3: Azuriranje 2025 filmova za 2026
# ============================================================
Log "============================================================"
Log "FAZA 3: Azuriranje 2025 filmova — created_at=$DANAS, prihod=100%"
Log "============================================================"

$film_ids_2025 = RunSQLCmd "SELECT film_id, (json_meta->>'prihod')::NUMERIC, datum_izlaska::TEXT FROM film WHERE datum_izlaska BETWEEN '2025-01-01' AND '2025-12-31';"
$film_ids_2025 = $film_ids_2025 | Where-Object { $_ -match '^\s*\d+' } | ForEach-Object { $_.Trim() }

foreach ($red in $film_ids_2025) {
    $dijelovi  = $red -split '\|'
    if ($dijelovi.Count -lt 3) { continue }
    $film_id   = $dijelovi[0].Trim()
    $prihod_90 = [decimal]$dijelovi[1].Trim()
    $datum     = "'$($dijelovi[2].Trim())'"

    $prihod_100 = [math]::Round($prihod_90 / 0.9, 0)

    $uspjesnost_sql = "DELETE FROM uspjesnost_filmova WHERE film_id = $film_id;`n"
    foreach ($t in $trzista) {
        $tn       = $t.naziv -replace "'", "''"
        $prihod_t = [math]::Round($prihod_100 * $t.udio, 2)
        $gleda_t  = if ($t.cijena -gt 0) { [math]::Round($prihod_t / $t.cijena) } else { 0 }
        $uspjesnost_sql += @"

INSERT INTO uspjesnost_filmova (film_id, trziste_id, datum, prihod, br_gledatelja, created_at)
SELECT $film_id, trziste_id, $datum, $prihod_t, $gleda_t, '$DANAS'::timestamp
FROM trziste WHERE naziv = '$tn';
"@
    }

    $sqlFile = "$TMPDIR\azur2026b_$film_id.sql"
    $sqlContent = @"
UPDATE film SET json_meta = jsonb_set(json_meta, '{prihod}', '$prihod_100') WHERE film_id = $film_id;
$uspjesnost_sql
"@
    Set-Content -Path $sqlFile -Value $sqlContent -Encoding UTF8
    RunSQL $sqlFile | Out-Null
    Remove-Item $sqlFile -ErrorAction SilentlyContinue
}

Log "FAZA 3 zavrsena"
ResetETLLog "1900-01-01"
PokreniETL

Log "============================================================"
Log "SVE FAZE ZAVRSENE!"
Log "============================================================"
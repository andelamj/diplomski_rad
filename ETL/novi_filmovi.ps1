# ============================================================
# punjenje_inkrementalno.ps1
# Inkrementalno punjenje — novi filmovi izasli u zadnjih 7 dana
# Prolazi kroz sve stranice dok nema vise rezultata
# Pokretati tjedno putem Task Schedulera
# ============================================================

$API_KEY    = "UPISI_SVOJ_TMDB_API_KLJUC"
$PGHOST     = "localhost"
$PGPORT     = "5432"
$PGDATABASE = "film_dw"
$PGUSER     = "postgres"
$PGPASSWORD = "UPISI_LOZINKU"
$PSQL       = "C:\PostgreSQL\bin\psql.exe"
$TMPDIR     = "C:\Users\Korisnik\Desktop\diplomski\ETL\tmp"
$LOG        = "C:\Users\Korisnik\Desktop\diplomski\ETL\log\inkrementalno_" + (Get-Date -Format "yyyyMMdd") + ".log"

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

function CleanText($text) {
    return ($text -replace "[^\x00-\x7F]", "" -replace "'", "''").Trim()
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

$datum_od = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
$datum_do = (Get-Date -Format "yyyy-MM-dd")

Log "Start inkrementalnog punjenja filmova s TMDB-a ($datum_od do $datum_do)"

$dodano      = 0
$preskoceno  = 0
$vec_postoji = 0
$razlozi_stats = @{}
$page        = 1
$nastavi     = $true

while ($nastavi) {

    $url = "https://api.themoviedb.org/3/discover/movie?api_key=$API_KEY&language=en-US&sort_by=revenue.desc&primary_release_date.gte=$datum_od&primary_release_date.lte=$datum_do&page=$page"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get
    } catch {
        Log "GRESKA pri dohvatu stranice $page — zaustavljam"
        break
    }

    if ($response.results.Count -eq 0) {
        Log "Nema vise filmova — zaustavljam"
        break
    }

    Log "Stranica $page od $($response.total_pages)"

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

        $json_meta = (@{
            tmdb_id      = $tmdb_id
            ocjena       = $d.vote_average
            broj_glasova = $d.vote_count
            popularnost  = $d.popularity
            prihod       = $prihod
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
        if ($filmska_ekipa -and ($filmska_ekipa.crew.Count -gt 0 -or $filmska_ekipa.cast.Count -gt 0)) {
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
            foreach ($g in ($filmska_ekipa.cast | Select-Object -First 3)) {
                $parts = $g.name -split " ", 2
                $ime  = CleanText $parts[0]
                $prez = if ($parts.Count -gt 1) { CleanText $parts[1] } else { "" }
                $osoba_sql += @"

    INSERT INTO osoba (tmdb_person_id, ime, prezime) VALUES ($($g.id), '$ime', '$prez')
    ON CONFLICT (tmdb_person_id) DO UPDATE SET ime = EXCLUDED.ime, prezime = EXCLUDED.prezime;
    INSERT INTO film_osoba (film_id, osoba_id, uloga)
    SELECT v_film_id, osoba_id, 'glumac' FROM osoba WHERE tmdb_person_id = $($g.id)
    ON CONFLICT DO NOTHING;
"@
            }
        } else {
            $osoba_sql = @"

    INSERT INTO osoba (tmdb_person_id, ime, prezime) VALUES (-1, 'Nepoznato', '')
    ON CONFLICT (tmdb_person_id) DO UPDATE SET ime = EXCLUDED.ime, prezime = EXCLUDED.prezime;
    INSERT INTO film_osoba (film_id, osoba_id, uloga)
    SELECT v_film_id, osoba_id, 'glumac' FROM osoba WHERE tmdb_person_id = -1
    ON CONFLICT DO NOTHING;
"@
        }

        $uspjesnost_sql = ""
        foreach ($t in $trzista) {
            $tn       = $t.naziv -replace "'", "''"
            $td       = $t.drzava -replace "'", "''"
            $prihod_t = [math]::Round($prihod * $t.udio, 2)
            $gleda_t  = if ($t.cijena -gt 0) { [math]::Round($prihod_t / $t.cijena) } else { 0 }
            $uspjesnost_sql += @"

    INSERT INTO trziste (naziv, drzava) VALUES ('$tn', '$td') ON CONFLICT (naziv) DO NOTHING;
    INSERT INTO uspjesnost_filmova (film_id, trziste_id, datum, prihod, br_gledatelja, created_at)
    SELECT v_film_id, trziste_id, $datum, $prihod_t, $gleda_t, NOW()
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
        RAISE NOTICE 'VEC_POSTOJI';
    END IF;
END
`$`$;
"@
        Set-Content -Path $sqlFile -Value $sqlContent -Encoding UTF8
        $result = RunSQL $sqlFile

        if ($LASTEXITCODE -eq 0) {
            if ($result -match "VEC_POSTOJI") {
                Log "Film vec postoji u bazi: $naziv"
                $vec_postoji++
            } else {
                Log "Dodan film: $naziv"
                $dodano++
            }
        } else {
            Log "GRESKA za film: $naziv"
            Log "$result"
        }

        Remove-Item $sqlFile -ErrorAction SilentlyContinue
    }

    if ($page -ge $response.total_pages) {
        Log "Dostignut kraj — zadnja stranica: $page"
        $nastavi = $false
    } else {
        $page++
    }
}

Log "Zavrseno - dodano: $dodano, vec postoji: $vec_postoji, preskoceno: $preskoceno"

Log "============================================================"
Log "Statistika preskocenih filmova po razlogu:"
foreach ($r in ($razlozi_stats.Keys | Sort-Object)) {
    Log ("  {0}: {1}" -f $r, $razlozi_stats[$r])
}
Log "============================================================"
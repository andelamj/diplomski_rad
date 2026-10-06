# ============================================================
# dodaj_film.ps1
# Dodaje jedan film u bazu prema TMDB ID-u
# Pokretanje: .\dodaj_film.ps1 -tmdb_id 27205
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [int]$tmdb_id
)

$API_KEY    = "UPISI_SVOJ_TMDB_API_KLJUC"
$PGHOST     = "localhost"
$PGPORT     = "5432"
$PGDATABASE = "film_dw"
$PGUSER     = "postgres"
$PGPASSWORD = "UPISI_LOZINKU"
$PSQL       = "C:\PostgreSQL\bin\psql.exe"
$TMPDIR     = "C:\Users\Korisnik\Desktop\diplomski\ETL\tmp"
$LOG        = "C:\Users\Korisnik\Desktop\diplomski\ETL\log\dodaj_film_" + (Get-Date -Format "yyyyMMdd") + ".log"

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

Log "Start dodavanja filma s TMDB ID: $tmdb_id"

# Provjeri postoji li vec u bazi
$postoji = & $PSQL -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -t -A -c "SELECT COUNT(*) FROM film WHERE json_meta->>'tmdb_id' = '$tmdb_id';" 2>&1
$postoji = [int](($postoji | Select-Object -Last 1) -replace '\s','')

if ($postoji -gt 0) {
    Log "Film s TMDB ID $tmdb_id vec postoji u bazi!"
    exit 0
}

# Detalji filma
try {
    $d = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/movie/$tmdb_id`?api_key=$API_KEY&language=en-US" -Method Get
} catch {
    Log "GRESKA: Ne mogu dohvatiti film s TMDB ID $tmdb_id"
    exit 1
}

# Filmska ekipa
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
if ($prihod -eq 0) {
    Log "Preskocen film (nema prihoda na TMDB): $naziv"
    exit 0
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

# Zanrovi SQL
$zanr_sql = ""
if ($d.genres.Count -gt 0) {
    foreach ($z in $d.genres) {
        $zn = CleanText $z.name
        $zanr_sql += @"

    INSERT INTO zanr (naziv) VALUES ('$zn') ON CONFLICT (naziv) DO UPDATE SET naziv=EXCLUDED.naziv;
    INSERT INTO film_zanr (film_id, zanr_id)
    SELECT v_film_id, zanr_id FROM zanr WHERE naziv = '$zn'
    ON CONFLICT DO NOTHING;
"@
    }
} else {
    $zanr_sql = @"

    INSERT INTO zanr (naziv) VALUES ('Nepoznato') ON CONFLICT (naziv) DO NOTHING;
    INSERT INTO film_zanr (film_id, zanr_id)
    SELECT v_film_id, zanr_id FROM zanr WHERE naziv = 'Nepoznato'
    ON CONFLICT DO NOTHING;
"@
}

# Osobe SQL
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

# Uspjesnost filmova SQL
$uspjesnost_sql = ""
foreach ($t in $trzista) {
    $tn       = $t.naziv -replace "'", "''"
    $td       = $t.drzava -replace "'", "''"
    $prihod_t = [math]::Round($prihod * $t.udio, 2)
    $gleda_t  = if ($t.cijena -gt 0) { [math]::Round($prihod_t / $t.cijena) } else { 0 }
    $uspjesnost_sql += @"

    INSERT INTO trziste (naziv, drzava) VALUES ('$tn', '$td') ON CONFLICT (naziv) DO NOTHING;
    INSERT INTO uspjesnost_filmova (film_id, trziste_id, datum, prihod, br_gledatelja)
    SELECT v_film_id, trziste_id, COALESCE($datum, CURRENT_DATE), $prihod_t, $gleda_t
    FROM trziste WHERE naziv = '$tn';
"@
}

$sqlFile = "$TMPDIR\film_manual_$tmdb_id.sql"
$sqlContent = @"
DO `$`$
DECLARE
    v_film_id INT;
BEGIN
    INSERT INTO film (naziv, datum_izlaska, trajanje_min, prod_kuca, json_meta)
    VALUES ('$naziv', $datum, $trajanje, '$prod_kuca', '$json_meta'::jsonb)
    RETURNING film_id INTO v_film_id;
$zanr_sql
$osoba_sql
$uspjesnost_sql
END
`$`$;
"@

Set-Content -Path $sqlFile -Value $sqlContent -Encoding UTF8
$result = RunSQL $sqlFile

if ($LASTEXITCODE -eq 0) {
    Log "Uspjesno dodan film: $naziv (TMDB ID: $tmdb_id)"
} else {
    Log "GRESKA pri dodavanju filma: $naziv"
    Log "$result"
}

Remove-Item $sqlFile -ErrorAction SilentlyContinue
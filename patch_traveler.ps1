# patch_traveler.ps1
param(
  [string]$ZipPath      = "G:\users\daveq\traveler_patch_latlng_2025-09-20-updated.zip",
  [string]$ProjectRoot  = "G:\users\daveq\traveler",
  [switch]$Backfill     = $false
)

$ErrorActionPreference = "Stop"

function Info($msg){ Write-Host $msg -ForegroundColor Cyan }
function Ok($msg){ Write-Host $msg -ForegroundColor Green }
function Warn($msg){ Write-Host $msg -ForegroundColor Yellow }
function Fail($msg){ Write-Host $msg -ForegroundColor Red }

# 0) Sanity checks
if (!(Test-Path $ZipPath)) { Fail "ZIP not found: $ZipPath"; exit 1 }
if (!(Test-Path (Join-Path $ProjectRoot "manage.py"))) { Fail "manage.py not found in $ProjectRoot"; exit 1 }

$settingsPath = Join-Path $ProjectRoot "config\settings.py"
if (!(Test-Path $settingsPath)) { Fail "Expected settings at $settingsPath"; exit 1 }

$staysPath = Join-Path $ProjectRoot "stays"
if (!(Test-Path $staysPath)) { Fail "stays app not found at $staysPath"; exit 1 }

# 1) Extract ZIP to temp
$TempRoot = Join-Path $env:TEMP ("trav_patch_" + (Get-Date -Format "yyyyMMddHHmmss"))
Info "Extracting ZIP to $TempRoot"
Expand-Archive -Path $ZipPath -DestinationPath $TempRoot -Force

# 2) Locate the extracted /stays folder
Info "Locating 'stays' in extracted contents..."
$extractedStaysRoot = Get-ChildItem -Path $TempRoot -Directory -Recurse `
  | Where-Object { Test-Path (Join-Path $_.FullName 'stays\forms.py') } `
  | Select-Object -First 1 -ExpandProperty FullName

if (-not $extractedStaysRoot) {
  # Fallback: maybe it's directly under the root
  if (Test-Path (Join-Path $TempRoot 'stays\forms.py')) {
    $extractedStaysRoot = $TempRoot
  } else {
    Fail "Couldn't find 'stays' folder in the ZIP after extracting to $TempRoot"
    exit 1
  }
}
$extractedStays = Join-Path $extractedStaysRoot "stays"
Ok "Using patch stays at: $extractedStays"

# 3) Backup current stays
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $ProjectRoot ("stays_backup_" + $ts)
Info "Backing up current stays to $backupPath"
Copy-Item -Recurse -Force $staysPath $backupPath

# 4) Copy patched files into stays
Info "Copying patched files into $staysPath"
Copy-Item -Recurse -Force (Join-Path $extractedStays "*") $staysPath
Ok "Patched files copied."

# 5) Fix migration dependency
$migrationsDir = Join-Path $staysPath "migrations"
$targetMig = Join-Path $migrationsDir "0009_add_lat_lng.py"
if (!(Test-Path $targetMig)) { Fail "Expected migration not found: $targetMig"; exit 1 }

# find latest existing migration, excluding __init__ and the new 0009
$migs = Get-ChildItem (Join-Path $migrationsDir "*.py") |
  Where-Object { $_.Name -notmatch '^__init__\.py$' -and $_.Name -ne '0009_add_lat_lng.py' } |
  Sort-Object Name

if (-not $migs) { Fail "No existing migrations found in $migrationsDir"; exit 1 }

$lastBase = [IO.Path]::GetFileNameWithoutExtension($migs[-1].Name)
Info "Setting migration dependency to: $lastBase"

(Get-Content $targetMig) `
  -replace "\('stays', '0008_previous_migration'\)", "('stays', '$lastBase')" `
  | Set-Content $targetMig
Ok "Migration dependency updated."

# 6) Ensure GEOCODER_USER_AGENT in settings
$settingsText = Get-Content $settingsPath -Raw
if ($settingsText -notmatch "GEOCODER_USER_AGENT") {
  Add-Content $settingsPath "`n# For geopy/Nominatim auto-geocoding`nGEOCODER_USER_AGENT = `"traveler-app`"`n"
  Ok "Added GEOCODER_USER_AGENT to config/settings.py"
} else {
  Warn "GEOCODER_USER_AGENT already present"
}

# 7) Ensure INSTALLED_APPS uses stays.apps.StaysConfig
if ($settingsText -match "'stays'\s*,") {
  $settingsText = $settingsText -replace "'stays'\s*,", "'stays.apps.StaysConfig',"
  $settingsText | Set-Content $settingsPath
  Ok "Updated INSTALLED_APPS to 'stays.apps.StaysConfig'"
} elseif ($settingsText -notmatch "stays\.apps\.StaysConfig") {
  Warn "Could not find 'stays' in INSTALLED_APPS; ensure it's listed as 'stays.apps.StaysConfig'"
} else {
  Warn "INSTALLED_APPS already references stays.apps.StaysConfig"
}

# 8) Ensure model fields exist in stays/models.py (idempotent insert)
$modelsPath = Join-Path $staysPath "models.py"
if (!(Test-Path $modelsPath)) {
  Warn "No models.py found at $modelsPath (skipping model field insert)"
} else {
  $models = Get-Content $modelsPath -Raw
  $needLat = ($models -notmatch "\blatitude\s*=\s*models\.DecimalField")
  $needLng = ($models -notmatch "\blongitude\s*=\s*models\.DecimalField")

  if ($needLat -or $needLng) {
    Info "Injecting latitude/longitude fields into models.py"

    # naive but robust insertion: place fields right after the class Stay(models.Model) line
    $pattern = "class\s+Stay\s*\(\s*models\.Model\s*\)\s*:"
    if ($models -match $pattern) {
      $insertion = @()
      if ($needLat) { $insertion += "    latitude  = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)" }
      if ($needLng) { $insertion += "    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)" }
      $insertionText = "`r`n" + ($insertion -join "`r`n") + "`r`n"

      $models = [System.Text.RegularExpressions.Regex]::Replace(
        $models, $pattern,
        { param($m) $m.Value + $insertionText },
        [System.Text.RegularExpressions.RegexOptions]::Singleline
      )
      Set-Content $modelsPath $models -NoNewline
      Ok "Added fields to models.py"
    } else {
      Warn "Could not find class Stay(models.Model) in models.py; add fields manually."
    }
  } else {
    Warn "latitude/longitude already present in models.py"
  }
}

# 9) Run migrate (stays only)
Push-Location $ProjectRoot
try {
  Info "Running database migration for stays..."
  python manage.py migrate --settings=config.settings stays
  Ok "Migration completed."
} catch {
  Fail "Migration failed: $($_.Exception.Message)"
  Pop-Location
  exit 1
}

# 10) Optional backfill
if ($Backfill) {
  try {
    Info "Backfilling coordinates for existing stays (missing lat/lng)..."
    python manage.py backfill_geocode --settings=config.settings
    Ok "Backfill completed."
  } catch {
    Fail "Backfill failed: $($_.Exception.Message)"
  }
}
Pop-Location

Ok "All done. Open Add Stay to verify latitude/longitude fields are visible and editable."

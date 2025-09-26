# quick_fix_critical.ps1
# Minimal, safe fixes to unblock ruff/black.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

function Backup($p) { if (Test-Path $p) { Copy-Item $p "$p.bak.$ts" -Force } }
function ReadAll($p) { Get-Content $p -Raw }
function WriteAll($p, $s) { Set-Content $p $s -Encoding UTF8 }

# --- 1) Fix parse error in auto_doctor_stays.py (bad escaped quotes) ---
$autoDoctor = ".\auto_doctor_stays.py"
if (Test-Path $autoDoctor) {
  $t = ReadAll $autoDoctor
  $orig = $t
  # Replace \" with "
  $t = $t -replace '\\\"','"'
  # Normalize stray print patterns if present (best effort)
  $t = $t -replace 'print\(\s*""','print("'
  if ($t -ne $orig) {
    Backup $autoDoctor
    WriteAll $autoDoctor $t
    Write-Host "Fixed quotes in auto_doctor_stays.py" -ForegroundColor Green
  } else {
    Write-Host "No quote fixes needed in auto_doctor_stays.py" -ForegroundColor DarkGray
  }
} else {
  Write-Host "Skip: auto_doctor_stays.py not found" -ForegroundColor Yellow
}

# --- 2) Remove unused `before = txt` lines in v2 scripts ---
$unusedTargets = @(
  ".\auto_doctor_stays_v2.py",
  ".\auto_doctor_stays_v2 - Copy.py"
) | Where-Object { Test-Path $_ }

foreach ($f in $unusedTargets) {
  $t = ReadAll $f
  $orig = $t
  $t = $t -replace '(?m)^\s*before\s*=\s*txt\s*\r?\n',''
  if ($t -ne $orig) {
    Backup $f
    WriteAll $f $t
    Write-Host "Removed unused 'before = txt' in $f" -ForegroundColor Green
  } else {
    Write-Host "No 'before = txt' to remove in $f" -ForegroundColor DarkGray
  }
}

# --- 3) stays/views.py cleanup (imports + bare excepts) ---
$staysViews = ".\stays\views.py"
if (Test-Path $staysViews) {
  $t = ReadAll $staysViews
  $orig = $t

  # Remove duplicate Stay import like: from stays.models import Stay
  $t = $t -replace '(?m)^\s*from\s+stays\.models\s+import\s+Stay\s*\r?\n',''

  # Remove any late imports of io / csv as _csv
  $t = $t -replace '(?m)^\s*import\s+io\s*\r?\n',''
  $t = $t -replace '(?m)^\s*import\s+csv\s+as\s+_csv\s*\r?\n',''

  # Ensure imports are at the very top (add once if missing)
  $needsIo   = ($t -notmatch '(?m)^\s*import\s+io\s*$')
  $needsCsv  = ($t -notmatch '(?m)^\s*import\s+csv\s+as\s+_csv\s*$')

  if ($needsIo -or $needsCsv) {
    # Insert after the first block of imports (heuristic): before the first "from django" or similar
    $inserts = @()
    if ($needsIo)  { $inserts += 'import io' }
    if ($needsCsv) { $inserts += 'import csv as _csv' }
    $insertBlock = ($inserts -join "`r`n") + "`r`n"
    # If there's a shebang or encoding line, skip past it; otherwise just prepend.
    if ($t -match '^(#!.*\r?\n)?(#.*coding.*\r?\n)?') {
      $t = $insertBlock + $t
    }
  }

  # Replace bare 'except:' specifically around simple coercions with typed exceptions
  # nights/rate/price parsing
  $t = $t -replace '(?m)^\s*except:\s*$','        except (TypeError, ValueError):'

  if ($t -ne $orig) {
    Backup $staysViews
    WriteAll $staysViews $t
    Write-Host "Patched stays/views.py (imports + excepts)" -ForegroundColor Green
  } else {
    Write-Host "No changes applied to stays/views.py" -ForegroundColor DarkGray
  }
} else {
  Write-Host "Skip: stays/views.py not found" -ForegroundColor Yellow
}

# --- 4) traveler_fix/stays/views.py: ensure JsonResponse import is top-level ---
$travFixViews = ".\traveler_fix\stays\views.py"
if (Test-Path $travFixViews) {
  $t = ReadAll $travFixViews
  $orig = $t

  # Remove any line 'from django.http import JsonResponse'
  $t = $t -replace '(?m)^\s*from\s+django\.http\s+import\s+JsonResponse\s*\r?\n',''
  # Add it once at the very top
  if ($t -notmatch '(?m)^\s*from\s+django\.http\s+import\s+JsonResponse\s*$') {
    $t = "from django.http import JsonResponse`r`n" + $t
  }

  if ($t -ne $orig) {
    Backup $travFixViews
    WriteAll $travFixViews $t
    Write-Host "Moved JsonResponse import to top in traveler_fix/stays/views.py" -ForegroundColor Green
  } else {
    Write-Host "No changes applied to traveler_fix/stays/views.py" -ForegroundColor DarkGray
  }
} else {
  Write-Host "Skip: traveler_fix/stays/views.py not found" -ForegroundColor Yellow
}

Write-Host "`nDone. Now run:" -ForegroundColor Cyan
Write-Host "  ruff check . --fix" -ForegroundColor Cyan
Write-Host "  black ." -ForegroundColor Cyan

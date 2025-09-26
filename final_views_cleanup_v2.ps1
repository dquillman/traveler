# final_views_cleanup_v2.ps1
# Cleans malformed conditional-return chunk in stays\views.py and verifies syntax.

$ErrorActionPreference = "Stop"

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host "Backup: $Path.bak.$stamp"
  }
}

$views = "stays\views.py"
if (-not (Test-Path $views)) {
  Write-Host "!! $views not found." -ForegroundColor Yellow
  exit 1
}

Write-Host "[1/4] Backing up views.py"
Backup-File $views

Write-Host "[2/4] Cleaning malformed conditional return..." -ForegroundColor Cyan
$raw = Get-Content -Raw $views

# Pattern A: multi-line junk shown in your error (return + redirect + if ... else ... + ) )
$patternA = "(?ms)^\s*return\s+redirect\(""stay_list""\)\s*\r?\n\s*redirect\(""stay_list""\)\s*\r?\n\s*if\s+.*?locals\(\)\s*\r?\n\s*else\s+redirect\(""stays_import""\)\s*\r?\n\s*\)\s*"
$raw2 = [regex]::Replace($raw, $patternA, "return redirect(""stay_list"")`r`n")

# Pattern B: two-line ternary-ish variant (no initial return)
$patternB = "(?m)^\s*redirect\(""stay_list""\)\s*\r?\n\s*if\s+.*?locals\(\)\s*\r?\n\s*else\s+redirect\(""stays_import""\)\s*$"
$raw2 = [regex]::Replace($raw2, $patternB, "return redirect(""stay_list"")")

# Pattern C: single-line variant (unlikely, but safe)
$patternC = "(?m)^\s*redirect\(""stay_list""\)\s+if\s+.*?locals\(\)\s+else\s+redirect\(""stays_import""\)\s*$"
$raw2 = [regex]::Replace($raw2, $patternC, "return redirect(""stay_list"")")

# Pattern D: stray lone ')' immediately after a return line
$patternD = "(?m)(?<=return\s+redirect\(""stay_list""\)\s*\r?\n)\s*\)\s*$"
$raw2 = [regex]::Replace($raw2, $patternD, "")

# Normalize tabs to spaces (best-effort)
$raw2 = $raw2 -replace "`t","    "

if ($raw2 -ne $raw) {
  Set-Content -Path $views -Value $raw2 -NoNewline
  Write-Host "  - Cleaned conditional return and stray parens." -ForegroundColor Green
} else {
  Write-Host "  = Nothing to change; patterns not found."
}

Write-Host "[3/4] Syntax check + Ruff/Black" -ForegroundColor Cyan

# Quick compile test for this file only
python -m py_compile stays\views.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! Python compile error in stays\views.py" -ForegroundColor Red
  Write-Host "    Open around the recent 'return redirect(\"stay_list\")' lines and check indentation/parentheses."
  exit 1
} else {
  Write-Host "  - Python compile check passed."
}

# Ruff/Black on the one file (keeps it surgical)
try { ruff --version | Out-Null ; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null ; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

Write-Host "[4/4] Done. Start server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

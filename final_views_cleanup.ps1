# final_views_cleanup.ps1
# Cleans the lingering malformed conditional return block in stays\views.py
# and ensures a single, valid `return redirect("stay_list")`.

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

Write-Host "[1/3] Backing up stays\views.py"
Backup-File $views

Write-Host "[2/3] Cleaning malformed conditional return" -ForegroundColor Cyan
$raw = Get-Content -Raw $views

# 1) Replace the weird multi-line conditional return with a single return.
# Matches the specific pattern shown in your error:
$pattern1 = "(?ms)" + `
  "^\s*return\s+redirect\(""stay_list""\)\s*\r?\n" + `
  "\s*redirect\(""stay_list""\)\s*\r?\n" + `
  "\s*if\s+.*?locals\(\)\s*\r?\n" + `
  "\s*else\s+redirect\(""stays_import""\)\s*\r?\n" + `
  "\s*\)\s*"
$fixed = [regex]::Replace($raw, $pattern1, "return redirect(""stay_list"")`r`n")

# 2) As an extra guard: if any stray closing parenthesis sits alone after a return, drop it.
$pattern2 = "(?m)^(?<=return\s+redirect\(""stay_list""\)\s*\r?\n)\s*\)\s*$"
$fixed = [regex]::Replace($fixed, $pattern2, "")

# 3) If a dangling "redirect('stay_list')" line appears with no 'return', fix it.
$pattern3 = "(?m)^\s*redirect\(""stay_list""\)\s*$"
$fixed = [regex]::Replace($fixed, $pattern3, "return redirect(""stay_list"")")

# 4) Normalize indentation: convert tabs to 4 spaces (best-effort).
$fixed = $fixed -replace "`t", "    "

if ($fixed -ne $raw) {
  Set-Content -Path $views -Value $fixed -NoNewline
  Write-Host "  - Cleaned conditional return and stray parens." -ForegroundColor Green
} else {
  Write-Host "  = No conditional-return garbage found; nothing to change."
}

Write-Host "[3/3] Lint/format and quick compile check" -ForegroundColor Cyan
try { ruff --version | Out-Null ; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null ; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

# Quick Python syntax check of the single file
try {
  python - << 'PYCODE'
import py_compile, sys
try:
    py_compile.compile(r"stays/views.py", doraise=True)
    print("  - Python compile check passed for stays/views.py")
except Exception as e:
    print("  ! Python compile error:", e)
    sys.exit(1)
PYCODE
} catch {
  Write-Host "  ! Compile check failed. Open stays\views.py around the edited return lines." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "Now start the server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

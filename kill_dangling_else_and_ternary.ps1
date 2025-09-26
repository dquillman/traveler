# kill_dangling_else_and_ternary.ps1
# Cleans malformed "redirect(...)\nif ...\nelse ..." and stray "else:" in stays\views.py

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
  Write-Host "!! stays\views.py not found." -ForegroundColor Yellow
  exit 1
}

Write-Host "[1/4] Backup stays\views.py"
Backup-File $views

Write-Host "[2/4] Scan and remove malformed blocks..." -ForegroundColor Cyan
$lines = Get-Content $views
$new = New-Object System.Collections.Generic.List[string]
$N = $lines.Count

function IsBlank($s) { return ($s -match '^\s*$') }

for ($i = 0; $i -lt $N; $i++) {
  $line = $lines[$i]

  # A) Kill the specific broken ternary-ish block:
  #    redirect("stay_list")
  #    if "stay_list" in globals() or "stay_list" in locals()
  #    else redirect("stays_import")
  if ($line -match '^\s*redirect\("stay_list"\)\s*$' -and ($i + 2) -lt $N) {
    $ifLine   = $lines[$i + 1]
    $elseLine = $lines[$i + 2]
    if ($ifLine -match '^\s*if\s+"stay_list"\s+in\s+globals\(\).*locals\(\)\s*$' -and `
        $elseLine -match '^\s*else\s+redirect\("stays_import"\)\s*$') {
      # Replace this whole 3-line construct with a single return redirect("stay_list")
      $indent = [regex]::Match($line, '^\s*').Value
      $new.Add($indent + 'return redirect("stay_list")')
      $i += 2
      # Also skip a possible lone ")" on the next line
      if (($i + 1) -lt $N -and $lines[$i + 1] -match '^\s*\)\s*$') { $i += 1 }
      continue
    }
  }

  # B) If we see the older multi-line variant that *starts* with return redirect(), then repeats redirect(), etc.
  if ($line -match '^\s*return\s+redirect\("stay_list"\)\s*$' -and ($i + 3) -lt $N) {
    $l1 = $lines[$i + 1]; $l2 = $lines[$i + 2]; $l3 = $lines[$i + 3]
    if ($l1 -match '^\s*redirect\("stay_list"\)\s*$' -and `
        $l2 -match '^\s*if\s+.+locals\(\)\s*$' -and `
        $l3 -match '^\s*else\s+redirect\("stays_import"\)\s*$') {
      # Keep only the first "return redirect" and skip the rest (+ optional closing paren)
      $new.Add($line)
      $i += 3
      if (($i + 1) -lt $N -and $lines[$i + 1] -match '^\s*\)\s*$') { $i += 1 }
      continue
    }
  }

  # C) Remove a stray lone ')' immediately following a return redirect("stay_list")
  if ($line -match '^\s*\)\s*$' -and $new.Count -gt 0 -and $new[$new.Count - 1] -match '^\s*return\s+redirect\("stay_list"\)\s*$') {
    # skip this ')'
    continue
  }

  # D) Kill a dangling "else:" whose previous *non-blank* line ended with a complete statement (return/closing paren)
  if ($line -match '^\s*else:\s*$') {
    # find previous non-blank in $new
    $prev = $null
    for ($p = $new.Count - 1; $p -ge 0; $p--) {
      if (-not (IsBlank $new[$p])) { $prev = $new[$p]; break }
    }
    if ($prev -ne $null -and ($prev.Trim() -match '^return\b' -or $prev.Trim().EndsWith(')') -or $prev.Trim().EndsWith('}'))) {
      # very likely a dangling else: drop it
      continue
    }
  }

  $new.Add($line)
}

# Normalize tabs -> spaces (best-effort)
for ($k = 0; $k -lt $new.Count; $k++) {
  $new[$k] = $new[$k] -replace "`t", "    "
}

Set-Content -Path $views -Value ($new -join "`r`n") -NoNewline
Write-Host "  - Cleanup pass complete."

Write-Host "[3/4] Syntax check + format" -ForegroundColor Cyan
python -m py_compile stays\views.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! Python compile error still present in stays\views.py" -ForegroundColor Red
  Write-Host "    Open around the last edited area (near return redirect(...)) and check indentation/parentheses."
  exit 1
} else {
  Write-Host "  - Python compile check passed."
}

try { ruff --version | Out-Null; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

Write-Host "[4/4] Done. Start server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

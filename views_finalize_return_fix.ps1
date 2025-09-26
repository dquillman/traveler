# views_finalize_return_fix.ps1
# Repairs dangling "else:" and malformed redirect logic in stays\views.py.
# Also normalizes tabs->spaces and verifies Python compiles.

$ErrorActionPreference = "Stop"

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host "Backup: $Path.bak.$stamp"
  }
}

function IsBlank($s) { return $s -match '^\s*$' }
function IndentOf($s) { return ([regex]::Match($s, '^\s*').Value) }

$views = "stays\views.py"
if (-not (Test-Path $views)) {
  Write-Host "!! stays\views.py not found." -ForegroundColor Yellow
  exit 1
}

Write-Host "[1/5] Backup"
Backup-File $views

# Read lines and keep a copy for diff/snippet
$lines = Get-Content $views
$N = $lines.Count

# Write a before-context around lines 515-545 (if present) to a temp file to help if we need to inspect later
$beforeStart = [Math]::Max(0, [Math]::Min(515, $N) - 10)
$beforeEnd   = [Math]::Min($N - 1, [Math]::Max(545, 0) + 10)
$beforePath  = "stays\views_before_around_520_545.txt"
$ctx = @()
for ($i=$beforeStart; $i -le $beforeEnd; $i++) { $ctx += ("{0,4}: {1}" -f $i, $lines[$i]) }
Set-Content -Path $beforePath -Value ($ctx -join "`r`n") -NoNewline
Write-Host "  - wrote context to $beforePath"

Write-Host "[2/5] Pass A: remove malformed ternary-style redirect blocks and stray ')' ..." -ForegroundColor Cyan
$raw = [string]::Join("`r`n", $lines)

# Normalize tabs -> spaces early to stabilize regex
$raw = $raw -replace "`t", "    "

# A1) Multi-line variant starting with return redirect()
$patA1 = "(?ms)^\s*return\s+redirect\(""stay_list""\)\s*\r?\n\s*redirect\(""stay_list""\)\s*\r?\n\s*if\s+.+?locals\(\)\s*\r?\n\s*else\s+redirect\(""stays_import""\)\s*\r?\n\s*\)\s*"
$raw = [regex]::Replace($raw, $patA1, "return redirect(""stay_list"")`r`n")

# A2) Three-line variant without the initial return
$patA2 = "(?ms)^\s*redirect\(""stay_list""\)\s*\r?\n\s*if\s+.+?locals\(\)\s*\r?\n\s*else\s+redirect\(""stays_import""\)\s*$"
$raw = [regex]::Replace($raw, $patA2, "return redirect(""stay_list"")")

# A3) Single-line variant
$patA3 = "(?m)^\s*redirect\(""stay_list""\)\s+if\s+.+?locals\(\)\s+else\s+redirect\(""stays_import""\)\s*$"
$raw = [regex]::Replace($raw, $patA3, "return redirect(""stay_list"")")

# A4) Lone ')' on its own line after a valid return redirect
$patA4 = "(?m)(?<=return\s+redirect\(""stay_list""\)\s*\r?\n)\s*\)\s*$"
$raw = [regex]::Replace($raw, $patA4, "")

# A5) Replace bare redirect("stay_list") with return redirect("stay_list")
$patA5 = "(?m)^\s*redirect\(""stay_list""\)\s*$"
$raw = [regex]::Replace($raw, $patA5, "return redirect(""stay_list"")")

# Back to array for structural pass
$lines = $raw -split "`r`n"
$N = $lines.Count

Write-Host "[3/5] Pass B: kill dangling 'else:' at a given indent with no matching 'if' ..." -ForegroundColor Cyan
$new = New-Object System.Collections.Generic.List[string]
for ($i=0; $i -lt $N; $i++) {
  $line = $lines[$i]

  if ($line -match '^\s*else:\s*$') {
    $myIndent = IndentOf $line
    # Find previous non-blank line at the same indent
    $prev = $null
    for ($p = $new.Count - 1; $p -ge 0; $p--) {
      if (-not (IsBlank $new[$p])) {
        $prev = $new[$p]
        break
      }
    }
    $dropElse = $true
    if ($prev -ne $null) {
      $prevIndent = IndentOf $prev
      $prevTrim = $prev.Trim()
      # If prior visible line has same indent and is an 'if/elif/except/for/while/try/with' header ending with ':', keep else
      if ($prevIndent -eq $myIndent -and ($prevTrim -match '^(if|elif|except|for|while|try|with)\b.*:\s*$')) {
        $dropElse = $false
      }
    }
    if ($dropElse) {
      # skip this dangling else:
      continue
    }
  }

  $new.Add($line)
}

# Pass C: normalize double blank lines and tabs (again)
for ($k=0; $k -lt $new.Count; $k++) { $new[$k] = $new[$k] -replace "`t","    " }
# Collapse 3+ blank lines to 1
$joined = [string]::Join("`r`n", $new) -replace "(\r?\n\s*){3,}", "`r`n"
Set-Content -Path $views -Value $joined -NoNewline
Write-Host "  - structural cleanup done."

Write-Host "[4/5] Verify Python syntax + Ruff/Black" -ForegroundColor Cyan
python -m py_compile stays\views.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! Python compile error still present." -ForegroundColor Red
  # Dump a fresh after-context around the problematic zone to a file for quick look
  $after = Get-Content stays\views.py
  $n2 = $after.Count
  $start = [Math]::Max(0, [Math]::Min(520, $n2-1) - 20)
  $end   = [Math]::Min($n2-1, [Math]::Max(545, 0) + 20)
  $afterPath = "stays\views_after_around_520_545.txt"
  $ctx2 = @()
  for ($i=$start; $i -le $end; $i++) { $ctx2 += ("{0,4}: {1}" -f $i, $after[$i]) }
  Set-Content -Path $afterPath -Value ($ctx2 -join "`r`n") -NoNewline
  Write-Host "  - wrote context to $afterPath"
  exit 1
}

try { ruff --version | Out-Null; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

Write-Host "[5/5] Done. Start server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

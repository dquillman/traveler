# fix_two_hotspots.ps1
# Repairs: (1) collapsed messages.success + return; (2) bare GET('state') ternary line.

$ErrorActionPreference = "Stop"

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host "Backup: $Path.bak.$stamp"
  }
}

$views = "stays\views.py"
if (!(Test-Path $views)) {
  Write-Host "!! stays\views.py not found" -ForegroundColor Yellow
  exit 1
}

Write-Host "[1/3] Backup"
Backup-File $views

Write-Host "[2/3] Apply targeted fixes..." -ForegroundColor Cyan
$raw = Get-Content -Raw $views

# --- A) Expand single-line messages.success(...) ) return redirect("stay_list") into a proper block
# Match a whole line where messages.success(...) and return redirect(...) were jammed together.
$raw = [regex]::Replace(
  $raw,
  '^(?<ind>\s*)messages\.success\((?<inside>[^)]*)\)\s*return\s+redirect\("stay_list"\)\s*$',
  {
    param($m)
    $ind = $m.Groups['ind'].Value
    $i1  = $ind + (' ' * 4)
    # Rebuild a clean 5-line block using whatever args were inside originally (or fall back to the canonical three lines)
    $inside = $m.Groups['inside'].Value
    if ([string]::IsNullOrWhiteSpace($inside)) {
      $inside = "request,`r`n${i1}f""Import complete. Created {created}, updated {updated}, skipped {skipped}."","
    }
    return ($ind + "messages.success(" + "`r`n" +
            $i1 + $inside.Trim() + "`r`n" +
            $ind + ")" + "`r`n" +
            $ind + "return redirect(""stay_list"")")
  },
  'Multiline'
)

# Also fix a variant that has args on same line but with extra spaces/newlines around them.
$raw = [regex]::Replace(
  $raw,
  '^(?<ind>\s*)messages\.success\(\s*request\s*,\s*f"Import complete\. Created \{created\}, updated \{updated\}, skipped \{skipped\}\."\s*,\s*\)\s*return\s+redirect\("stay_list"\)\s*$',
  {
    param($m)
    $ind = $m.Groups['ind'].Value
    $i1  = $ind + (' ' * 4)
    return ($ind + "messages.success(" + "`r`n" +
            $i1 + "request," + "`r`n" +
            $i1 + 'f"Import complete. Created {created}, updated {updated}, skipped {skipped}.",' + "`r`n" +
            $ind + ")" + "`r`n" +
            $ind + 'return redirect("stay_list")')
  },
  'Multiline'
)

# --- B) Ensure the problematic ternary line parses by adding a trailing comma
$raw = [regex]::Replace(
  $raw,
  '^(?<ind>\s*)\(\[request\.GET\.get\("state"\)\]\s+if\s+request\.GET\.get\("state"\)\s+else\s+\[\]\)\s*$',
  '${ind}([request.GET.get("state")] if request.GET.get("state") else []),',
  'Multiline'
)

# Normalize tabs -> spaces (best effort)
$raw = $raw -replace "`t","    "
Set-Content -Path $views -Value $raw -NoNewline

Write-Host "[3/3] Verify & format" -ForegroundColor Cyan
python -m py_compile stays\views.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! Python compile error still present in stays\views.py" -ForegroundColor Red
  Write-Host "    Showing context around any messages.success occurrences:" -ForegroundColor Red
  $all = Get-Content stays\views.py
  for ($i=0; $i -lt $all.Count; $i++) {
    if ($all[$i] -match '^\s*messages\.success\(') {
      $s = [Math]::Max(0, $i - 8); $e = [Math]::Min($all.Count-1, $i + 12)
      for ($j=$s; $j -le $e; $j++) { Write-Host ("{0,4}: {1}" -f $j, $all[$j]) }
    }
  }
  exit 1
}

try { ruff --version | Out-Null; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

Write-Host ""
Write-Host "All set. Try:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

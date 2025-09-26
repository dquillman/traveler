# view_rescue_final.ps1
# Repairs jammed messages.success/redirect and bare GET('state'/'city') ternary lines in stays\views.py

$ErrorActionPreference = "Stop"

function Backup-File([string]$Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host ("Backup: {0}.bak.{1}" -f $Path, $stamp)
  }
}

$views = "stays\views.py"
if (!(Test-Path $views)) {
  Write-Host "!! stays\views.py not found." -ForegroundColor Yellow
  exit 1
}

Write-Host "[1/4] Backup"
Backup-File $views

Write-Host "[2/4] Apply targeted repairs..." -ForegroundColor Cyan
$raw = Get-Content -Raw $views

# Normalize tabs -> spaces
$raw = $raw -replace "`t","    "

# --- A) Fix bare ternary lines for state/city into proper assignments
$raw = [regex]::Replace(
  $raw,
  '^(?<ind>\s*)\(\[request\.GET\.get\("state"\)\]\s+if\s+request\.GET\.get\("state"\)\s+else\s+\[\]\)\s*$',
  '${ind}states = request.GET.getlist("state") or ([request.GET.get("state")] if request.GET.get("state") else [])',
  'Multiline'
)
$raw = [regex]::Replace(
  $raw,
  '^(?<ind>\s*)\(\[request\.GET\.get\("city"\)\]\s+if\s+request\.GET\.get\("city"\)\s+else\s+\[\]\)\s*$',
  '${ind}cities = request.GET.getlist("city") or ([request.GET.get("city")] if request.GET.get("city") else [])',
  'Multiline'
)

# --- B) Expand jammed "messages.success(...)) return redirect(...)" into a proper block.
# Prefer a second redirect target on same line if present.
$raw = [regex]::Replace(
  $raw,
  '^(?<ind>\s*)messages\.success\((?<inside>[^)]*?)\)\s*return\s+redirect\("(?<first>[^"]+)"\)(?<rest>.*)$',
  {
    param($m)
    $ind   = $m.Groups['ind'].Value
    $i1    = $ind + (' ' * 4)
    $inside= ($m.Groups['inside'].Value).Trim()
    $rest  = $m.Groups['rest'].Value
    $first = $m.Groups['first'].Value

    if ([string]::IsNullOrWhiteSpace($inside)) {
      $inside = "request,`r`n${i1}f""Import complete. Created {created}, updated {updated}, skipped {skipped}."","
    }

    $target = $first
    $m2 = [regex]::Match($rest, 'return\s+redirect\("(?<tgt>[^"]+)"(?:,[^\)]*)?\)')
    if ($m2.Success) { $target = $m2.Groups['tgt'].Value }

    ($ind + "messages.success(" + "`r`n" +
     $i1 + $inside + "`r`n" +
     $ind + ")" + "`r`n" +
     $ind + "return redirect(""" + $target + """)")
  },
  'Multiline'
)

# C) If two return redirects are on one line, keep the second (more specific)
$raw = [regex]::Replace(
  $raw,
  '^(?<ind>\s*)return\s+redirect\("(?<a>[^"]+)"\)\s+return\s+redirect\("(?<b>[^"]+)"(?:,[^\)]*)?\)\s*$',
  '${ind}return redirect("${b}")',
  'Multiline'
)

# D) Remove any remaining lone ")" lines
$raw = [regex]::Replace($raw, '^(?<ind>\s*)\)\s*$', '', 'Multiline')

Set-Content -Path $views -Value $raw -NoNewline

Write-Host "[3/4] Verify & format" -ForegroundColor Cyan
python -m py_compile stays\views.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! Python compile error still present." -ForegroundColor Red
  Write-Host "    Show early-lines context (1..80) to inspect 'state/city' area:" -ForegroundColor DarkYellow
  $all = Get-Content stays\views.py
  $max = [Math]::Min(79, $all.Count - 1)
  for ($i=0; $i -le $max; $i++) { Write-Host ("{0,4}: {1}" -f $i, $all[$i]) }
  Write-Host "    Show around any messages.success blocks:" -ForegroundColor DarkYellow
  for ($i=0; $i -lt $all.Count; $i++) {
    if ($all[$i] -match '^\s*messages\.success\(') {
      $s=[Math]::Max(0,$i-6); $e=[Math]::Min($all.Count-1,$i+10)
      for ($j=$s; $j -le $e; $j++) { Write-Host ("{0,4}: {1}" -f $j, $all[$j]) }
    }
  }
  exit 1
}

try { ruff --version | Out-Null; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

Write-Host "[4/4] Done. Start the server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

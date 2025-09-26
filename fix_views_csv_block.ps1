# fix_views_csv_block.ps1
# Safely replaces the broken try/except CSV-import block in stays\views.py

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

Write-Host "[1/3] Backing up and patching stays\views.py" -ForegroundColor Cyan
Backup-File $views

# Read file as an array of lines (preserves existing CRLF when we write back)
$lines = Get-Content $views
$N = $lines.Count

# Find the 'try:' line whose NEXT line contains nights = int(row.get("nights") or 0)
$start = $null
for ($i = 0; $i -lt $N - 1; $i++) {
  if ($lines[$i].Trim() -eq "try:" -and $lines[$i+1] -match 'nights\s*=\s*int\(\s*row\.get\("nights"\)\s*or\s*0\)') {
    $start = $i
    break
  }
}
if ($null -eq $start) {
  Write-Host "!! Could not locate the broken CSV-import 'try:' block. Aborting." -ForegroundColor Yellow
  exit 1
}

# Determine indentation from the 'try:' line
$indentMatch = [regex]::Match($lines[$start], '^(?<ind>\s*)try:\s*$')
$base = $indentMatch.Groups['ind'].Value
$i1 = $base + (' ' * 4)
$i2 = $base + (' ' * 8)

# Find the end of the broken region: look for messages.success(...) then the next return line
$msg = $null
for ($j = $start; $j -lt $N; $j++) {
  if ($lines[$j] -match 'messages\.success\(') { $msg = $j; break }
}
if ($null -eq $msg) {
  Write-Host "!! Could not find messages.success(...) within the import logic. Aborting." -ForegroundColor Yellow
  exit 1
}

$ret = $null
for ($k = $msg; $k -lt $N; $k++) {
  if ($lines[$k].TrimStart().StartsWith("return")) { $ret = $k; break }
}
if ($null -eq $ret) {
  $ret = $msg
}

# Build a clean replacement block (keep this inside your CSV row loop)
$block = @()
$block += ($base + '# Parse numeric/switch fields safely')
$block += ($base + 'try:')
$block += ($i1  + 'nights = int(row.get("nights") or 0)')
$block += ($base + 'except (TypeError, ValueError):')
$block += ($i1  + 'nights = 0')
$block += ''
$block += ($base + 'try:')
$block += ($i1  + 'rate = float(row.get("rate/nt") or row.get("rate_per_night") or 0)')
$block += ($base + 'except (TypeError, ValueError):')
$block += ($i1  + 'rate = 0.0')
$block += ''
$block += ($base + 'try:')
$block += ($i1  + 'price = float(')
$block += ($i2  + 'row.get("price/night")')
$block += ($i2  + 'or row.get("price_per_night")')
$block += ($i2  + 'or row.get("price")')
$block += ($i2  + 'or 0')
$block += ($i1  + ')')
$block += ($base + 'except (TypeError, ValueError):')
$block += ($i1  + 'price = 0.0')
$block += ''
$block += ($base + 'elect_extra = (row.get("elect extra") or row.get("elect_extra") or "").strip().lower() in {"yes","true","1","y","on","checked"}')
$block += ($base + 'paid = (row.get("paid?") or row.get("paid") or "").strip().lower() in {"yes","true","1","y","paid"}')
$block += ''
$block += ($base + '# Update or create the Stay row')
$block += ($base + 'obj, is_created = Stay.objects.update_or_create(')
$block += ($i1  + 'park=park,')
$block += ($i1  + 'city=city,')
$block += ($i1  + 'state=state,')
$block += ($i1  + 'check_in=check_in,')
$block += ($i1  + 'defaults={')
$block += ($i2  + '"nights": nights,')
$block += ($i2  + '"rate_per_night": rate,')
$block += ($i2  + '"price_per_night": price,')
$block += ($i2  + '"elect_extra": elect_extra,')
$block += ($i2  + '"paid": paid,')
$block += ($i2  + '"site": (row.get("site") or ""),')
$block += ($i2  + '"check_out": check_out,')
$block += ($i1  + '},')
$block += ($base + ')')
$block += ($base + 'created += int(is_created)')
$block += ($base + 'updated += int(not is_created)')
$block += ''
$block += ($base + 'messages.success(')
$block += ($i1  + 'request,')
$block += ($i1  + 'f"Import complete. Created {created}, updated {updated}, skipped {skipped}.",')
$block += ($base + ')')
$block += ($base + 'return redirect("stay_list")')

# Splice the new content in place
$pre  = if ($start -gt 0) { $lines[0..($start-1)] } else { @() }
$post = if ($ret -lt ($N-1)) { $lines[($ret+1)..($N-1)] } else { @() }

$newLines = @()
$newLines += $pre
$newLines += $block
$newLines += $post

Set-Content -Path $views -Value ($newLines -join "`r`n") -NoNewline
Write-Host "  - Replaced malformed CSV-import block." -ForegroundColor Green

Write-Host "[2/3] Migrations" -ForegroundColor Cyan
try { python manage.py makemigrations ; python manage.py migrate } catch { Write-Host "  ! migration warning: $($_.Exception.Message)" -ForegroundColor Yellow }

Write-Host "[3/3] Ruff + Black" -ForegroundColor Cyan
try { ruff --version | Out-Null ; ruff check stays\views.py --fix } catch { Write-Host "  ! install Ruff: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null ; black stays\views.py } catch { Write-Host "  ! install Black: python -m pip install black" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Now start the server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

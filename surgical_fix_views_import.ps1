# surgical_fix_views_import.ps1
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

$lines = Get-Content $views
$N = $lines.Count

# Find the 'try:' line whose next line contains the 'nights = int(row.get("nights")' assignment
$start = $null
for ($i = 0; $i -lt $N - 1; $i++) {
  if ($lines[$i].Trim() -eq "try:" -and $lines[$i+1] -match 'nights\s*=\s*int\(\s*row\.get\("nights"\)') {
    $start = $i
    break
  }
}
if ($null -eq $start) {
  Write-Host "!! Could not locate the broken 'try:' block for nights parsing. Aborting." -ForegroundColor Yellow
  exit 1
}

# Capture base indentation from that 'try:' line
$indentMatch = [regex]::Match($lines[$start], '^(?<ind>\s*)try:\s*$')
$base = $indentMatch.Groups['ind'].Value
$i1 = $base + (' ' * 4)
$i2 = $base + (' ' * 8)

# Find the end of the bad region: search forward for messages.success(...) and then its subsequent return line
$msg = $null
for ($j = $start; $j -lt $N; $j++) {
  if ($lines[$j] -match 'messages\.success\(') { $msg = $j; break }
}
if ($null -eq $msg) {
  Write-Host "!! Could not find messages.success(...) within the import loop. Aborting." -ForegroundColor Yellow
  exit 1
}

$ret = $null
for ($k = $msg; $k -lt $N; $k++) {
  if ($lines[$k].TrimStart().StartsWith("return")) { $ret = $k; break }
}
if ($null -eq $ret) {
  # If no explicit return is found, just end at the messages.success block
  $ret = $msg
}

# Build a clean replacement block
$block = @()
$block += "$base# Parse numeric/switch fields safely"
$block += "$base" + "try:"
$block += "$i1" + "nights = int(row.get(""nights"") or 0)"
$block += "$base" + "except (TypeError, ValueError):"
$block += "$i1" + "nights = 0"
$block += ""
$block += "$base" + "try:"
$block += "$i1" + "rate = float(row.get(""rate/nt"") or row.get(""rate_per_night"") or 0)"
$block += "$base" + "except (TypeError, ValueError):"
$block += "$i1" + "rate = 0.0"
$block += ""
$block += "$base" + "try:"
$block += "$i1" + "price = float("
$block += "$i2" + "row.get(""price/night"")"
$block += "$i2" + "or row.get(""price_per_night"")"
$block += "$i2" + "or row.get(""price"")"
$block += "$i2" + "or 0"
$block += "$i1" + ")"
$block += "$base" + "except (TypeError, ValueError):"
$block += "$i1" + "price = 0.0"
$block += ""
$block += "$base" + "elect_extra = (row.get(""elect extra"") or row.get(""elect_extra"") or """").strip().lower() in {""yes"",""true"",""1"",""y"",""on"",""checked""}"
$block += "$base" + "paid = (row.get(""paid?"") or row.get(""paid"") or """").strip().lower() in {""yes"",""true"",""1"",""y"",""paid""}"
$block += ""
$block += "$base" + "# Update or create the Stay row"
$block += "$base" + "obj, is_created = Stay.objects.update_or_create("
$block += "$i1" + "park=park,"
$block += "$i1" + "city=city,"
$block += "$i1" + "state=state,"
$block += "$i1" + "check_in=check_in,"
$block += "$i1" + "defaults={"
$block += "$i2" + @"""nights"": nights,"@
$block += "$i2" + @"""rate_per_night"": rate,"@
$block += "$i2" + @"""price_per_night"": price,"@
$block += "$i2" +

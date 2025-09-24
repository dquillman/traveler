# remove_lower_nav_anywhere.ps1
# Keeps the first <nav> near the top and removes the second one if it appears
# before <main> (or within the first 5000 chars). Backs up each edited file.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateRoot = Join-Path $root 'templates'

if (-not (Test-Path $templateRoot)) {
  Write-Host "Templates folder not found: $templateRoot" -ForegroundColor Red
  exit 1
}

$targets = Get-ChildItem -Path $templateRoot -Recurse -Include *.html -File
if (-not $targets) {
  Write-Host "No .html files found under $templateRoot" -ForegroundColor Yellow
  exit 0
}

# Match any <nav ...> ... </nav> (non-greedy)
$navRegex = [regex]'(?is)<nav\b[^>]*?>.*?</nav>'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

$changed = 0
$skipped = 0
$backedUp = 0

foreach ($f in $targets) {
  $html = Get-Content -Path $f.FullName -Raw
  if ([string]::IsNullOrWhiteSpace($html)) { $skipped++; continue }

  # Limit for “top of page” area
  $preMainIdx = $html.IndexOf('<main', [StringComparison]::OrdinalIgnoreCase)
  if ($preMainIdx -lt 0) { $preMainIdx = [Math]::Min($html.Length, 5000) }

  # Find all navs and keep those located before the limit
  $matches = $navRegex.Matches($html) | Where-Object { $_.Index -lt $preMainIdx }

  if ($matches.Count -ge 2) {
    # Keep first nav, remove the second
    $second = $matches[1]
    $start = $second.Index
    $len   = $second.Length

    $before = $html.Substring(0, $start)
    $after  = $html.Substring($start + $len)

    $newHtml = $before + $after

    if ($newHtml -ne $html) {
      $bak = "$($f.FullName).bak.$ts"
      if (-not (Test-Path $bak)) { Copy-Item $f.FullName $bak; $backedUp++ }
      Set-Content -Path $f.FullName -Value $newHtml -Encoding UTF8
      Write-Host "Removed lower nav in: $($f.FullName)"
      $changed++
      continue
    }
  }

  $skipped++
}

Write-Host ""
Write-Host "Backups created: $backedUp" -ForegroundColor Cyan
Write-Host "Files changed:   $changed"  -ForegroundColor Green
Write-Host "Files skipped:   $skipped"  -ForegroundColor DarkGray
Write-Host ""
Write-Host "All done. Restart Django and hard-refresh (Ctrl+F5)." -ForegroundColor Green

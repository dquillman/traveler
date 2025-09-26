# fix_codex_findings.ps1 (paste into shell directly)

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

# 1) stays/views.py — remove 'price_per_night' from defaults
$views = ".\stays\views.py"
if (Test-Path $views) {
  Copy-Item $views "$views.bak.$ts"
  $txt = Get-Content $views -Raw
  # Remove ",'price_per_night': something" inside defaults dicts
  $txt = $txt -replace "(\s*['""]price_per_night['""]\s*:\s*[^,}\r\n]+,\s*)", ""
  Set-Content $views $txt -Encoding UTF8
  Write-Host "Patched: stays/views.py (removed price_per_night from defaults)" -ForegroundColor Green
} else { Write-Host "Skip: stays/views.py not found" -ForegroundColor Yellow }

# 2) stays/urls.py — drop early duplicate import/export routes that shadow later ones
$urls = ".\stays\urls.py"
if (Test-Path $urls) {
  Copy-Item $urls "$urls.bak.$ts"
  $u = Get-Content $urls -Raw

  # Heuristic: remove earlier import/export patterns that point to older views
  # Comment out lines with path('import/', views.import_view, ...) and path('export/', views.export_view, ...)
  $u = $u -replace "(?m)^\s*path\(\s*['""]import/['""]\s*,\s*views\.import_view\s*,.*\)\s*,?\s*$", "# [removed dup] \`$0"
  $u = $u -replace "(?m)^\s*path\(\s*['""]export/['""]\s*,\s*views\.export_view\s*,.*\)\s*,?\s*$", "# [removed dup] \`$0"

  Set-Content $urls $u -Encoding UTF8
  Write-Host "Patched: stays/urls.py (commented duplicate import/export routes)" -ForegroundColor Green
} else { Write-Host "Skip: stays/urls.py not found" -ForegroundColor Yellow }

Write-Host "`nRun tests:" -ForegroundColor Cyan
Write-Host "  python manage.py check" -ForegroundColor Cyan
Write-Host "  python manage.py runserver" -ForegroundColor Cyan

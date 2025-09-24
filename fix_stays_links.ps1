# fix_stays_links.ps1 — replace broken {% url %} tags with direct hrefs
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$tpl = ".\templates\stays\stay_list.html"
if (-not (Test-Path $tpl)) { Write-Host "Not found: $tpl" -ForegroundColor Red; exit 1 }
Copy-Item $tpl "$tpl.bak.$ts"

# Replace {% url 'stay_detail' stay.id %} -> /stays/{{ stay.id }}/
# Replace {% url 'stay_edit' stay.id %}   -> /stays/{{ stay.id }}/edit/
(Get-Content $tpl -Raw) `
  -replace '\{\%\s*url\s+[''"]stay_detail[''"]\s+([^\%]+)\%\}', '/stays/{{ stay.id }}/' `
  -replace '\{\%\s*url\s+[''"]stay_edit[''"]\s+([^\%]+)\%\}',   '/stays/{{ stay.id }}/edit/' `
| Set-Content $tpl -Encoding UTF8

Write-Host "Patched links in $tpl" -ForegroundColor Green
Write-Host "Backup: $tpl.bak.$ts" -ForegroundColor DarkGray

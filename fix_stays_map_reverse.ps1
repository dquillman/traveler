# fix_stays_map_reverse.ps1
$ErrorActionPreference = "Stop"

# --- 1) Patch template fetch() to be namespace-agnostic and have a hard fallback ---
$tplPath = "templates\stays\stay_list.html"
if (-not (Test-Path $tplPath)) { throw "Template not found: $tplPath" }
$tpl = Get-Content $tplPath -Raw

$patched = $false

# Replace {% url 'stays_map_data' %} usage inside fetch("...")+q) with as-var + fallback
$block = @"
{% url 'stays_map_data' as map_url %}
{% if not map_url %}{% url 'stays:stays_map_data' as map_url %}{% endif %}
fetch("{{ map_url|default:'/stays/map-data/' }}" + q)
"@

# Handle single or double quoted variants
$re1 = '(?s)fetch\(\s*"{%\s*url\s+''stays_map_data''\s*%}"\s*\+\s*q\s*\)'
$re2 = '(?s)fetch\(\s*"{%\s*url\s+""stays_map_data""\s*%}"\s*\+\s*q\s*\)'

if ($tpl -match $re1) { $tpl = $tpl -replace $re1, $block; $patched = $true }
if ($tpl -match $re2) { $tpl = $tpl -replace $re2, $block; $patched = $true }

if ($patched) {
  Set-Content $tplPath $tpl -Encoding UTF8
  Write-Host "Patched template: $tplPath"
} else {
  Write-Host "No direct {% url 'stays_map_data' %} fetch() pattern found in template; skipping template patch."
}

# --- 2) Ensure stays/urls.py has the map-data route name='stays_map_data' ---
$urlsPath = "stays\urls.py"
if (-not (Test-Path $urlsPath)) { throw "File not found: $urlsPath" }
$urls = Get-Content $urlsPath -Raw

if ($urls -notmatch "name=['""]stays_map_data['""]") {
  if ($urls -match "urlpatterns\s*=\s*\[") {
    $urls = $urls -replace "urlpatterns\s*=\s*\[", "urlpatterns = [`r`n    path('map-data/', views.stays_map_data, name='stays_map_data'),"
    Set-Content $urlsPath $urls -Encoding UTF8
    Write-Host "Inserted stays_map_data route in stays/urls.py"
  } else {
    Write-Host "Could not locate urlpatterns = [ ... ] in stays/urls.py"
  }
} else {
  Write-Host "stays_map_data already present in stays/urls.py"
}

# --- 3) Ensure app_name = 'stays' exists (works with namespacing includes) ---
$urls = Get-Content $urlsPath -Raw
if ($urls -notmatch "app_name\s*=\s*['""]stays['""]") {
  # Insert after import line; if not present, just prepend
  if ($urls -match "from\s+django\.urls\s+import\s+path") {
    $urls = $urls -replace "from\s+django\.urls\s+import\s+path", "from django.urls import path`r`napp_name = 'stays'"
  } else {
    $urls = "app_name = 'stays'`r`n" + $urls
  }
  Set-Content $urlsPath $urls -Encoding UTF8
  Write-Host "Added app_name = 'stays' to stays/urls.py"
} else {
  Write-Host "app_name already set in stays/urls.py"
}

Write-Host ""
Write-Host "Done. If the dev server is running, restart it."

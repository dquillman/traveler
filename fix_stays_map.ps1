param(
  # Repo root; defaults to the folder containing this script
  [string]$Root = $PSScriptRoot
)

# fix_stays_map.ps1
# ----------------------------------------------------------------------
# What this does:
# 1) Patches templates\stays\stay_list.html:
#    - Replaces the namespace-agnostic IIFE block with:
#        var mapDataUrl = "{% url 'stays:stays_map_data' %}";
#    - Normalizes any non-namespaced {% url 'stays_map_data' %} -> namespaced
#    - Converts {{ map_url }} to namespaced {% url %} directly
# 2) Patches stays\urls.py:
#    - Ensures imports exist
#    - Ensures app_name = "stays"
#    - Ensures path("map-data/", views.stays_map_data, name="stays_map_data")
# 3) Leaves .bak backups next to changed files.
#
# Usage:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\fix_stays_map.ps1                   # from repo root
#   .\fix_stays_map.ps1 -Root .           # explicit
#
# After running:
#   python manage.py shell -c "from django.urls import reverse; print(reverse('stays:stays_map_data'))"
#   # Expect: /stays/map-data/
#   python manage.py runserver
# ----------------------------------------------------------------------

$ErrorActionPreference = "Stop"

function Backup-And-Write([string]$Path, [string]$Content) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "File not found: $Path"
  }
  $orig = Get-Content -Raw -LiteralPath $Path
  if ($orig -ne $Content) {
    $bak = "$Path.bak"
    Set-Content -NoNewline -LiteralPath $bak -Value $orig
    Set-Content -NoNewline -LiteralPath $Path -Value $Content
    Write-Host "Patched: $Path  (backup at $bak)"
  } else {
    Write-Host "No changes needed: $Path"
  }
}

# ---------- 1) Patch the map script in stay_list.html ----------
$templatePath = Join-Path $Root "templates\stays\stay_list.html"
if (Test-Path -LiteralPath $templatePath) {
  $tpl = Get-Content -Raw -LiteralPath $templatePath
  $origTpl = $tpl

  # Replace the namespace-agnostic IIFE with a single assignment
  $patternIife = [regex]::new('var\s+mapDataUrl\s*=\s*\(function\(\)\s*\)\s*\{\s*.*?\s*\}\s*\(\s*\)\s*;', 'Singleline,IgnoreCase')
  $tpl = $patternIife.Replace($tpl, 'var mapDataUrl = "{% url ''stays:stays_map_data'' %}";')

  # Normalize any remaining non-namespaced url tags
  $tpl = $tpl -replace "\{\%\s*url\s+'stays_map_data'\s*\%\}", "{% url 'stays:stays_map_data' %}"
  $tpl = $tpl -replace '\{\%\s*url\s+"stays_map_data"\s*\%\}', "{% url 'stays:stays_map_data' %}"

  # Replace {{ map_url }} with namespaced {% url %}
  $tpl = $tpl -replace "\{\{\s*map_url\s*\}\}", "{% url 'stays:stays_map_data' %}"

  Backup-And-Write -Path $templatePath -Content $tpl
} else {
  Write-Warning "Template not found: $templatePath (skipping template patch)"
}

# ---------- 2) Patch stays/urls.py ----------
$urlsPath = Join-Path $Root "stays\urls.py"
if (Test-Path -LiteralPath $urlsPath) {
  $urls = Get-Content -Raw -LiteralPath $urlsPath
  $origUrls = $urls

  # Ensure imports: from django.urls import path
  if ($urls -notmatch 'from\s+django\.urls\s+import\s+path') {
    # insert near top
    if ($urls -match '^(from\s+\.\s+import\s+view

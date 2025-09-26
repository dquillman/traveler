# add_stub_pages.ps1
$ErrorActionPreference = "Stop"

# Paths
$urls = "stays\urls.py"
$views = "stays\views.py"
$tplDir = "templates\stays"

# Backups
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
if (Test-Path $urls) { Copy-Item $urls "$urls.bak.$ts" -Force; Write-Host "Backup: $urls.bak.$ts" }
if (Test-Path $views) { Copy-Item $views "$views.bak.$ts" -Force; Write-Host "Backup: $views.bak.$ts" }

# Ensure template dir
if (-not (Test-Path $tplDir)) { New-Item -ItemType Directory -Path $tplDir -Force | Out-Null; Write-Host "Created $tplDir" }

# ---------- Ensure URL patterns ----------
$urlsContent = Get-Content -Raw -Encoding UTF8 $urls

# If file missing minimal header, write a clean header first
if ($urlsContent -notmatch "(?m)from\s+django\.urls\s+import\s+path") {
$urlsHeader = @'
from django.urls import path
from . import views

app_name = "stays"

urlpatterns = [
    path("", views.stay_list, name="list"),
    path("add/", views.stay_add, name="add"),
    path("<int:pk>/edit/", views.stay_edit, name="edit"),
    path("map-data/", views.stays_map_data, name="map_data"),
]
'@
Set-Content -Path $urls -Value $urlsHeader -Encoding UTF8
$urlsContent = Get-Content -Raw -Encoding UTF8 $urls
Write-Host "Wrote clean base stays/urls.py"
}

function Ensure-Url {
    param([string]$Pattern, [string]$LineToAdd)
    $global:urlsContent = Get-Content -Raw -Encoding UTF8 $urls
    if ($global:urlsContent -notmatch [regex]::Escape($Pattern)) {
        $global:urlsContent = $global:urlsContent -replace '(?ms)urlpatterns\s*=\s*\[\s*', ('urlpatterns = [' + "`r`n    " + $LineToAdd + "," + "`r`n    ")
        Set-Content -Path $urls -Value $global:urlsContent -Encoding UTF8
        Write-Host ("Added URL: {0}" -f $Pattern)
    }
}

Ensure-Url 'path\("charts/"'     'path("charts/", views.stays_charts, name="charts")'
Ensure-Url 'path\("import/"'     'path("import/", views.stays_import, name="import")'
Ensure-Url 'path\("export/"'     'path("export/", views.stays_export, name="export")'
Ensure-Url 'path\("appearance/"' 'path("appearance/", views.stays_appearance, name="appearance")'
Ensure-Url 'path\("map/"'        'path("map/", views.stays_map, name="map")'

# ---------- Ensure view stubs in views.py ----------
$viewsText = Get-Content -Raw -Encoding UTF8 $views

# Make sure imports exist
if ($viewsText -notmatch "(?m)from\s+django\.shortcuts\s+import\s+render") {
    $viewsText = "from django.shortcuts import render" + "`r`n" + $viewsText
}
if ($viewsText -notmatch "(?m)from\s+django\.http\s+import\s+JsonResponse") {
    $viewsText = "from django.http import JsonResponse" + "`r`n" + $viewsText
}
Set-Content -Path $views -Value $viewsText -Encoding UTF8
$viewsText = Get-Content -Raw -Encoding UTF8 $views

function Ensure-View {
    param([string]$FuncName, [string]$Block)
    $txt = Get-Content -Raw -Encoding UTF8 $views
    $pat = "(?ms)^\s*def\s+$([regex]::Escape($FuncName))\s*\("
    if ($txt -notmatch $pat) {
        Add-Content -Path $views -Value "`r`n`r`n$Block" -Encoding UTF8
        Write-Host ("Added view: {0}" -f $FuncName)
    }
}

$view_charts = @'
def stays_charts(request):
    # TODO: Replace with real charts. Minimal page to avoid 404.
    return render(request, "stays/charts.html", {})
'@

$view_import = @'
def stays_import(request):
    # TODO: Replace with real import flow. Minimal page to avoid 404.
    return render(request, "stays/import.html", {})
'@

$view_export = @'
def stays_export(request):
    # TODO: Replace with real export flow. Minimal page to avoid 404.
    return render(request, "stays/export.html", {})
'@

$view_appearance = @'
def stays_appearance(request):
    # TODO: Replace with real appearance settings page. Minimal page to avoid 404.
    return render(request, "stays/appearance.html", {})
'@

$view_map = @'
def stays_map(request):
    # Minimal map page placeholder; fetches JSON from /stays/map-data/
    return render(request, "stays/map.html", {})
'@

Ensure-View "stays_charts"     $view_charts
Ensure-View "stays_import"     $view_import
Ensure-View "stays_export"     $view_export
Ensure-View "stays_appearance" $view_appearance
Ensure-View "stays_map"        $view_map

# ---------- Minimal templates ----------
$tplCharts = Join-Path $tplDir "charts.html"
$tplImport = Join-Path $tplDir "import.html"
$tplExport = Join-Path $tplDir "export.html"
$tplAppear = Join-Path $tplDir "appearance.html"
$tplMap    = Join-Path $tplDir "map.html"

function Write-IfMissing {
    param([string]$Path, [string]$Content)
    if (-not (Test-Path $Path)) {
        Set-Content -Path $Path -Value $Content -Encoding UTF8
        Write-Host ("Wrote {0}" -f $Path)
    }
}

$baseHtml = @'
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Stays</title></head>
  <body>
    <nav>
      <a href="/stays/">List</a> |
      <a href="/stays/add/">Add</a> |
      <a href="/stays/map/">Map</a> |
      <a href="/stays/charts/">Charts</a> |
      <a href="/stays/import/">Import</a> |
      <a href="/stays/export/">Export</a> |
      <a href="/stays/appearance/">Appearance</a>
    </nav>
    <hr>
    <h1>{{ title }}</h1>
    <div>
      {{ content|default:"" }}
    </div>
  </body>
</html>
'@

$chartsHtml = @'
{% with title="Charts" %}{% include "stays/_base_stub.html" %}{% endwith %}
'@

$importHtml = @'
{% with title="Import" %}{% include "stays/_base_stub.html" %}{% endwith %}
'@

$exportHtml = @'
{% with title="Export" %}{% include "stays/_base_stub.html" %}{% endwith %}
'@

$appearHtml = @'
{% with title="Appearance" %}{% include "stays/_base_stub.html" %}{% endwith %}
'@

$mapHtml = @'
{% with title="Map" %}
{% include "stays/_base_stub.html" %}
<script>
fetch("/stays/map-data/").then(r=>r.json()).then(d=>{
  console.log("stays:", d);
  const div=document.createElement("pre");
  div.textContent = JSON.stringify(d, null, 2);
  document.body.appendChild(div);
});
</script>
{% endwith %}
'@

# Write a small shared base used by stubs
$tplBase = Join-Path $tplDir "_base_stub.html"
Write-IfMissing $tplBase $baseHtml
Write-IfMissing $tplCharts $chartsHtml
Write-IfMissing $tplImport $importHtml
Write-IfMissing $tplExport $exportHtml
Write-IfMissing $tplAppear $appearHtml
Write-IfMissing $tplMap    $mapHtml

Write-Host "Done. Restart server: python manage.py runserver"
Write-Host "Pages:"
Write-Host "  /stays/charts/     /stays/import/   /stays/export/   /stays/appearance/   /stays/map/"

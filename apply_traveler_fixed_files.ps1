<# =====================================================================
 apply_traveler_fixed_files.ps1
 • Overwrites specific files with known-good content (UTF-8 no BOM)
 • Ensures /stays/ routes (map-data, charts, import, export) work
 • Creates minimal templates and a dark, modern charts page
 • Adds /appearance/ at project level
 • Backs up anything it overwrites
===================================================================== #>

param(
  [string]$ProjectRoot = $PSScriptRoot
)

# ---------- helpers ----------
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
function Backup([string]$p){ if(Test-Path $p){ Copy-Item $p "$p.bak.$stamp" -Force; Write-Host "Backup: $p.bak.$stamp" } }
function WriteUtf8([string]$p,[string]$t){ [IO.File]::WriteAllText($p, $t, [Text.UTF8Encoding]::new($false)) }
function EnsureDir([string]$p){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

# ---------- paths ----------
$staysUrls  = Join-Path $ProjectRoot "stays\urls.py"
$staysViews = Join-Path $ProjectRoot "stays\views.py"

$tplDir       = Join-Path $ProjectRoot "templates"
$tplStaysDir  = Join-Path $tplDir "stays"
$stayListTpl  = Join-Path $tplStaysDir "stay_list.html"
$chartsTpl    = Join-Path $tplStaysDir "charts.html"
$importTpl    = Join-Path $tplStaysDir "import.html"
$exportTpl    = Join-Path $tplStaysDir "export.html"
$appearanceTpl= Join-Path $tplDir "appearance.html"

EnsureDir $tplDir
EnsureDir $tplStaysDir

# ---------- content (known-good) ----------

$urls_py = @'
from django.urls import path
from . import views

urlpatterns = [
    path("", views.stay_list, name="stay_list"),
    path("add/", views.stay_add, name="stay_add"),
    path("edit/<int:pk>/", views.stay_edit, name="stay_edit"),
    path("map-data/", views.stays_map_data, name="stays_map_data"),
    path("charts/", views.stays_charts, name="stays_charts"),
    path("import/", views.stays_import, name="stays_import"),
    path("export/", views.stays_export, name="stays_export"),
]
'@

$views_py = @'
from django.shortcuts import render
from django.http import JsonResponse
from django.urls import reverse
from django.db.models import Count
from .models import Stay

def stays_map_data(request):
    items = []
    for s in Stay.objects.all():
        lat = getattr(s, "latitude", None)
        lng = getattr(s, "longitude", None)
        try:
            lat = float(lat) if lat is not None else None
            lng = float(lng) if lng is not None else None
        except (TypeError, ValueError):
            lat = None
            lng = None
        items.append({
            "id": s.id,
            "label": s.label or "",
            "latitude": lat,
            "longitude": lng,
            "popup_html": f"<strong>{s.label or 'Stay'}</strong><br>{(s.city or '')}, {(s.state or '')}",
            "detail_url": reverse("stay_edit", args=[s.id]),
        })
    return JsonResponse({"stays": items})

def stays_charts(request):
    qs = (Stay.objects
          .values('state')
          .annotate(count=Count('id'))
          .order_by('state'))
    labels = [x['state'] or '—' for x in qs]
    counts = [x['count'] for x in qs]
    return render(request, "stays/charts.html", {"labels": labels, "counts": counts})

def stays_import(request):
    return render(request, "stays/import.html", {})

def stays_export(request):
    return render(request, "stays/export.html", {})

# The following are expected to already exist in your app:
#   stay_list, stay_add, stay_edit (used by urls above)
# If they don't, your app will tell you on server start.

def appearance(request):
    return render(request, "appearance.html", {})
'@

$stay_list_html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Traveler &bull; Stays</title>
  <link rel="icon" href="/static/favicon.ico" sizes="any">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin="">
  <style>
    :root { --bg:#0f1220; --card:#161a2b; --ink:#e8ebff; --muted:#9aa4d2; --line:#272b41; --accent:#b9c6ff; }
    *{box-sizing:border-box}
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Arial; margin:0; background:var(--bg); color:var(--ink); }
    header { padding:14px 18px; background:#101425; color:#fff; display:flex; align-items:center; gap:16px; }
    header .brand { font-weight:700; }
    header nav a { color:var(--accent); text-decoration:none; margin-right:14px; }
    .wrap { max-width:1200px; margin:0 auto; padding:16px; }
    .panel { background:var(--card); border:1px solid var(--line); border-radius:14px; box-shadow:0 8px 24px rgba(0,0,0,.25); }
    #map { width:100%; height:460px; border-radius:14px; background:#0a0d18; }
    table { width:100%; border-collapse:collapse; background:var(--card); border-radius:14px; overflow:hidden; border:1px solid var(--line); }
    th, td { padding:10px 12px; border-bottom:1px solid var(--line); }
    th { text-align:left; color:var(--muted); font-weight:600; background:#12162a; }
    .button { display:inline-block; margin-top:8px; padding:8px 12px; border-radius:10px; border:1px solid var(--line); color:var(--ink); text-decoration:none; background:#1c2040; }
    .muted { color: var(--muted); }
  </style>
</head>
<body>
  <header>
    <div class="brand">Traveler</div>
    <nav>
      <a href="/stays/">Stays</a>
      <a href="/stays/add/">Add</a>
      <a href="/stays/#map">Map</a>
      <a href="/stays/charts/">Charts</a>
      <a href="/stays/import/">Import</a>
      <a href="/stays/export/">Export</a>
      <a href="/appearance/">Appearance</a>
    </nav>
  </header>

  <div class="wrap">
    <div class="panel" style="padding:12px; margin-bottom:16px;">
      <div id="map"></div>
      <p class="muted" style="margin:8px 4px 0;">Pins load from <code>/stays/map-data/</code>.</p>
      <div id="map-status" class="muted" style="margin:8px 4px 0;"></div>
    </div>

    {% comment %} Your table rendering below remains as-is; Django will fill it {% endcomment %}
    {% block content_table %}{% endblock %}
  </div>

  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin=""></script>
  <script>
  (function(){
    var map = L.map('map');
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 18, attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    var q = window.location.search || '';
    var mapDataUrl = "/stays/map-data/";
    var statusEl = document.getElementById('map-status');

    fetch(mapDataUrl + q)
      .then(function(r){ if(!r.ok) throw new Error('HTTP '+r.status); return r.json(); })
      .then(function(j){
        var stays = (j && j.stays) ? j.stays : [];
        var group = L.featureGroup();
        stays.forEach(function(s){
          if (s.latitude != null && s.longitude != null) {
            var html = s.popup_html || '';
            if (s.detail_url) { html += '<br><a href="' + s.detail_url + '">Open / Edit</a>'; }
            var m = L.marker([s.latitude, s.longitude]).bindPopup(html);
            group.addLayer(m);
          }
        });
        if (group.getLayers().length) {
          group.addTo(map);
          map.fitBounds(group.getBounds(), { padding: [20,20] });
          statusEl.textContent = '';
        } else {
          map.setView([39.5, -98.35], 4);
          statusEl.textContent = 'No mappable stays yet (add a stay with latitude & longitude).';
        }
      })
      .catch(function(err){
        console.error('Map data error', err);
        map.setView([39.5, -98.35], 4);
        statusEl.textContent = 'Could not load map data: ' + err.message + ' (open /stays/map-data/ to debug).';
      });
  })();
  </script>
</body>
</html>
'@

$charts_html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Traveler &bull; Charts</title>
  <link rel="icon" href="/static/favicon.ico" sizes="any">
  <style>
    :root { --bg:#0f1220; --card:#161a2b; --ink:#e8ebff; --muted:#9aa4d2; --line:#272b41; --accent:#b9c6ff; }
    *{box-sizing:border-box}
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Arial; margin:0; background:var(--bg); color:var(--ink); }
    header { padding:14px 18px; background:#101425; color:#fff; display:flex; align-items:center; gap:16px; }
    header .brand { font-weight:700; }
    header nav a { color:var(--accent); text-decoration:none; margin-right:14px; }
    .wrap { max-width:1200px; margin:0 auto; padding:16px; }
    .panel { background:var(--card); border:1px solid var(--line); border-radius:14px; box-shadow:0 8px 24px rgba(0,0,0,.25); padding:16px; }
  </style>
</head>
<body>
  <header>
    <div class="brand">Traveler</div>
    <nav>
      <a href="/stays/">Stays</a>
      <a href="/stays/add/">Add</a>
      <a href="/stays/#map">Map</a>
      <a href="/stays/charts/">Charts</a>
      <a href="/stays/import/">Import</a>
      <a href="/stays/export/">Export</a>
      <a href="/appearance/">Appearance</a>
    </nav>
  </header>

  <div class="wrap">
    <div class="panel">
      <h1>Stays by State</h1>
      <canvas id="c1" height="120"></canvas>
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
  <script>
    (function(){
      const labels = JSON.parse('{{ labels|safe|escapejs }}');
      const counts = JSON.parse('{{ counts|safe|escapejs }}');
      const ctx = document.getElementById('c1').getContext('2d');
      new Chart(ctx, {
        type: 'bar',
        data: { labels: labels, datasets: [{ label: 'Stays', data: counts }] },
        options: {
          plugins:{ legend:{ labels:{ color:'#e8ebff' } } },
          scales:{
            x:{ ticks:{ color:'#9aa4d2' }, grid:{ color:'#272b41' } },
            y:{ ticks:{ color:'#9aa4d2' }, grid:{ color:'#272b41' }, beginAtZero:true }
          }
        }
      });
    })();
  </script>
</body>
</html>
'@

$import_html = @'
<!doctype html><meta charset="utf-8">
<title>Traveler &bull; Import</title>
<style>:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Arial}.wrap{max-width:1200px;margin:0 auto;padding:16px}.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px}</style>
<div class="wrap"><div class="panel"><h1>Import</h1><p class="muted">Stub page. CSV form goes here.</p></div></div>
'@

$export_html = @'
<!doctype html><meta charset="utf-8">
<title>Traveler &bull; Export</title>
<style>:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Arial}.wrap{max-width:1200px;margin:0 auto;padding:16px}.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px}</style>
<div class="wrap"><div class="panel"><h1>Export</h1><p class="muted">Stub page. Download links go here.</p></div></div>
'@

$appearance_html = @'
<!doctype html><meta charset="utf-8">
<title>Traveler &bull; Appearance</title>
<style>:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Arial}.wrap{max-width:1200px;margin:0 auto;padding:16px}.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px}</style>
<div class="wrap"><div class="panel"><h1>Appearance</h1><p class="muted">Theme settings will go here.</p></div></div>
'@

# ---------- write files ----------
foreach($pair in @(
  @($staysUrls,  $urls_py),
  @($staysViews, $views_py),
  @($stayListTpl,$stay_list_html),
  @($chartsTpl,  $charts_html),
  @($importTpl,  $import_html),
  @($exportTpl,  $export_html),
  @($appearanceTpl,$appearance_html)
)){
  $path = $pair[0]; $text = $pair[1]
  if(Test-Path $path){ Backup $path }
  WriteUtf8 $path $text
  Write-Host "Wrote:  $path"
}

# ---------- project-level urls.py: add /stays/ include + /appearance/ ----------
# find a settings.py and sibling urls.py
$projUrls = $null
$settings = Get-ChildItem $ProjectRoot -Recurse -Filter settings.py -ErrorAction SilentlyContinue | Select-Object -First 1
if($settings){
  $projDir = Split-Path $settings.FullName -Parent
  $candidate = Join-Path $projDir "urls.py"
  if(Test-Path $candidate){ $projUrls = $candidate }
}
if($projUrls){
  $u = Get-Content $projUrls -Raw
  $orig = $u
  if($u -notmatch 'from\s+django\.urls\s+import\s+path,\s*include'){
    if($u -match 'from\s+django\.urls\s+import\s+path'){
      $u = $u -replace 'from\s+django\.urls\s+import\s+path', 'from django.urls import path, include'
    } else {
      $u = "from django.urls import path, include`r`n" + $u
    }
  }
  if($u -notmatch 'from\s+stays\s+import\s+views\s+as\s+stays_views'){
    $u = "from stays import views as stays_views`r`n" + $u
  }
  if($u -notmatch 'urlpatterns\s*='){
    $u += "`r`nurlpatterns = []`r`n"
  }
  if($u -notmatch 'include\(\s*"stays\.urls"\s*\)'){
    $u = $u -replace 'urlpatterns\s*=\s*\[', "urlpatterns = [" + "`r`n    path(""stays/"", include(""stays.urls"")),"
  }
  if($u -notmatch 'appearance.*stays_views\.appearance'){
    $u = $u -replace 'urlpatterns\s*=\s*\[', "urlpatterns = [" + "`r`n    path(""appearance/"", stays_views.appearance, name=""appearance""),"
  }
  if($u -ne $orig){
    Backup $projUrls
    WriteUtf8 $projUrls $u
    Write-Host "Updated project urls: $projUrls"
  } else {
    Write-Host "Project urls already had stays/include + appearance."
  }
} else {
  Write-Warning "Could not auto-locate project urls.py (next to settings.py). If /stays/ 404s, tell me that file path."
}

Write-Host "`nAll set. If you want a test pin, run:"
Write-Host 'python manage.py shell -c "from stays.models import Stay; Stay.objects.create(label=''Test Pin'', city=''Chicago'', state=''IL'', latitude=41.8781, longitude=-87.6298)"'
Write-Host ""
Write-Host "Now start:  python manage.py runserver"

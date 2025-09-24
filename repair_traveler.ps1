param(
  # Path to your repo root (folder containing 'stays', 'templates', 'config', etc.)
  [string]$Repo = (Get-Location).Path
)

# repair_traveler.ps1
# ------------------------------------------------------------------------------------
# Fixes:
#  - stays/urls.py  (adds stay_list/list/map-data/add/edit with app_name='stays')
#  - stays/views.py (safe, working implementations + stubs for referenced routes)
#  - templates/stays/stay_list.html (banner UI + table + Leaflet map, safe lookups)
#  - static/favicon.ico (stops favicon 404s)
# Backups: original files saved as .bak.<timestamp> alongside each file.
# Idempotent: re-running is safe; will overwrite with the same fixed content.
# ------------------------------------------------------------------------------------

$ErrorActionPreference = "Stop"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-FileSafe([string]$Path, [string]$Content) {
  Ensure-Dir (Split-Path -Parent $Path)
  if (Test-Path -LiteralPath $Path) {
    $bak = "$Path.bak.$ts"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    Write-Host "Backup: $bak"
  }
  Set-Content -NoNewline -LiteralPath $Path -Value $Content -Encoding UTF8
  Write-Host "Wrote:  $Path"
}

# -------------------- 1) stays/urls.py --------------------
$urlsPath = Join-Path $Repo "stays\urls.py"
$urlsContent = @'
from django.urls import path
from . import views

app_name = 'stays'

urlpatterns = [
    path('', views.stay_list, name='stay_list'),                 # /stays/
    path('stays/', views.stay_list, name='list'),                # legacy alias
    path('map-data/', views.stays_map_data, name='stays_map_data'),
    path('add/', views.stay_add, name='add'),                    # template calls {% url 'stays:add' %}
    path('edit/<int:pk>/', views.stay_edit, name='stay_edit'),   # template calls {% url 'stays:stay_edit' s.id %}
]
'@
Write-FileSafe $urlsPath $urlsContent

# -------------------- 2) stays/views.py --------------------
$viewsPath = Join-Path $Repo "stays\views.py"
$viewsContent = @'
from django.http import JsonResponse, HttpResponse
from django.shortcuts import render, get_object_or_404
from django.utils.html import escape
from django.urls import reverse, NoReverseMatch

from .models import Stay

# ---------- helpers ----------

def _to_float(v):
    try:
        return float(v) if v is not None else None
    except (TypeError, ValueError):
        return None

def _detail_url_for(s):
    """Return a usable detail/edit URL if available (used in map popup)."""
    for name in ('stay_edit', 'stay_detail'):
        try:
            return reverse(f"stays:{name}", args=[s.id])
        except NoReverseMatch:
            pass
    return ""

# ---------- core pages ----------

def stay_list(request):
    qs = Stay.objects.all().order_by('-check_in', '-id')
    states = (Stay.objects.exclude(state__isnull=True).exclude(state='')
              .values_list('state', flat=True).distinct().order_by('state'))
    ctx = dict(
        stays=qs,
        states=states,
        selected_state=request.GET.get('state', ''),
    )
    return render(request, 'stays/stay_list.html', ctx)

def stays_map_data(request):
    """Return JSON for map pins; accepts optional ?state=&city= filters."""
    qs = Stay.objects.all()
    state = request.GET.get("state")
    city = request.GET.get("city")
    if state:
        qs = qs.filter(state__iexact=state)
    if city:
        qs = qs.filter(city__iexact=city)

    qs = qs.exclude(latitude__isnull=True).exclude(longitude__isnull=True)

    out = []
    for s in qs:
        name = getattr(s, "park", None) or getattr(s, "site_name", None) or getattr(s, "location", "") or f"Stay #{s.pk}"
        city_val = getattr(s, "city", "") or ""
        state_val = getattr(s, "state", "") or ""
        popup = f"<strong>{escape(name)}</strong><br>{escape(city_val)}, {escape(state_val)}"
        out.append({
            "id": s.pk,
            "name": name,
            "latitude": _to_float(getattr(s, 'latitude', None)),
            "longitude": _to_float(getattr(s, 'longitude', None)),
            "popup_html": popup,
            "detail_url": _detail_url_for(s),
        })
    return JsonResponse({"stays": out}, json_dumps_params={"ensure_ascii": False})

# ---------- CRUD stubs (replace with real forms later) ----------

def stay_add(request):
    return HttpResponse("Stay Add — placeholder")

def stay_edit(request, pk):
    _ = get_object_or_404(Stay, pk=pk)
    return HttpResponse(f"Stay Edit — placeholder for #{pk}")

# ---------- misc routes referenced elsewhere (stubs so URLs load) ----------

def map_view(request):
    # Reuse list so /stays/map/ shows something useful if linked
    return stay_list(request)

def appearance_view(request):
    return HttpResponse("Appearance — placeholder")

def export_view(request):
    return HttpResponse("Export — placeholder")

def import_view(request):
    return HttpResponse("Import — placeholder")

def charts_view(request):
    return HttpResponse("Charts — placeholder")

# Custom error handlers (if project config points to them)
def custom_404(request, exception):  # pragma: no cover
    return HttpResponse("Not found", status=404)

def custom_500(request):  # pragma: no cover
    return HttpResponse("Server error", status=500)

def custom_403(request, exception):  # pragma: no cover
    return HttpResponse("Forbidden", status=403)

def custom_400(request, exception):  # pragma: no cover
    return HttpResponse("Bad request", status=400)
'@
Write-FileSafe $viewsPath $viewsContent

# -------------------- 3) templates/stays/stay_list.html --------------------
$tplPath = Join-Path $Repo "templates\stays\stay_list.html"
$tplContent = @'
{% load static %}
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Traveler • Stays</title>
  <link rel="icon" href="{% static 'favicon.ico' %}" sizes="any">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" integrity="sha256-o9N1j7kPvxG8kGHLm0P7E3vhd0JQ8Z8Lx9vZ1C8Q2vY=" crossorigin=""/>
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
      <a href="{% url 'stays:stay_list' %}">Stays</a>
      <a href="{% url 'stays:add' %}">Add Stay</a>
    </nav>
  </header>

  <div class="wrap">
    <div class="panel" style="padding:12px; margin-bottom:16px;">
      <div id="map"></div>
      <p class="muted" style="margin:8px 4px 0;">Pins load from <code>{% url 'stays:stays_map_data' %}</code>.</p>
    </div>

    {% if stays %}
      <table>
        <thead>
          <tr>
            <th>Label</th><th>City</th><th>State</th><th>Check in</th><th>Leave</th>
            <th>Nights</th><th>Rate</th><th>Total</th><th>Fees</th><th>Paid</th><th>Site</th><th></th>
          </tr>
        </thead>
        <tbody>
          {% for s in stays %}
          <tr>
            <td>{% firstof s.park s.site_name s.campground s.location "Stay" %}</td>
            <td>{{ s.city|default:"—" }}</td>
            <td>{{ s.state|default:"—" }}</td>
            <td>{{ s.check_in|default:"—" }}</td>
            <td>{{ s.leave|default:"—" }}</td>
            <td>{{ s.nights|default:"—" }}</td>
            <td>{% if s.rate_per_night is not None %}${{ s.rate_per_night }}{% else %}—{% endif %}</td>
            <td>{% if s.total is not None %}${{ s.total }}{% else %}—{% endif %}</td>
            <td>{% if s.fees is not None %}${{ s.fees }}{% else %}—{% endif %}</td>
            <td>{{ s.paid|yesno:"Yes,No" }}</td>
            <td>{{ s.site|default:"—" }}</td>
            <td><a class="button" href="{% url 'stays:stay_edit' s.id %}">Open / Edit</a></td>
          </tr>
          {% empty %}
          <tr><td colspan="12" style="text-align:center;padding:16px;">No stays yet.</td></tr>
          {% endfor %}
        </tbody>
      </table>
      <div style="padding:12px;">
        <a class="button" href="{% url 'stays:add' %}">Add Stay</a>
      </div>
    {% else %}
      <p class="muted">No stays found.</p>
    {% endif %}
  </div>

  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" integrity="sha256-o4mY9G7yyEJ9vE3F7w2S2U9Q4KQk2r+bQKp1R4C6G2Q=" crossorigin=""></script>
  <script>
  (function(){
    var map = L.map('map');
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 18, attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    var q = window.location.search || '';
    var mapDataUrl = "{% url 'stays:stays_map_data' %}";

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
        } else {
          map.setView([39.5, -98.35], 4);
        }
      })
      .catch(function(err){
        console.error('Map data error', err);
        map.setView([39.5, -98.35], 4);
      });
  })();
  </script>
</body>
</html>
'@
Write-FileSafe $tplPath $tplContent

# -------------------- 4) static/favicon.ico --------------------
$icoPath = Join-Path $Repo "static\favicon.ico"
Ensure-Dir (Split-Path -Parent $icoPath)

# Minimal 16x16 ICO (base64) to silence 404; replace later if desired.
$icoBase64 = @'
AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAGAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
///8A////AP///wD///8A////AP///wD///8A
'@.Trim()

# Write ico file; back up if exists
if (Test-Path -LiteralPath $icoPath) {
  Copy-Item -LiteralPath $icoPath -Destination "$icoPath.bak.$ts" -Force
  Write-Host "Backup: $($icoPath).bak.$ts"
}
[IO.File]::WriteAllBytes($icoPath, [Convert]::FromBase64String($icoBase64))
Write-Host "Wrote:  $icoPath"

# -------------------- Final hints --------------------
Write-Host ""
Write-Host "All set."
Write-Host "Next:"
Write-Host "  python manage.py runserver"
Write-Host "Then visit: http://127.0.0.1:8000/stays/stays/"
Write-Host ""
Write-Host "Optional (git save point):"
Write-Host "  git add stays/urls.py stays/views.py templates/stays/stay_list.html static/favicon.ico"
Write-Host "  git commit -m 'Repair: stays routes/views/template + favicon; JSON map + safe lookups'"

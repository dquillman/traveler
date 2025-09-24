# update_ui_and_pins.ps1
# - Restores full stays UI template (filters + table + map)
# - Makes map-data view tolerant to various lat/lng field names
# - Ensures URL route exists
$ErrorActionPreference = "Stop"
$ts = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not (Test-Path "stays")) { throw "stays folder not found" }
if (-not (Test-Path "templates\stays")) { New-Item -ItemType Directory -Force -Path "templates\stays" | Out-Null }

# Backups
foreach ($f in @("stays\views.py","stays\urls.py","templates\stays\stay_list.html")) {
  if (Test-Path $f) { Copy-Item $f "$f.bak.$ts" }
}

# ---------- stays/views.py (robust lat/lng + full list view) ----------
@'
from django.http import JsonResponse, HttpResponse
from django.shortcuts import render
from django.urls import reverse, NoReverseMatch
from .models import Stay

LAT_CANDIDATES = ["latitude", "lat", "gps_lat", "y", "lat_deg", "lat_degrees"]
LNG_CANDIDATES = ["longitude", "lng", "lon", "gps_lng", "x", "long_deg", "long_degrees"]

def _to_float(v):
    try:
        if v is None: return None
        return float(v)
    except (TypeError, ValueError):
        return None

def _get_lat_lng(obj):
    # try all candidate attribute names
    lat = None
    lng = None
    for name in LAT_CANDIDATES:
        lat = _to_float(getattr(obj, name, None))
        if lat is not None: break
    for name in LNG_CANDIDATES:
        lng = _to_float(getattr(obj, name, None))
        if lng is not None: break
    return lat, lng

def _apply_filters(request, qs):
    state = (request.GET.get('state') or '').strip()
    stars = (request.GET.get('stars') or '').strip()
    if state:
        qs = qs.filter(state__iexact=state)
    if stars:
        try:
            s = int(stars)
            if 1 <= s <= 5:
                qs = qs.filter(rating=s)
        except ValueError:
            pass
    return qs

def stay_list(request):
    qs = _apply_filters(request, Stay.objects.all()).order_by('-check_in', '-id')

    states = (Stay.objects.exclude(state__isnull=True).exclude(state='')
              .values_list('state', flat=True).distinct().order_by('state'))
    stars_options = [5, 4, 3, 2, 1]

    ctx = dict(
        stays=qs,
        states=states,
        stars_options=stars_options,
        selected_state=request.GET.get('state', ''),
        selected_stars=request.GET.get('stars', ''),
    )
    return render(request, 'stays/stay_list.html', ctx)

def _detail_url_for(s):
    for name in ('stay_edit', 'stay_detail'):
        try:
            return reverse(name, args=[s.id])
        except NoReverseMatch:
            continue
    return ''

def stays_map_data(request):
    qs = _apply_filters(request, Stay.objects.all())
    data = []
    for s in qs:
        lat, lng = _get_lat_lng(s)
        if lat is None or lng is None:
            continue
        data.append({
            'id': s.id,
            'park': getattr(s, 'park', '') or 'Stay',
            'city': getattr(s, 'city', '') or '',
            'state': (getattr(s, 'state', '') or '').upper(),
            'rating': getattr(s, 'rating', 0) or 0,
            'check_in': getattr(s, 'check_in', None).isoformat() if getattr(s, 'check_in', None) else '',
            'lat': lat,
            'lng': lng,
            'detail_url': _detail_url_for(s),
        })
    return JsonResponse({'stays': data})
'@ | Set-Content "stays\views.py" -Encoding UTF8

# ---------- stays/urls.py (ensure map-data route + stable names) ----------
$urls = @"
from django.urls import path
from . import views

app_name = 'stays'

urlpatterns = [
    path('', views.stay_list, name='stay_list'),
    path('stays/', views.stay_list, name='list'),  # alias for reverse('list')
    path('map-data/', views.stays_map_data, name='stays_map_data'),
]
"@
$urls | Set-Content "stays\urls.py" -Encoding UTF8

# ---------- templates/stays/stay_list.html (full UI + safe text + namespace-agnostic map url) ----------
@'
{% load static %}
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>Traveler - Stays</title>
  <link rel="stylesheet" href="{% static 'css/style.css' %}">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin="">
  <style>
    :root { --line: #e5e7eb; }
    body { font-family: system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif; margin:16px; }
    .filters { display:flex; gap:12px; align-items:center; margin: 8px 0 16px; flex-wrap: wrap; }
    label { font-weight:600; }
    select { padding:6px 8px; }
    table { width:100%; border-collapse: collapse; margin-top:12px; }
    th, td { padding:8px 10px; border-bottom:1px solid var(--line); }
    th { text-align:left; background:#f8fafc; position:sticky; top:0; z-index:1; }
    .stars { white-space:nowrap; }
    .pill { display:inline-block; padding:2px 8px; border-radius:999px; background:#eef2ff; }
    #map { height:420px; border:1px solid var(--line); border-radius:10px; margin-bottom:16px; }
    .note { font-size: 13px; color:#6b7280; margin:6px 0; }
  </style>
</head>
<body>

<h1>Stays</h1>

<form method="get" class="filters">
  <label>
    State:
    <select name="state" onchange="this.form.submit()">
      <option value="">All</option>
      {% for s in states %}
        <option value="{{ s }}" {% if selected_state|upper == s|upper %}selected{% endif %}>{{ s|upper }}</option>
      {% endfor %}
    </select>
  </label>

  <label>
    Stars:
    <select name="stars" onchange="this.form.submit()">
      <option value="">All</option>
      {% for s in stars_options %}
        <option value="{{ s }}" {% if selected_stars|stringformat:"s" == s|stringformat:"s" %}selected{% endif %}>{{ s }}&#9733;</option>
      {% endfor %}
    </select>
  </label>

  {% if selected_state or selected_stars %}
    <a href="{% url 'stay_list' %}">Reset</a>
  {% endif %}
</form>

<div id="map"></div>
<div class="note" id="map-note" style="display:none;"></div>

<table>
  <thead>
    <tr>
      <th>Park</th>
      <th>City</th>
      <th>State</th>
      <th>Check in</th>
      <th>Rating</th>
    </tr>
  </thead>
  <tbody>
  {% for stay in stays %}
    <tr>
      <td>{% firstof stay.park "&mdash;" %}</td>
      <td>{% firstof stay.city "&mdash;" %}</td>
      <td><span class="pill">{% firstof stay.state|upper "&mdash;" %}</span></td>
      <td>{% if stay.check_in %}{{ stay.check_in|date:"Y-m-d" }}{% else %}&mdash;{% endif %}</td>
      <td class="stars">{% if stay.rating %}{{ stay.rating }}&#9733;{% else %}&mdash;{% endif %}</td>
    </tr>
  {% empty %}
    <tr><td colspan="5">No stays found.</td></tr>
  {% endfor %}
  </tbody>
</table>

<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin=""></script>
<script>
(function(){
  var map = L.map('map');
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 18, attribution: '&copy; OpenStreetMap'
  }).addTo(map);

  var q = window.location.search || '';

  // Namespace-agnostic reverse: try both names; fallback to literal path.
  var mapDataUrl = (function(){
    try { return "{% url 'stays_map_data' %}"; } catch(e) {}
    try { return "{% url 'stays:stays_map_data' %}"; } catch(e) {}
    return "/stays/map-data/";
  })();

  fetch(mapDataUrl + q)
    .then(function(r){ return r.json(); })
    .then(function(j){
      var stays = (j && j.stays) ? j.stays : [];
      var group = L.featureGroup();
      stays.forEach(function(s){
        var ok = (typeof s.lat === 'number' && !isNaN(s.lat) &&
                  typeof s.lng === 'number' && !isNaN(s.lng));
        if (!ok) return;
        var popup = '<div style="min-width:200px">'
          + '<strong>' + (s.park || 'Stay') + '</strong><br/>'
          + (s.city ? s.city + ', ' : '') + (s.state || '') + '<br/>'
          + (s.check_in ? ('Check in: ' + s.check_in) : '') + '<br/>'
          + (s.rating ? ('Rating: ' + '&#9733;'.repeat(s.rating)) : '')
          + (s.detail_url ? '<br/><a href="'+s.detail_url+'">Open</a>' : '')
          + '</div>';
        L.marker([s.lat, s.lng]).bindPopup(popup).addTo(group);
      });

      if (group.getLayers().length) {
        group.addTo(map);
        map.fitBounds(group.getBounds().pad(0.2));
      } else {
        map.setView([39.8283,-98.5795], 4);
        var note = document.getElementById('map-note');
        note.textContent = 'No pins to display. Add coordinates to your stays (any of: latitude/longitude, lat/lng, lon, gps_lat/gps_lng).';
        note.style.display = 'block';
      }
    })
    .catch(function(err){
      console.error('Map data fetch failed', err);
      map.setView([39.8283,-98.5795], 4);
    });
})();
</script>

</body>
</html>
'@ | Set-Content "templates\stays\stay_list.html" -Encoding UTF8

Write-Host "Updated views.py, urls.py, and stay_list.html (backups saved with .bak.$ts)"
Write-Host "Restart the server if needed: python manage.py runserver"

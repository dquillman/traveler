# update_stays.ps1
# Overwrites urls.py, views.py, and stay_list.html with fixed versions

$ErrorActionPreference = "Stop"
$ts = Get-Date -Format "yyyyMMdd-HHmmss"

# Ensure folders exist
if (-not (Test-Path "stays")) { throw "stays folder not found" }
if (-not (Test-Path "templates\stays")) { New-Item -ItemType Directory -Force -Path "templates\stays" | Out-Null }

# Backup old files
foreach ($f in @("stays\urls.py","stays\views.py","templates\stays\stay_list.html")) {
    if (Test-Path $f) {
        Copy-Item $f "$f.bak.$ts"
    }
}

# --- urls.py ---
@'
from django.urls import path
from . import views

urlpatterns = [
    path('', views.stay_list, name='stay_list'),
    path('map-data/', views.stays_map_data, name='stays_map_data'),
    # path('<int:pk>/edit/', views.stay_edit, name='stay_edit'),
]
'@ | Set-Content "stays\urls.py" -Encoding UTF8
Write-Host "urls.py updated"

# --- views.py ---
@'
from django.http import JsonResponse
from django.shortcuts import render
from django.urls import reverse, NoReverseMatch
from .models import Stay

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
    stars_options = [5,4,3,2,1]
    return render(request, 'stays/stay_list.html', {
        'stays': qs,
        'states': states,
        'stars_options': stars_options,
        'selected_state': request.GET.get('state', ''),
        'selected_stars': request.GET.get('stars', ''),
    })

def _detail_url_for(s):
    for name in ('stay_edit','stay_detail'):
        try:
            return reverse(name, args=[s.id])
        except NoReverseMatch:
            continue
    return ''

def stays_map_data(request):
    qs = _apply_filters(request,
        Stay.objects.exclude(latitude__isnull=True).exclude(longitude__isnull=True))
    data = []
    for s in qs:
        data.append({
            'id': s.id,
            'park': getattr(s,'park','') or getattr(s,'name','') or 'Stay',
            'city': getattr(s,'city','') or '',
            'state': (s.state or '').upper(),
            'rating': s.rating or 0,
            'check_in': s.check_in.isoformat() if getattr(s,'check_in',None) else '',
            'lat': s.latitude,
            'lng': s.longitude,
            'detail_url': _detail_url_for(s),
        })
    return JsonResponse({'stays': data})
'@ | Set-Content "stays\views.py" -Encoding UTF8
Write-Host "views.py updated"

# --- stay_list.html ---
@'
{% load static %}
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>Traveler — Stays</title>
  <link rel="stylesheet" href="{% static 'css/style.css' %}">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
        integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin=""/>
  <style>
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 16px; }
    .filters { display:flex; gap:12px; align-items:center; margin: 8px 0 16px; }
    label { font-weight: 600; }
    select { padding:6px 8px; }
    table { width:100%; border-collapse: collapse; }
    th, td { padding: 8px 10px; border-bottom: 1px solid #e5e7eb; }
    th { text-align:left; background:#f8fafc; position: sticky; top: 0; }
    .stars { white-space:nowrap; }
    .pill { display:inline-block; padding:2px 8px; border-radius:999px; background:#eef2ff; }
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
        <option value="{{ s }}" {% if selected_stars|stringformat:"s" == s|stringformat:"s" %}selected{% endif %}>{{ s }}★</option>
      {% endfor %}
    </select>
  </label>

  {% if selected_state or selected_stars %}
    <a href="{% url 'stay_list' %}">Reset</a>
  {% endif %}
</form>

<div id="map" style="height:420px;border:1px solid #ddd;border-radius:10px;margin-bottom:16px;"></div>

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
      <td>{{ stay.park|default:stay.name|default:"—" }}</td>
      <td>{{ stay.city|default:"—" }}</td>
      <td><span class="pill">{{ stay.state|upper|default:"—" }}</span></td>
      <td>{{ stay.check_in|date:"Y-m-d"|default:"—" }}</td>
      <td class="stars">
        {% if stay.rating %}
          {% for _ in ""|center:stay.rating %}★{% endfor %}
        {% else %}
          —
        {% endif %}
      </td>
    </tr>
  {% empty %}
    <tr><td colspan="5">No stays found.</td></tr>
  {% endfor %}
  </tbody>
</table>

<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script>
(function(){
  var map = L.map('map');
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 18, attribution: '&copy; OpenStreetMap'
  }).addTo(map);

  const q = window.location.search || '';
  fetch("{% url 'stays_map_data' %}" + q)
    .then(r=>r.json()).then(j=>{
      const stays=j.stays||[];
      if(!stays.length){map.setView([39.8283,-98.5795],4);return;}
      const group=L.featureGroup();
      stays.forEach(s=>{
        if(typeof s.lat==='number'&&typeof s.lng==='number'){
          const popup=`<div style="min-width:180px">
              <strong>${s.park||'Stay'}</strong><br/>
              ${s.city? s.city+', ':''}${s.state||''}<br/>
              ${s.check_in?('Check in: '+s.check_in):''}<br/>
              ${s.rating?('Rating: '+'★'.repeat(s.rating)):''}
            </div>`;
          L.marker([s.lat,s.lng]).bindPopup(popup).addTo(group);
        }
      });
      if(group.getLayers().length){group.addTo(map);map.fitBounds(group.getBounds().pad(0.2));}
      else{map.setView([39.8283,-98.5795],4);}
    }).catch(()=>map.setView([39.8283,-98.5795],4));
})();
</script>

</body>
</html>
'@ | Set-Content "templates\stays\stay_list.html" -Encoding UTF8
Write-Host "stay_list.html updated"

Write-Host ""
Write-Host "All done. Backups saved with .bak.$ts"
Write-Host "Now run: python manage.py runserver"

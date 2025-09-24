# apply_map_filters.ps1
# PowerShell script to add map + filters + default ordering for stays app

$ErrorActionPreference = "Stop"
$ts = Get-Date -Format "yyyyMMdd-HHmmss"

# --- check environment ---
if (-not (Test-Path "manage.py")) {
    Write-Error "Run this from your Django project root (where manage.py lives)."
}
if (-not (Test-Path "stays")) {
    Write-Error "Couldn't find 'stays' app directory."
}
if (-not (Test-Path "templates\stays")) {
    New-Item -ItemType Directory -Force -Path "templates\stays" | Out-Null
}

# --- 1) Backup and patch models.py ---
if (Test-Path "stays\models.py") {
    Copy-Item "stays\models.py" "stays\models.py.bak.$ts"
} else {
    Write-Error "stays\models.py not found"
}

# Ensure ordering Meta exists
$content = Get-Content "stays\models.py" -Raw
if ($content -match "class\s+Meta") {
    # replace or insert ordering line
    if ($content -match "ordering\s*=") {
        $content = [regex]::Replace($content, "ordering\s*=\s*\[.*?\]", "ordering = ['-check_in', '-id']")
    } else {
        $content = $content -replace "(class\s+Meta\s*:[\s\S]*?)(\n\s*class|\Z)", "`$1`n        ordering = ['-check_in', '-id']`n`$2"
    }
} else {
    # add new Meta block inside Stay
    $content = $content -replace "(class\s+Stay\s*\(models.Model\)\s*:[\s\S]*?)(\n\n|$)", "`$1`n    class Meta:`n        ordering = ['-check_in', '-id']`n`n"
}
Set-Content "stays\models.py" $content -Encoding UTF8
Write-Host "✔ models.py updated with default ordering"

# --- 2) urls.py ---
if (Test-Path "stays\urls.py") {
    Copy-Item "stays\urls.py" "stays\urls.py.bak.$ts"
}
@'
from django.urls import path
from . import views

urlpatterns = [
    path('', views.stay_list, name='stay_list'),
    path('map-data/', views.stays_map_data, name='stays_map_data'),
    # path('<int:pk>/edit/', views.stay_edit, name='stay_edit'),
]
'@ | Set-Content "stays\urls.py" -Encoding UTF8
Write-Host "✔ urls.py written with map-data route"

# --- 3) views.py ---
if (Test-Path "stays\views.py") {
    Copy-Item "stays\views.py" "stays\views.py.bak.$ts"
}
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
Write-Host "✔ views.py written"

# --- 4) stay_list.html ---
if (Test-Path "templates\stays\stay_list.html") {
    Copy-Item "templates\stays\stay_list.html" "templates\stays\stay_list.html.bak.$ts"
}
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
</head>
<body>
<h1>Stays</h1>
<form method="get" class="filters" style="display:flex; gap:12px; align-items:center; margin: 8px 0 16px;">
  <label>State:
    <select name="state" onchange="this.form.submit()">
      <option value="">All</option>
      {% for s in states %}
        <option value="{{ s }}" {% if selected_state|upper == s|upper %}selected{% endif %}>{{ s|upper }}</option>
      {% endfor %}
    </select>
  </label>
  <label>Stars:
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
    <tr><th>Park</th><th>City</th><th>State</th><th>Check in</th><th>Rating</th></tr>
  </thead>
  <tbody>
  {% for stay in stays %}
    <tr>
      <td>{{ stay.park|default:stay.name|default:"—" }}</td>
      <td>{{ stay.city|default:"—" }}</td>
      <td>{{ stay.state|upper|default:"—" }}</td>
      <td>{{ stay.check_in|date:"Y-m-d"|default:"—" }}</td>
      <td>{% if stay.rating %}{% for _ in ""|center:stay.rating %}★{% endfor %}{% else %}—{% endif %}</td>
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
          const popup=`<div><strong>${s.park||'Stay'}</strong><br/>${s.city? s.city+', ':''}${s.state||''}<br/>${s.check_in?('Check in: '+s.check_in):''}<br/>${s.rating?('Rating: '+'★'.repeat(s.rating)):''}</div>`;
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
Write-Host "✔ stay_list.html written"

Write-Host ""
Write-Host "✅ All changes applied. Backups saved with .bak.$ts"
Write-Host "Next: run your server again:"
Write-Host "  python manage.py runserver"

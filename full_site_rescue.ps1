# full_site_rescue.ps1 — reset stays app to a working baseline (views, urls, templates) and try migrations
$ErrorActionPreference = 'Stop'

# Helpers
function Write-File {
    param([string]$Path, [string]$Content)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

# Timestamp
$ts = (Get-Date).ToString('yyyyMMdd_HHmmss')

# Backups if present
$toBackup = @(
    'stays\views.py',
    'stays\urls.py',
    'templates\stays\stay_list.html',
    'templates\stays\stay_form.html',
    'templates\stays\charts.html',
    'templates\stays\import.html',
    'templates\stays\export.html',
    'templates\stays\appearance.html',
    'templates\stays\map.html',
    'templates\stays\_base_stub.html'
)
foreach ($f in $toBackup) { if (Test-Path $f) { Copy-Item $f "$f.bak.$ts" -Force } }

# ---- Known-good stays/views.py (dynamic/safe for missing fields) ----
$views_py = @'
# -*- coding: utf-8 -*-
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from django.http import JsonResponse
from django.forms import ModelForm
from .models import Stay

# Try to use the app's StayForm; fallback to a simple ModelForm if missing
try:
    from stays.forms import StayForm as _StayForm
except Exception:
    _StayForm = None

class _FallbackStayForm(ModelForm):
    class Meta:
        model = Stay
        fields = "__all__"

StayForm = _StayForm or _FallbackStayForm


def _apply_stay_filters(qs, request):
    """Apply multi-filters: state, city, rating (if rating field exists)."""
    states = request.GET.getlist("state") or ([request.GET.get("state")] if request.GET.get("state") else [])
    cities = request.GET.getlist("city") or ([request.GET.get("city")] if request.GET.get("city") else [])
    ratings = request.GET.getlist("rating") or ([request.GET.get("rating")] if request.GET.get("rating") else [])

    states = [s for s in states if s]
    cities = [c for c in cities if c]

    ratings_clean = []
    for r in ratings:
        try:
            ratings_clean.append(int(r))
        except Exception:
            pass

    if states:
        qs = qs.filter(state__in=states)
    if cities:
        qs = qs.filter(city__in=cities)

    # Only filter by rating if the field exists
    field_names = {getattr(f, "attname", None) or getattr(f, "name", None) for f in Stay._meta.get_fields()}
    if ratings_clean and "rating" in field_names:
        qs = qs.filter(rating__in=ratings_clean)

    return qs


def stay_list(request):
    qs = Stay.objects.all()
    # Choices are guarded against missing columns
    field_names = {getattr(f, "attname", None) or getattr(f, "name", None) for f in Stay._meta.get_fields()}

    def safe_distinct(col):
        if col not in field_names:
            return []
        return list(
            Stay.objects.values_list(col, flat=True)
            .exclude(**{f"{col}__isnull": True})
            .exclude(**{f"{col}__exact": ""})
            .distinct()
            .order_by(col)
        )

    state_choices = safe_distinct("state")
    city_choices = safe_distinct("city")
    rating_choices = [1, 2, 3, 4, 5]

    qs = _apply_stay_filters(qs, request)

    context = {
        "stays": qs,
        "state_choices": state_choices,
        "city_choices": city_choices,
        "rating_choices": rating_choices,
    }
    return render(request, "stays/stay_list.html", context)


def stay_add(request):
    if request.method == "POST":
        form = StayForm(request.POST)
        if form.is_valid():
            form.save()
            messages.success(request, "Stay created.")
            return redirect("stays:list")
    else:
        form = StayForm()
    return render(request, "stays/stay_form.html", {"form": form})


def stay_edit(request, pk):
    obj = get_object_or_404(Stay, pk=pk)
    if request.method == "POST":
        form = StayForm(request.POST, instance=obj)
        if form.is_valid():
            form.save()
            messages.success(request, "Stay updated.")
            return redirect("stays:list")
    else:
        form = StayForm(instance=obj)
    return render(request, "stays/stay_form.html", {"form": form, "stay": obj})


def stays_map_data(request):
    # Build values() fields dynamically so missing DB columns never explode
    field_names = {getattr(f, "attname", None) or getattr(f, "name", None) for f in Stay._meta.get_fields()}
    wanted = ["id"]
    for col in ["city", "state", "latitude", "longitude"]:
        if col in field_names:
            wanted.append(col)
    qs = Stay.objects.all()
    stays = list(qs.values(*wanted))
    return JsonResponse({"stays": stays})


# Stub pages so nothing 404s
def stays_charts(request):
    return render(request, "stays/charts.html", {})

def stays_import(request):
    return render(request, "stays/import.html", {})

def stays_export(request):
    return render(request, "stays/export.html", {})

def stays_appearance(request):
    return render(request, "stays/appearance.html", {})

def stays_map(request):
    return render(request, "stays/map.html", {})
'@

Write-File 'stays\views.py' $views_py

# ---- stays/urls.py with all routes ----
$urls_py = @'
from django.urls import path
from . import views

app_name = "stays"

urlpatterns = [
    path("", views.stay_list, name="list"),
    path("add/", views.stay_add, name="add"),
    path("<int:pk>/edit/", views.stay_edit, name="edit"),
    path("map-data/", views.stays_map_data, name="map_data"),
    path("charts/", views.stays_charts, name="charts"),
    path("import/", views.stays_import, name="import"),
    path("export/", views.stays_export, name="export"),
    path("appearance/", views.stays_appearance, name="appearance"),
    path("map/", views.stays_map, name="map"),
]
'@
Write-File 'stays\urls.py' $urls_py

# ---- Minimal templates (shared nav + pages) ----
$base_stub = @'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Traveler • Stays</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial; margin:0; padding:20px; background:#0f1220; color:#e8ebff; }
      nav a { color:#b9c6ff; text-decoration:none; margin-right:12px; }
      nav { margin-bottom:16px; }
      select, button, input { padding:6px 10px; border-radius:8px; border:1px solid #272b41; background:#161a2b; color:#e8ebff; }
      hr { border:0; border-top:1px solid #272b41; margin:16px 0; }
      .card { background:#161a2b; border:1px solid #272b41; border-radius:12px; padding:16px; margin:12px 0; }
      label { margin-right:8px; }
    </style>
  </head>
  <body>
    <nav>
      <a href="/stays/">List</a>
      <a href="/stays/add/">Add</a>
      <a href="/stays/map/">Map</a>
      <a href="/stays/charts/">Charts</a>
      <a href="/stays/import/">Import</a>
      <a href="/stays/export/">Export</a>
      <a href="/stays/appearance/">Appearance</a>
    </nav>
    <hr>
    {% block content %}{% endblock %}
  </body>
</html>
'@
Write-File 'templates\stays\_base_stub.html' $base_stub

$stay_list_html = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>Stays</h1>
  <form method="get" class="card">
    <label>State</label>
    <select name="state" multiple>
      {% for s in state_choices %}<option value="{{s}}">{{s}}</option>{% endfor %}
    </select>
    <label>City</label>
    <select name="city" multiple>
      {% for c in city_choices %}<option value="{{c}}">{{c}}</option>{% endfor %}
    </select>
    <label>Rating</label>
    <select name="rating" multiple>
      {% for r in rating_choices %}<option value="{{r}}">{{r}}</option>{% endfor %}
    </select>
    <button type="submit">Filter</button>
  </form>

  {% for stay in stays %}
    <div class="card">
      <div><strong>{{ stay.city }}</strong>{% if stay.state %}, {{ stay.state }}{% endif %}</div>
      {% if stay.rating %}<div>Rating: {{ stay.rating }}★</div>{% endif %}
    </div>
  {% empty %}
    <div class="card">No stays yet.</div>
  {% endfor %}
{% endblock %}
'@
Write-File 'templates\stays\stay_list.html' $stay_list_html

$stay_form_html = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>{% if stay %}Edit Stay{% else %}Add Stay{% endif %}</h1>
  <form method="post" class="card">
    {% csrf_token %}
    {{ form.as_p }}
    <button type="submit">Save</button>
  </form>
{% endblock %}
'@
Write-File 'templates\stays\stay_form.html' $stay_form_html

$charts_html = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>Charts</h1>
  <div class="card">Placeholder charts page.</div>
{% endblock %}
'@
Write-File 'templates\stays\charts.html' $charts_html

$import_html = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>Import</h1>
  <div class="card">Placeholder import page.</div>
{% endblock %}
'@
Write-File 'templates\stays\import.html' $import_html

$export_html = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>Export</h1>
  <div class="card">Placeholder export page.</div>
{% endblock %}
'@
Write-File 'templates\stays\export.html' $export_html

$appearance_html = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>Appearance</h1>
  <div class="card">Placeholder appearance page.</div>
{% endblock %}
'@
Write-File 'templates\stays\appearance.html' $appearance_html

$map_html = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>Map</h1>
  <div class="card">
    Minimal map placeholder. Map data JSON is fetched below and printed.
  </div>
  <pre id="out" class="card"></pre>
  <script>
    fetch("/stays/map-data/").then(r=>r.json()).then(d=>{
      document.getElementById("out").textContent = JSON.stringify(d, null, 2);
    }).catch(e=>{
      document.getElementById("out").textContent = "Error fetching map data: " + e;
    });
  </script>
{% endblock %}
'@
Write-File 'templates\stays\map.html' $map_html

# ---- Try to compile views.py to confirm no SyntaxError ----
try {
    $py = ".\.venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { $py = "python" }
    & $py -m py_compile stays\views.py
    Write-Host "Python compile OK for stays\views.py"
} catch {
    Write-Host "Python compile failed — open stays\views.py and check the reported line."
}

# ---- Try migrations (safe to run even if no changes) ----
try {
    $py = ".\.venv\Scripts\python.exe"
    if (-not (Test-Path $py)) { $py = "python" }
    & $py manage.py makemigrations stays
    & $py manage.py migrate
} catch {
    Write-Host "Migrations raised an error. You can still start the server; pages that don't need new columns will work."
}

Write-Host "Rescue complete. Start server with:  python manage.py runserver"
Write-Host "Pages: /stays/  /stays/add/  /stays/charts/  /stays/import/  /stays/export/  /stays/appearance/  /stays/map/  /stays/map-data/"

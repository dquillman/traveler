# traveler_update.ps1 - Rebuild Traveler files (models, forms, views, templates, urls, etc.)
# RUN from your Traveler project root (same folder as manage.py).

function Write-File($Path, $Content) {
  $Full = Join-Path (Get-Location) $Path
  $Dir = Split-Path $Full -Parent
  if (!(Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
  $Content | Set-Content -Path $Full -Encoding UTF8
}

# --- config/settings.py ---
$settings = @"
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = "replace-this-with-your-secret-key"
DEBUG = True
ALLOWED_HOSTS = []

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "stays",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "stays" / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
                "stays.context_processors.site_appearance",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}

LANGUAGE_CODE = "en-us"
TIME_ZONE = "America/Chicago"
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
"@
Write-File "config\settings.py" $settings

# --- config/urls.py ---
$urls = @"
from django.contrib import admin
from django.urls import path
from django.conf import settings
from django.conf.urls.static import static
from stays import views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("", views.stay_list, name="stay_list"),
    path("stay/<int:pk>/", views.stay_detail, name="stay_detail"),
    path("stays/new/", views.stay_create, name="stay_create"),
    path("stays/<int:pk>/edit/", views.stay_edit, name="stay_edit"),
    path("stays/<int:pk>/delete/", views.stay_delete, name="stay_delete"),
    path("map/", views.stays_map, name="stays_map"),
    path("charts/", views.stay_charts, name="stay_charts"),
    path("appearance/", views.appearance_edit, name="appearance_edit"),
    path("export/", views.export_stays_csv, name="export_stays_csv"),
    path("import/", views.import_stays_csv, name="import_stays_csv"),
    path("health/", views.health, name="health"),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
"@
Write-File "config\urls.py" $urls

# --- stays\models.py ---
$models = @"
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator

class Stay(models.Model):
    name = models.CharField(max_length=255)
    city = models.CharField(max_length=128, blank=True)
    state = models.CharField(max_length=64, blank=True)
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)

    rating = models.PositiveSmallIntegerField(
        null=True, blank=True,
        validators=[MinValueValidator(1), MaxValueValidator(5)],
        help_text="1 (worst) to 5 (best)"
    )

    water_hookup = models.BooleanField(default=False)
    sewer_hookup = models.BooleanField(default=False)
    electric_30a = models.BooleanField(default=False, help_text="30 Amp electric")
    electric_50a = models.BooleanField(default=False, help_text="50 Amp electric")

    photo = models.ImageField(upload_to="stays/", null=True, blank=True)
    is_background = models.BooleanField(default=False, help_text="If true, this photo is used as the site background.")

    def __str__(self):
        return self.name or f"Stay #{self.pk}"

    @property
    def stars(self) -> str:
        if not self.rating:
            return "—"
        return "★" * int(self.rating) + "☆" * (5 - int(self.rating))

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if self.is_background:
            type(self).objects.exclude(pk=self.pk).filter(is_background=True).update(is_background=False)
"@
Write-File "stays\models.py" $models

# --- stays\forms.py ---
$forms = @"
from django import forms
from .models import Stay

STAR_CHOICES = [
    (5, "★★★★★"),
    (4, "★★★★☆"),
    (3, "★★★☆☆"),
    (2, "★★☆☆☆"),
    (1, "★☆☆☆☆"),
]

class StayForm(forms.ModelForm):
    class Meta:
        model = Stay
        fields = "__all__"
        widgets = {
            "rating": forms.RadioSelect(choices=STAR_CHOICES),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for name, field in self.fields.items():
            if not isinstance(field.widget, forms.RadioSelect):
                existing = field.widget.attrs.get("class", "")
                field.widget.attrs["class"] = (existing + " txt").strip()
"@
Write-File "stays\forms.py" $forms

# --- stays\utils.py ---
$utils = @"
import requests

def geocode_city_state(city: str, state: str):
    if not (city and state):
        return None, None
    q = f"{city}, {state}"
    url = "https://nominatim.openstreetmap.org/search"
    params = {"q": q, "format": "json", "limit": 1}
    headers = {"User-Agent": "traveler-app/1.0 (contact: you@example.com)"}
    r = requests.get(url, params=params, headers=headers, timeout=10)
    r.raise_for_status()
    data = r.json()
    if not data:
        return None, None
    lat = float(data[0]["lat"])
    lon = float(data[0]["lon"])
    return lat, lon
"@
Write-File "stays\utils.py" $utils

# --- stays\context_processors.py ---
$cp = @"
from django.apps import apps

def site_appearance(request):
    defaults = {
        "site_name": "Traveler",
        "primary_color": "#0d6efd",
        "secondary_color": "#6c757d",
    }
    try:
        SiteAppearance = apps.get_model("stays", "SiteAppearance")
    except LookupError:
        SiteAppearance = None

    if SiteAppearance is not None:
        try:
            obj = SiteAppearance.objects.first()
            if obj:
                defaults.update({
                    "site_name": getattr(obj, "site_name", defaults["site_name"]),
                    "primary_color": getattr(obj, "primary_color", defaults["primary_color"]),
                    "secondary_color": getattr(obj, "secondary_color", defaults["secondary_color"]),
                })
        except Exception:
            pass

    background_url = None
    try:
        Stay = apps.get_model("stays", "Stay")
        if Stay is not None:
            try:
                bg = Stay.objects.filter(is_background=True, photo__isnull=False).exclude(photo="").first()
                if bg and getattr(bg, "photo", None):
                    try:
                        background_url = bg.photo.url
                    except Exception:
                        background_url = None
            except Exception:
                background_url = None
    except LookupError:
        background_url = None

    return {
        "site_appearance": defaults,
        "site_background_url": background_url,
    }
"@
Write-File "stays\context_processors.py" $cp

# --- stays\admin.py ---
$admin = @"
from django.contrib import admin
from django.utils.html import format_html
from .models import Stay

@admin.register(Stay)
class StayAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "city", "state", "rating",
                    "water_hookup", "sewer_hookup", "electric_30a", "electric_50a",
                    "photo_thumb", "is_background", "latitude", "longitude")
    search_fields = ("name", "city", "state")
    list_filter = ("state", "water_hookup", "sewer_hookup", "electric_30a", "electric_50a", "rating", "is_background")
    readonly_fields = ("photo_preview",)

    fieldsets = (
        (None, {"fields": ("name", "city", "state")}),
        ("Location", {"fields": ("latitude", "longitude")}),
        ("Rating & Hookups", {"fields": ("rating", "water_hookup", "sewer_hookup", "electric_30a", "electric_50a")}),
        ("Photo", {"fields": ("photo", "photo_preview", "is_background")}),
    )

    def photo_thumb(self, obj):
        if obj.photo:
            try:
                return format_html('<img src="{}" style="height:40px;width:auto;border-radius:4px;" />', obj.photo.url)
            except Exception:
                return "—"
        return "—"
    photo_thumb.short_description = "Photo"

    def photo_preview(self, obj):
        if obj.photo:
            try:
                return format_html('<img src="{}" style="max-width:320px;height:auto;border-radius:8px;" />', obj.photo.url)
            except Exception:
                return "—"
        return "—"
"@
Write-File "stays\admin.py" $admin

# --- stays\views.py ---
$views = @"
import csv
import io
import json
from django.core.serializers.json import DjangoJSONEncoder
from django.db.models import Count
from django.http import HttpResponse, HttpResponseBadRequest
from django.shortcuts import render, get_object_or_404, redirect
from django.contrib import messages
from django.apps import apps

from .models import Stay
from .forms import StayForm
from .utils import geocode_city_state

def stays_map(request):
    qs = (
        Stay.objects
        .filter(latitude__isnull=False, longitude__isnull=False)
        .values("id", "name", "city", "state", "latitude", "longitude")
    )
    stays = list(qs)
    stays_json = json.dumps(stays, cls=DjangoJSONEncoder)
    return render(request, "stays/map.html", {"stays_json": stays_json})

def stay_list(request):
    q = request.GET.get("q", "").strip()
    qs = Stay.objects.all()
    if q:
        qs = qs.filter(name__icontains=q)
    stays = qs.order_by("name")
    return render(request, "stays/list.html", {"stays": stays, "q": q})

def stay_detail(request, pk: int):
    stay = get_object_or_404(Stay, pk=pk)
    return render(request, "stays/detail.html", {"stay": stay})

def _maybe_geocode(stay):
    has_lat = hasattr(stay, "latitude")
    has_lon = hasattr(stay, "longitude")
    has_city = hasattr(stay, "city")
    has_state = hasattr(stay, "state")
    if not (has_lat and has_lon and (has_city or has_state)):
        return
    lat_missing = getattr(stay, "latitude", None) is None
    lon_missing = getattr(stay, "longitude", None) is None
    city = getattr(stay, "city", None)
    state = getattr(stay, "state", None)
    if (lat_missing or lon_missing) and (city or state):
        g_lat, g_lon = geocode_city_state(city or "", state or "")
        if lat_missing and g_lat is not None:
            stay.latitude = g_lat
        if lon_missing and g_lon is not None:
            stay.longitude = g_lon

def stay_create(request):
    if request.method == "POST":
        form = StayForm(request.POST, request.FILES)
        if form.is_valid():
            stay = form.save(commit=False)
            _maybe_geocode(stay)
            stay.save()
            messages.success(request, "Stay created.")
            return redirect("stay_detail", pk=stay.pk)
    else:
        form = StayForm()
    return render(request, "stays/form.html", {"form": form, "title": "New Stay"})

def stay_edit(request, pk: int):
    stay = get_object_or_404(Stay, pk=pk)
    if request.method == "POST":
        form = StayForm(request.POST, request.FILES, instance=stay)
        if form.is_valid():
            stay = form.save(commit=False)
            _maybe_geocode(stay)
            stay.save()
            messages.success(request, "Stay updated.")
            return redirect("stay_detail", pk=stay.pk)
    else:
        form = StayForm(instance=stay)
    return render(request, "stays/form.html", {"form": form, "title": f"Edit: {stay}"})

def stay_delete(request, pk: int):
    stay = get_object_or_404(Stay, pk=pk)
    if request.method == "POST":
        stay.delete()
        messages.success(request, "Stay deleted.")
        return redirect("stay_list")
    return render(request, "stays/confirm_delete.html", {"stay": stay})

def stay_charts(request):
    by_state = list(Stay.objects.values("state").annotate(n=Count("id")).order_by("state"))
    labels = [row["state"] or "—" for row in by_state]
    values = [row["n"] for row in by_state]
    return render(request, "stays/charts.html", {"labels": labels, "values": values})

def appearance_edit(request):
    SiteAppearance = None
    try:
        SiteAppearance = apps.get_model("stays", "SiteAppearance")
    except LookupError:
        SiteAppearance = None

    if SiteAppearance is None:
        messages.info(request, "Appearance settings are using defaults (no SiteAppearance model).")
        return render(request, "stays/appearance.html", {"has_model": False, "obj": None})

    obj = SiteAppearance.objects.first()
    if request.method == "POST":
        site_name = request.POST.get("site_name") or "Traveler"
        primary_color = request.POST.get("primary_color") or "#0d6efd"
        secondary_color = request.POST.get("secondary_color") or "#6c757d"
        if obj is None:
            obj = SiteAppearance.objects.create(
                site_name=site_name,
                primary_color=primary_color,
                secondary_color=secondary_color,
            )
        else:
            obj.site_name = site_name
            obj.primary_color = primary_color
            obj.secondary_color = secondary_color
            obj.save()
        messages.success(request, "Appearance updated.")
        return redirect("appearance_edit")

    return render(request, "stays/appearance.html", {"has_model": True, "obj": obj})

def export_stays_csv(request):
    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = 'attachment; filename="stays.csv"'
    w = csv.writer(response)
    w.writerow(["name", "city", "state", "latitude", "longitude", "rating",
                "water_hookup", "sewer_hookup", "electric_30a", "electric_50a"])
    for s in Stay.objects.all().order_by("name"):
        w.writerow([
            s.name, s.city, s.state,
            s.latitude or "", s.longitude or "",
            s.rating or "",
            "1" if s.water_hookup else "0",
            "1" if s.sewer_hookup else "0",
            "1" if s.electric_30a else "0",
            "1" if s.electric_50a else "0",
        ])
    return response

def import_stays_csv(request):
    if request.method == "POST":
        f = request.FILES.get("file")
        if not f:
            return HttpResponseBadRequest("No file uploaded.")
        decoded = io.TextIOWrapper(f.file, encoding="utf-8")
        reader = csv.DictReader(decoded)

        def to_bool(v):
            if v is None: return False
            s = str(v).strip().lower()
            return s in ("1", "true", "t", "yes", "y")

        def to_rating(v):
            if v in (None, ""): return None
            try:
                n = int(v)
                if 1 <= n <= 5: return n
            except Exception:
                pass
            return None

        created = updated = 0
        for row in reader:
            name = (row.get("name") or "").strip()
            if not name:
                continue
            city = (row.get("city") or "").strip()
            state = (row.get("state") or "").strip()
            lat = row.get("latitude")
            lon = row.get("longitude")
            lat = float(lat) if (lat not in (None, "")) else None
            lon = float(lon) if (lon not in (None, "")) else None

            rating = to_rating(row.get("rating"))
            water = to_bool(row.get("water_hookup"))
            sewer = to_bool(row.get("sewer_hookup"))
            e30 = to_bool(row.get("electric_30a"))
            e50 = to_bool(row.get("electric_50a"))

            stay, was_created = Stay.objects.get_or_create(
                name=name,
                defaults={
                    "city": city, "state": state,
                    "latitude": lat, "longitude": lon,
                    "rating": rating,
                    "water_hookup": water,
                    "sewer_hookup": sewer,
                    "electric_30a": e30,
                    "electric_50a": e50,
                }
            )
            changed = False
            if not was_created:
                for field, val in [
                    ("city", city), ("state", state),
                    ("latitude", lat), ("longitude", lon),
                    ("rating", rating),
                    ("water_hookup", water),
                    ("sewer_hookup", sewer),
                    ("electric_30a", e30),
                    ("electric_50a", e50),
                ]:
                    if val is not None and getattr(stay, field) != val:
                        setattr(stay, field, val)
                        changed = True
                if changed:
                    stay.save()
                    updated += 1
            else:
                created += 1
                if (stay.latitude is None or stay.longitude is None) and (stay.city or stay.state):
                    g_lat, g_lon = geocode_city_state(stay.city, stay.state)
                    if g_lat is not None and g_lon is not None:
                        stay.latitude = stay.latitude if stay.latitude is not None else g_lat
                        stay.longitude = stay.longitude if stay.longitude is not None else g_lon
                        stay.save()
        messages.success(request, f"Import finished. Created {created}, updated {updated}.")
        return redirect("stay_list")

    return render(request, "stays/import.html")

def health(request):
    return HttpResponse("OK")
"@
Write-File "stays\views.py" $views

# --- templates (base, list, detail, form, map, charts, appearance, import, confirm_delete) ---
function Write-Template($Path, $HereContent) { Write-File $Path $HereContent }

$base = @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>{{ site_appearance.site_name|default:"Traveler" }}</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet/dist/leaflet.css">
  <style>
    :root { --pri: {{ site_appearance.primary_color|default:"#0d6efd" }}; --fg:#e6edf3; --bg:#0b1220; --panel:#111827; --muted:#93a4b3; }
    html, body { height:100%; }
    body {
      margin:0; color:var(--fg); background:var(--bg);
      {% if site_background_url %}
      background-image: linear-gradient(rgba(0,0,0,.55), rgba(0,0,0,.55)), url('{{ site_background_url }}');
      background-size: cover; background-position:center; background-attachment:fixed;
      {% endif %}
    }
    .nav { display:flex; gap:16px; align-items:center; padding:12px 16px; background:#0f1621; border-bottom:1px solid #1f2630; }
    .nav a { color:var(--fg); text-decoration:none; opacity:.9 } .nav a:hover{opacity:1}
    .brand { font-weight:700; color:var(--pri); margin-right:20px; }
    .wrap { padding:20px; }
    .btn { display:inline-block; padding:8px 12px; background:var(--pri); color:white; border-radius:6px; text-decoration:none; }
    .btn-outline { border:1px solid var(--pri); color:var(--pri); background:transparent; border-radius:6px; padding:7px 11px; }
    .txt { width:100%; max-width:420px; padding:7px 9px; border:1px solid #2b3a4a; background:#0e1622; color:var(--fg); border-radius:6px; }
    table { border-collapse:collapse; width:100%; background:rgba(17,24,39,.75); backdrop-filter:blur(2px); }
    th,td { padding:10px 12px; border-bottom:1px solid #1f2937; }
    th { text-align:left; color:#cbd5e1; background:#0f172a; position:sticky; top:0; }
    .muted { color:var(--muted); }
    .card { background:rgba(17,24,39,.8); padding:16px; border:1px solid #1f2937; border-radius:10px; }
    .actions a { margin-right:8px; color:#7dd3fc; }
    img.thumb { height:40px; width:auto; border-radius:6px; border:1px solid #1f2937; }
  </style>
  {% block head %}{% endblock %}
</head>
<body>
  <nav class="nav">
    <span class="brand">{{ site_appearance.site_name|default:"Traveler" }}</span>
    <a href="/">Home</a><a href="/map/">Map</a><a href="/charts/">Charts</a><a href="/appearance/">Appearance</a><a href="/import/">Import</a><a href="/export/">Export</a><a href="/admin/">Admin</a>
  </nav>
  <div class="wrap">
    {% if messages %}{% for m in messages %}<div class="card" style="margin-bottom:8px;">{{ m }}</div>{% endfor %}{% endif %}
    {% block content %}{% endblock %}
  </div>
</body>
</html>
"@
Write-Template "stays\templates\stays\base.html" $base

$list = @"
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">Stays</h1>
    <form method="get" style="margin-bottom:12px;">
      <input name="q" class="txt" placeholder="Search by name..." value="{{ q }}">
      <button class="btn" style="margin-left:8px;">Search</button>
      <a class="btn btn-outline" href="{% url "stay_create" %}" style="margin-left:8px;">Add Stay</a>
    </form>
    <div style="overflow:auto; border-radius:8px;">
      <table>
        <thead>
          <tr><th>Photo</th><th>Name</th><th>City</th><th>State</th><th>Rating</th><th>Hookups</th><th>Lat</th><th>Lng</th><th></th></tr>
        </thead>
        <tbody>
        {% for s in stays %}
          <tr>
            <td>{% if s.photo %}<img class="thumb" src="{{ s.photo.url }}">{% else %}<span class="muted">—</span>{% endif %}</td>
            <td><a href="{% url 'stay_detail' s.id %}">{{ s.name }}</a>{% if s.is_background %} <span class="muted">• background</span>{% endif %}</td>
            <td>{{ s.city }}</td><td>{{ s.state }}</td>
            <td class="muted">{{ s.stars }}</td>
            <td>
              {% if s.water_hookup %}💧{% endif %}
              {% if s.sewer_hookup %}🚽{% endif %}
              {% if s.electric_30a %} 30A{% endif %}
              {% if s.electric_50a %}{% if s.electric_30a %} / {% endif %}50A{% endif %}
              {% if not s.water_hookup and not s.sewer_hookup and not s.electric_30a and not s.electric_50a %}<span class="muted">—</span>{% endif %}
            </td>
            <td class="muted">{{ s.latitude|default:"—" }}</td>
            <td class="muted">{{ s.longitude|default:"—" }}</td>
            <td class="actions"><a href="{% url 'stay_edit' s.id %}">Edit</a> <a href="{% url 'stay_delete' s.id %}">Delete</a></td>
          </tr>
        {% empty %}
          <tr><td colspan="9" class="muted">No stays yet. <a href="{% url 'stay_create' %}">Add one</a> or visit the <a href="/map/">map</a>.</td></tr>
        {% endfor %}
        </tbody>
      </table>
    </div>
  </div>
{% endblock %}
"@
Write-Template "stays\templates\stays\list.html" $list

$detail = @"
{% extends "stays/base.html" %}
{% block content %}
  <p><a href="/">← Back</a></p>
  <div class="card">
    <h1 style="margin-top:0;">{{ stay.name }}</h1>
    {% if stay.photo %}<img src="{{ stay.photo.url }}" alt="" style="max-width:100%;height:auto;border-radius:10px;border:1px solid #1f2937;">{% endif %}
    <dl style="display:grid;grid-template-columns:max-content 1fr;gap:8px 16px; margin-top:12px;">
      <dt>City</dt><dd>{{ stay.city }}</dd>
      <dt>State</dt><dd>{{ stay.state }}</dd>
      <dt>Rating</dt><dd>{{ stay.stars }}</dd>
      <dt>Hookups</dt>
      <dd>
        {% if stay.water_hookup %}💧 Water{% endif %}
        {% if stay.sewer_hookup %}{% if stay.water_hookup %} • {% endif %}🚽 Sewer{% endif %}
        {% if stay.electric_30a or stay.electric_50a %}{% if stay.water_hookup or stay.sewer_hookup %} • {% endif %}{% endif %}
        {% if stay.electric_30a %}30A{% endif %}{% if stay.electric_30a and stay.electric_50a %} / {% endif %}{% if stay.electric_50a %}50A{% endif %}
        {% if not stay.water_hookup and not stay.sewer_hookup and not stay.electric_30a and not stay.electric_50a %}—{% endif %}
      </dd>
      <dt>Latitude</dt><dd>{{ stay.latitude|default:"—" }}</dd>
      <dt>Longitude</dt><dd>{{ stay.longitude|default:"—" }}</dd>
    </dl>
    <p class="actions" style="margin-top:12px;">
      <a class="btn btn-outline" href="{% url 'stay_edit' stay.id %}">Edit</a>
      <a class="btn btn-outline" href="{% url 'stay_delete' stay.id %}">Delete</a>
      <a class="btn" href="/map/">View on Map</a>
    </p>
  </div>
{% endblock %}
"@
Write-Template "stays\templates\stays\detail.html" $detail

$form = @"
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">{{ title }}</h1>
    <form method="post" {% if form.is_multipart %}enctype="multipart/form-data"{% endif %}>
      {% csrf_token %}
      {{ form.non_field_errors }}
      <div style="display:grid;gap:12px;max-width:560px;">
        {% for field in form %}
          <div>
            <label for="{{ field.id_for_label }}" style="font-weight:600;">{{ field.label }}</label><br>
            {{ field }}
            {% if field.help_text %}<div class="muted" style="font-size:12px;">{{ field.help_text }}</div>{% endif %}
            {% for error in field.errors %}<div style="color:#fca5a5; font-size:12px;">{{ error }}</div>{% endfor %}
          </div>
        {% endfor %}
      </div>
      <p style="margin-top:14px;">
        <button class="btn">Save</button>
        <a class="btn btn-outline" href="/">Cancel</a>
      </p>
      <p class="muted">Tip: If you leave latitude/longitude blank but set City/State, we’ll try to geocode them.</p>
    </form>
  </div>
{% endblock %}
"@
Write-Template "stays\templates\stays\form.html" $form

$confirm = @"
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1>Delete: {{ stay.name }}</h1>
    <p>Are you sure you want to delete this stay?</p>
    <form method="post">{% csrf_token %}<button class="btn">Yes, delete</button> <a class="btn btn-outline" href="{% url 'stay_detail' stay.id %}">Cancel</a></form>
  </div>
{% endblock %}
"@
Write-Template "stays\templates\stays\confirm_delete.html" $confirm

$map = @"
{% extends "stays/base.html" %}
{% block head %}<style>#map{height:70vh;border-radius:8px;border:1px solid #1f2937;}</style>{% endblock %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">Map</h1>
    <div id="map"></div>
  </div>
  <script type="application/json" id="stays-data">{{ stays_json|safe }}</script>
  <script src="https://unpkg.com/leaflet/dist/leaflet.js"></script>
  <script>
    const map = L.map('map').setView([39.5, -98.35], 4);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {maxZoom:19, attribution:'&copy; OpenStreetMap'}).addTo(map);
    const stays = JSON.parse(document.getElementById('stays-data').textContent || '[]');
    const markers = [];
    stays.forEach(s => {
      if (typeof s.latitude === 'number' && typeof s.longitude === 'number') {
        markers.push(L.marker([s.latitude, s.longitude]).addTo(map)
          .bindPopup(`<strong>${s.name ?? 'Stay'}</strong><br>${s.city ?? ''}, ${s.state ?? ''}`));
      }
    });
    if (markers.length) { const g = L.featureGroup(markers); map.fitBounds(g.getBounds().pad(0.2)); }
  </script>
{% endblock %}
"@
Write-Template "stays\templates\stays\map.html" $map

$charts = @"
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">Charts</h1>
    <canvas id="byState" width="800" height="380"></canvas>
  </div>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <script>
    const labels = {{ labels|safe }};
    const values = {{ values|safe }};
    const ctx = document.getElementById("byState").getContext("2d");
    new Chart(ctx, { type: "bar", data: { labels, datasets: [{ label: "Stays by State", data: values }] }, options: { responsive: true, scales: { y: { beginAtZero: true } } } });
  </script>
{% endblock %}
"@
Write-Template "stays\templates\stays\charts.html" $charts

$appearance = @"
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">Appearance</h1>
    {% if not has_model %}
      <p class="muted">Using defaults. The <code>SiteAppearance</code> model is not present; the site still works.</p>
      <dl>
        <dt>Site Name</dt><dd>{{ site_appearance.site_name }}</dd>
        <dt>Primary Color</dt><dd>{{ site_appearance.primary_color }}</dd>
        <dt>Secondary Color</dt><dd>{{ site_appearance.secondary_color }}</dd>
      </dl>
    {% else %}
      <form method="post">{% csrf_token %}
        <div style="display:grid;gap:12px;max-width:420px;">
          <label>Site Name <input class="txt" name="site_name" value="{{ obj.site_name|default:site_appearance.site_name }}"></label>
          <label>Primary Color <input class="txt" name="primary_color" value="{{ obj.primary_color|default:site_appearance.primary_color }}"></label>
          <label>Secondary Color <input class="txt" name="secondary_color" value="{{ obj.secondary_color|default:site_appearance.secondary_color }}"></label>
        </div>
        <p style="margin-top:12px;"><button class="btn">Save</button></p>
      </form>
    {% endif %}
  </div>
{% endblock %}
"@
Write-Template "stays\templates\stays\appearance.html" $appearance

$import = @"
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">Import CSV</h1>
    <p>Columns: <code>name, city, state, latitude, longitude, rating, water_hookup, sewer_hookup, electric_30a, electric_50a</code>.</p>
    <form method="post" enctype="multipart/form-data">
      {% csrf_token %}
      <input type="file" name="file" accept=".csv" class="txt" style="max-width:unset;">
      <button class="btn" style="margin-left:8px;">Upload</button>
    </form>
  </div>
{% endblock %}
"@
Write-Template "stays\templates\stays\import.html" $import

# --- management command dirs (empty __init__.py files) ---
New-Item -ItemType Directory -Path "stays\management\commands" -Force | Out-Null
"" | Set-Content -Path "stays\management\__init__.py"
"" | Set-Content -Path "stays\management\commands\__init__.py"

$backfill = @"
from django.core.management.base import BaseCommand
from stays.models import Stay
from stays.utils import geocode_city_state

class Command(BaseCommand):
    help = "Backfill missing latitude/longitude for stays using geocode_city_state(city, state)."

    def handle(self, *args, **kwargs):
        qs = Stay.objects.filter(latitude__isnull=True) | Stay.objects.filter(longitude__isnull=True)
        total = qs.count()
        updated = 0
        self.stdout.write(f"Backfilling coordinates for {total} stays...")
        for stay in qs.iterator():
            try:
                lat, lon = geocode_city_state(stay.city, stay.state)
                if lat is not None and lon is not None:
                    stay.latitude = lat
                    stay.longitude = lon
                    stay.save(update_fields=["latitude", "longitude"])
                    updated += 1
                else:
                    self.stderr.write(f"No geocode for Stay(id={stay.id}, '{stay.city}, {stay.state}')")
            except Exception as e:
                self.stderr.write(f"Error on Stay(id={stay.id}): {e}")
        self.stdout.write(self.style.SUCCESS(f"Updated {updated}/{total} stays."))
"@
Write-Template "stays\management\commands\backfill_coords.py" $backfill

# --- requirements.txt ---
$req = @"
Django>=5.2.1
requests>=2.32
Pillow>=10.0
"@
Write-File "requirements.txt" $req

Write-Host "Files written. Next steps:"
Write-Host "1) venv\\Scripts\\activate"
Write-Host "2) pip install -r requirements.txt"
Write-Host "3) python manage.py makemigrations && python manage.py migrate"
Write-Host "4) python manage.py runserver"

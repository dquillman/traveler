# traveler_update_full.ps1
$ErrorActionPreference = "Stop"
$root = Get-Location
function Write-Text($Path, $Content) {
  $full = Join-Path $root $Path
  $dir  = Split-Path $full
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $Content | Set-Content -Path $full -Encoding UTF8
  Write-Host "Wrote $Path"
}

# ---------- stays/models.py ----------
Write-Text "stays\models.py" @'
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from django.utils.safestring import mark_safe

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

    # NEW
    price_night = models.DecimalField(max_digits=7, decimal_places=2, null=True, blank=True)
    electric_extra = models.BooleanField(default=False)

    photo = models.ImageField(upload_to="stays/", null=True, blank=True)
    is_background = models.BooleanField(default=False, help_text="If true, this photo is used as the site background.")

    def __str__(self):
        return self.name or f"Stay #{self.pk}"

    @property
    def stars_html(self):
        if not self.rating:
            return mark_safe("&mdash;")
        full = "&#9733;" * int(self.rating)      # ★
        empty = "&#9734;" * (5 - int(self.rating))  # ☆
        return mark_safe(full + empty)

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if self.is_background:
            type(self).objects.exclude(pk=self.pk).filter(is_background=True).update(is_background=False)
'@

# ---------- stays/forms.py ----------
Write-Text "stays\forms.py" @'
from django import forms
from django.utils.safestring import mark_safe
from .models import Stay

STAR = "&#9733;"   # ★
EMPTY = "&#9734;"  # ☆

STAR_CHOICES = [
    (5, mark_safe(STAR * 5)),
    (4, mark_safe(STAR * 4 + EMPTY)),
    (3, mark_safe(STAR * 3 + EMPTY * 2)),
    (2, mark_safe(STAR * 2 + EMPTY * 3)),
    (1, mark_safe(STAR + EMPTY * 4)),
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
        if "price_night" in self.fields:
            self.fields["price_night"].label = "Price / Night ($)"
            self.fields["price_night"].widget = forms.NumberInput(attrs={"step": "0.01", "min": "0"})
        if "electric_extra" in self.fields:
            self.fields["electric_extra"].label = "Elect. Extra"
        for name, field in self.fields.items():
            if not isinstance(field.widget, forms.RadioSelect):
                cls = field.widget.attrs.get("class", "")
                field.widget.attrs["class"] = (cls + " txt").strip()
'@

# ---------- stays/admin.py ----------
Write-Text "stays\admin.py" @'
from django.contrib import admin
from django.utils.html import format_html
from .models import Stay

@admin.register(Stay)
class StayAdmin(admin.ModelAdmin):
    list_display = (
        "id", "name", "city", "state", "rating",
        "price_night", "electric_extra",
        "water_hookup", "sewer_hookup", "electric_30a", "electric_50a",
        "photo_thumb", "is_background", "latitude", "longitude"
    )
    search_fields = ("name", "city", "state")
    list_filter = (
        "state", "rating", "electric_extra",
        "water_hookup", "sewer_hookup", "electric_30a", "electric_50a", "is_background"
    )
    readonly_fields = ("photo_preview",)

    fieldsets = (
        (None, {"fields": ("name", "city", "state")}),
        ("Location", {"fields": ("latitude", "longitude")}),
        ("Rating & Hookups", {"fields": ("rating", "water_hookup", "sewer_hookup", "electric_30a", "electric_50a", "electric_extra")}),
        ("Price", {"fields": ("price_night",)}),
        ("Photo", {"fields": ("photo", "photo_preview", "is_background")}),
    )

    def photo_thumb(self, obj):
        if obj.photo:
            try:
                return format_html('<img src="{}" style="height:40px;width:auto;border-radius:4px;" />', obj.photo.url)
            except Exception:
                return "—"
        return "—"

    def photo_preview(self, obj):
        if obj.photo:
            try:
                return format_html('<img src="{}" style="max-width:320px;height:auto;border-radius:8px;" />', obj.photo.url)
            except Exception:
                return "—"
        return "—"
'@

# ---------- stays/utils.py ----------
Write-Text "stays\utils.py" @'
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
'@

# ---------- stays/context_processors.py ----------
Write-Text "stays\context_processors.py" @'
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
'@

# ---------- stays/views.py ----------
Write-Text "stays\views.py" @'
import csv
import io
import json
from django.core.serializers.json import DjangoJSONEncoder
from django.db.models import Count
from django.http import HttpResponse, HttpResponseBadRequest
from django.shortcuts import render, get_object_or_404, redirect
from django.contrib import messages

from .models import Stay
from .forms import StayForm
from .utils import geocode_city_state

def stays_map(request):
    qs = (
        Stay.objects
        .filter(latitude__isnull=False, longitude__isnull=False)
        .values(
            "id", "name", "city", "state",
            "latitude", "longitude",
            "rating",
            "water_hookup", "sewer_hookup", "electric_30a", "electric_50a",
            "price_night", "electric_extra",
        )
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
    return render(request, "stays/appearance.html", {"has_model": False, "obj": None})

def export_stays_csv(request):
    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = 'attachment; filename="stays.csv"'
    w = csv.writer(response)
    w.writerow([
        "name", "city", "state", "latitude", "longitude", "rating",
        "water_hookup", "sewer_hookup", "electric_30a", "electric_50a",
        "price_night", "electric_extra",
    ])
    for s in Stay.objects.all().order_by("name"):
        w.writerow([
            s.name, s.city, s.state,
            s.latitude or "", s.longitude or "",
            s.rating or "",
            "1" if s.water_hookup else "0",
            "1" if s.sewer_hookup else "0",
            "1" if s.electric_30a else "0",
            "1" if s.electric_50a else "0",
            f"{s.price_night:.2f}" if s.price_night is not None else "",
            "1" if s.electric_extra else "0",
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

        def to_price(v):
            if v in (None, ""): return None
            try:
                return round(float(v), 2)
            except Exception:
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
            price = to_price(row.get("price_night"))
            elect_extra = to_bool(row.get("electric_extra"))

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
                    "price_night": price,
                    "electric_extra": elect_extra,
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
                    ("price_night", price),
                    ("electric_extra", elect_extra),
                ]:
                    if val is not None and getattr(stay, field) != val:
                        setattr(stay, field, val)
                        changed = True
                if changed:
                    stay.save()
                    updated += 1
            else:
                created += 1
        messages.success(request, f"Import finished. Created {created}, updated {updated}.")
        return redirect("stay_list")

    return render(request, "stays/import.html")

def health(request):
    return HttpResponse("OK")
'@

# ---------- templates ----------
Write-Text "stays\templates\stays\base.html" @'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>{{ site_appearance.site_name|default:"Traveler" }}</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.css">
  <style>
    :root { --pri: {{ site_appearance.primary_color|default:"#0d6efd" }}; --fg:#e6edf3; --bg:#0b1220; --panel:#111827; --muted:#93a4b3; }
    html, body { height:100%; }
    body {
      margin:0; color:var(--fg); background:var(--bg);
      {% if site_background_url %}
      background-image: linear-gradient(rgba(0,0,0,.55), rgba(0,0,0,.55)), url('{{ site_background_url }}');
      background-size: cover; background-position:center; background-attachment:fixed;
      {% endif %}
      font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji";
    }
    .nav { display:flex; gap:16px; align-items:center; padding:12px 16px; background:#0f1621; border-bottom:1px solid #1f2630; }
    .nav a { color:var(--fg); text-decoration:none; opacity:.9 } .nav a:hover{opacity:1}
    .brand { font-weight:700; color:var(--pri); margin-right:20px; }
    .wrap { padding:20px; }
    .btn { display:inline-block; padding:8px 12px; background:var(--pri); color:white; border-radius:6px; text-decoration:none; }
    .btn-outline { border:1px solid var(--pri); color:var(--pri); background:transparent; border-radius:6px; padding:7px 11px; }
    .txt { width:100%; max-width:420px; padding:7px 9px; border:1px solid #2b3a4a; background:#0e1622; color:var(--fg); border-radius:6px; }
    table { border-collapse:collapse; width:100%; background:rgba(17,24,39,.75); backdrop-filter:blur(2px); }
    th,td { padding:10px 12px; border-bottom:1px solid #1f2937; vertical-align:middle; }
    th { text-align:left; color:#cbd5e1; background:#0f172a; position:sticky; top:0; }
    .muted { color:var(--muted); }
    .card { background:rgba(17,24,39,.8); padding:16px; border:1px solid #1f2937; border-radius:10px; }
    .actions a { margin-right:8px; color:#7dd3fc; }
    img.thumb { height:32px; width:auto; border-radius:6px; border:1px solid #1f2937; object-fit:cover; }
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
'@

Write-Text "stays\templates\stays\list.html" @'
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
          <tr>
            <th>Photo</th><th>Name</th><th>City</th><th>State</th>
            <th>Rating</th><th>Hookups</th><th>Price/Night</th><th></th>
          </tr>
        </thead>
        <tbody>
        {% for s in stays %}
          <tr>
            <td>{% if s.photo %}<img class="thumb" src="{{ s.photo.url }}" alt="{{ s.name }}">{% else %}<span class="muted">-</span>{% endif %}</td>
            <td><a href="{% url 'stay_detail' s.id %}">{{ s.name }}</a>{% if s.is_background %} <span class="muted">• background</span>{% endif %}</td>
            <td>{{ s.city }}</td>
            <td>{{ s.state }}</td>
            <td class="muted">{{ s.stars_html|safe }}</td>
            <td>
              {% if s.water_hookup %}Water{% endif %}
              {% if s.sewer_hookup %}{% if s.water_hookup %} / {% endif %}Sewer{% endif %}
              {% if s.electric_30a or s.electric_50a %}{% if s.water_hookup or s.sewer_hookup %} / {% endif %}{% endif %}
              {% if s.electric_30a %}30A{% endif %}{% if s.electric_30a and s.electric_50a %} / {% endif %}{% if s.electric_50a %}50A{% endif %}
              {% if s.electric_extra %}{% if s.water_hookup or s.sewer_hookup or s.electric_30a or s.electric_50a %} / {% endif %}Elect. Extra{% endif %}
              {% if not s.water_hookup and not s.sewer_hookup and not s.electric_30a and not s.electric_50a and not s.electric_extra %}<span class="muted">-</span>{% endif %}
            </td>
            <td class="muted">{% if s.price_night %}${{ s.price_night|floatformat:2 }}{% else %}-{% endif %}</td>
            <td class="actions"><a href="{% url 'stay_edit' s.id %}">Edit</a> <a href="{% url 'stay_delete' s.id %}">Delete</a></td>
          </tr>
        {% empty %}
          <tr><td colspan="8" class="muted">No stays yet. <a href="{% url 'stay_create' %}">Add one</a> or visit the <a href="/map/">map</a>.</td></tr>
        {% endfor %}
        </tbody>
      </table>
    </div>
  </div>
{% endblock %}
'@

Write-Text "stays\templates\stays\detail.html" @'
{% extends "stays/base.html" %}
{% block content %}
  <p><a href="/">← Back</a></p>
  <div class="card">
    <h1 style="margin-top:0;">{{ stay.name }}</h1>
    {% if stay.photo %}
      <img src="{{ stay.photo.url }}" alt="" style="max-width:600px;width:100%;height:auto;border-radius:10px;border:1px solid #1f2937;">
      <p class="muted" style="margin:6px 0 0;">{% if stay.is_background %}This photo is used as the site background.{% else %}&nbsp;{% endif %}</p>
    {% endif %}
    <dl style="display:grid;grid-template-columns:max-content 1fr;gap:8px 16px; margin-top:12px;">
      <dt>City</dt><dd>{{ stay.city }}</dd>
      <dt>State</dt><dd>{{ stay.state }}</dd>
      <dt>Rating</dt><dd>{{ stay.stars_html|safe }}</dd>
      <dt>Hookups</dt>
      <dd>
        {% if stay.water_hookup %}Water{% endif %}
        {% if stay.sewer_hookup %}{% if stay.water_hookup %} / {% endif %}Sewer{% endif %}
        {% if stay.electric_30a or stay.electric_50a %}{% if stay.water_hookup or stay.sewer_hookup %} / {% endif %}{% endif %}
        {% if stay.electric_30a %}30A{% endif %}{% if stay.electric_30a and stay.electric_50a %} / {% endif %}{% if stay.electric_50a %}50A{% endif %}
        {% if stay.electric_extra %}{% if stay.water_hookup or stay.sewer_hookup or stay.electric_30a or stay.electric_50a %} / {% endif %}Elect. Extra{% endif %}
        {% if not stay.water_hookup and not stay.sewer_hookup and not stay.electric_30a and not stay.electric_50a and not stay.electric_extra %}-{% endif %}
      </dd>
      <dt>Price/Night</dt><dd>{% if stay.price_night %}${{ stay.price_night|floatformat:2 }}{% else %}-{% endif %}</dd>
      <dt>Latitude</dt><dd>{{ stay.latitude|default:"-" }}</dd>
      <dt>Longitude</dt><dd>{{ stay.longitude|default:"-" }}</dd>
    </dl>
    <p class="actions" style="margin-top:12px;">
      <a class="btn btn-outline" href="{% url 'stay_edit' stay.id %}">Edit</a>
      <a class="btn btn-outline" href="{% url 'stay_delete' stay.id %}">Delete</a>
      <a class="btn" href="/map/">View on Map</a>
    </p>
  </div>
{% endblock %}
'@

Write-Text "stays\templates\stays\form.html" @'
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
'@

Write-Text "stays\templates\stays\map.html" @'
{% extends "stays/base.html" %}
{% block head %}
  <style>#map { height: 70vh; border-radius: 8px; border:1px solid #1f2937; }</style>
{% endblock %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">Map</h1>
    <div id="map"></div>
  </div>
  <script type="application/json" id="stays-data">{{ stays_json|safe }}</script>
  <script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"></script>
  <script>
    function stars(n) {
      if (!n) return "&minus;";
      n = Math.max(1, Math.min(5, Number(n)));
      const full = "&#9733;".repeat(n);
      const empty = "&#9734;".repeat(5 - n);
      return full + empty;
    }
    function hookups(s) {
      const parts = [];
      if (s.water_hookup) parts.push("Water");
      if (s.sewer_hookup) parts.push("Sewer");
      const elec = [s.electric_30a ? "30A" : null, s.electric_50a ? "50A" : null].filter(Boolean).join("/");
      if (elec) parts.push(elec);
      if (s.electric_extra) parts.push("Elect. Extra");
      return parts.length ? parts.join(" / ") : "-";
    }
    function price(v) {
      if (v === null || v === undefined || v === "") return "-";
      const n = Number(v);
      if (Number.isFinite(n)) return "$" + n.toFixed(2);
      return "-";
    }

    const map = L.map('map').setView([39.5, -98.35], 4);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {maxZoom:19, attribution:'© OpenStreetMap'}).addTo(map);

    const stays = JSON.parse(document.getElementById('stays-data').textContent || '[]');
    const markers = [];
    stays.forEach(s => {
      if (typeof s.latitude === 'number' && typeof s.longitude === 'number') {
        const html = `
          <div style="min-width:240px;">
            <div style="font-weight:700; margin-bottom:4px;">${s.name ?? 'Stay'}</div>
            <div style="color:#94a3b8; margin-bottom:6px;">${(s.city||'')}${s.city&&s.state?', ':''}${s.state||''}</div>
            <div><strong>Rating:</strong> <span>${stars(s.rating)}</span> ${s.rating ? `(${s.rating}/5)` : ''}</div>
            <div><strong>Hookups:</strong> ${hookups(s)}</div>
            <div><strong>Price/Night:</strong> ${price(s.price_night)}</div>
            <div style="margin-top:8px;">
              <a href="/stay/${s.id}/" class="btn btn-outline" style="padding:4px 8px;">Open</a>
              <a href="/stays/${s.id}/edit/" class="btn btn-outline" style="padding:4px 8px; margin-left:6px;">Edit</a>
            </div>
          </div>
        `;
        const m = L.marker([s.latitude, s.longitude]).addTo(map).bindPopup(html, { maxWidth: 280 });
        markers.push(m);
      }
    });
    if (markers.length) { const g = L.featureGroup(markers); map.fitBounds(g.getBounds().pad(0.2)); }
  </script>
{% endblock %}
'@

Write-Text "stays\templates\stays\charts.html" @'
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
'@

Write-Text "stays\templates\stays\appearance.html" @'
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">Appearance</h1>
    <p class="muted">Using defaults. The <code>SiteAppearance</code> model is optional; the site still works.</p>
    <dl>
      <dt>Site Name</dt><dd>{{ site_appearance.site_name }}</dd>
      <dt>Primary Color</dt><dd>{{ site_appearance.primary_color }}</dd>
      <dt>Secondary Color</dt><dd>{{ site_appearance.secondary_color }}</dd>
    </dl>
  </div>
{% endblock %}
'@

Write-Text "stays\templates\stays\import.html" @'
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1 style="margin-top:0;">Import CSV</h1>
    <p>Columns: <code>name, city, state, latitude, longitude, rating, water_hookup, sewer_hookup, electric_30a, electric_50a, price_night, electric_extra</code>.</p>
    <form method="post" enctype="multipart/form-data">
      {% csrf_token %}
      <input type="file" name="file" accept=".csv" class="txt" style="max-width:unset;">
      <button class="btn" style="margin-left:8px;">Upload</button>
    </form>
  </div>
{% endblock %}
'@

Write-Text "stays\templates\stays\confirm_delete.html" @'
{% extends "stays/base.html" %}
{% block content %}
  <div class="card">
    <h1>Delete: {{ stay.name }}</h1>
    <p>Are you sure you want to delete this stay?</p>
    <form method="post">{% csrf_token %}<button class="btn">Yes, delete</button> <a class="btn btn-outline" href="{% url 'stay_detail' stay.id %}">Cancel</a></form>
  </div>
{% endblock %}
'@

# ---------- requirements.txt ----------
Write-Text "requirements.txt" @'
Django>=5.2.1
requests>=2.32
Pillow>=10.0
'@

Write-Host "`nAll files written."
Write-Host "Next:"
Write-Host "  venv\Scripts\activate"
Write-Host "  pip install -r requirements.txt"
Write-Host "  python manage.py makemigrations"
Write-Host "  python manage.py migrate"
Write-Host "  python manage.py runserver"

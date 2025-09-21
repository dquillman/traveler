# autofix_stays.py
from __future__ import annotations
from pathlib import Path
from datetime import datetime
import re
import subprocess
import sys

PROJ = Path.cwd()
APP = PROJ / "stays"
URLS = APP / "urls.py"
VIEWS = APP / "views.py"
TPL_DIR = APP / "templates" / "stays"
LIST_HTML = TPL_DIR / "stay_list.html"
MAP_HTML = TPL_DIR / "map.html"
FORM_HTML = TPL_DIR / "stay_form.html"
DETAIL_HTML = TPL_DIR / "stay_detail.html"

def ts() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")

def backup(p: Path):
    if p.exists():
        p.with_suffix(p.suffix + f".{ts()}.bak").write_bytes(p.read_bytes())

def ensure_dirs():
    APP.mkdir(parents=True, exist_ok=True)
    TPL_DIR.mkdir(parents=True, exist_ok=True)

def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""

def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    backup(path)
    path.write_text(text, encoding="utf-8", newline="\n")

URLS_WANTED = """from django.urls import path
from . import views

app_name = "stays"

urlpatterns = [
    path("", views.stay_list, name="list"),
    path("map/", views.stay_map, name="map"),
    path("add/", views.stay_add, name="add"),
    path("<int:pk>/", views.stay_detail, name="detail"),
    path("<int:pk>/edit/", views.stay_edit, name="edit"),
]
"""

VIEWS_BLOCK = """import json
from urllib.parse import urlencode

from django.shortcuts import render, get_object_or_404, redirect
from django.db.models import Count, Sum, Avg
from django.db.models.functions import TruncDate

from .models import Stay

# Try to use your app's form; fallback to a simple ModelForm
try:
    from .forms import StayForm
except Exception:
    from django.forms import ModelForm
    class StayForm(ModelForm):
        class Meta:
            model = Stay
            fields = "__all__"

def _apply_stay_filters(qs, request):
    \"\"\"Apply multi-filters: state, city, rating (if rating field exists).\"\"\"
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

    field_names = {getattr(f, "attname", None) or getattr(f, "name", None) for f in Stay._meta.get_fields()}
    if ratings_clean and "rating" in field_names:
        qs = qs.filter(rating__in=ratings_clean)

    return qs

def stay_list(request):
    qs = Stay.objects.all()
    state_choices = list(Stay.objects.values_list("state", flat=True)
                         .exclude(state__isnull=True).exclude(state__exact="")
                         .distinct().order_by("state"))
    city_choices  = list(Stay.objects.values_list("city", flat=True)
                         .exclude(city__isnull=True).exclude(city__exact="")
                         .distinct().order_by("city"))
    rating_choices = [1, 2, 3, 4, 5]

    qs = _apply_stay_filters(qs, request)

    selected_states  = request.GET.getlist("state")  or ([request.GET.get("state")]  if request.GET.get("state")  else [])
    selected_cities  = request.GET.getlist("city")   or ([request.GET.get("city")]   if request.GET.get("city")   else [])
    selected_ratings = request.GET.getlist("rating") or ([request.GET.get("rating")] if request.GET.get("rating") else [])
    selected_ratings = [str(r) for r in selected_ratings]

    qs_params = []
    for s in selected_states:  qs_params.append(("state", s))
    for c in selected_cities:  qs_params.append(("city", c))
    for r in selected_ratings: qs_params.append(("rating", r))
    map_query = urlencode(qs_params)

    return render(request, "stays/stay_list.html", {
        "stays": qs,
        "state_choices": state_choices,
        "city_choices": city_choices,
        "rating_choices": rating_choices,
        "selected_states": selected_states,
        "selected_cities": selected_cities,
        "selected_ratings": selected_ratings,
        "map_query": map_query,
    })

def stay_map(request):
    \"\"\"Leaflet map of stays; zooms to filtered stays if filters present, otherwise all.\"\"\"
    qs = _apply_stay_filters(Stay.objects.all(), request)
    qs = qs.exclude(latitude__isnull=True).exclude(longitude__isnull=True)
    points = []
    for s in qs:
        points.append({
            "lat": float(s.latitude) if s.latitude is not None else None,
            "lng": float(s.longitude) if s.longitude is not None else None,
            "title": f"{getattr(s, 'park', '')}".strip() or f"Stay {s.pk}",
            "subtitle": f"{getattr(s, 'city', '')}, {getattr(s, 'state', '')}".strip(", "),
        })
    return render(request, "stays/map.html", {"stays_json": json.dumps(points)})

def stay_detail(request, pk):
    obj = get_object_or_404(Stay, pk=pk)
    return render(request, "stays/stay_detail.html", {"stay": obj})

def stay_add(request):
    if request.method == "POST":
        form = StayForm(request.POST)
        if form.is_valid():
            obj = form.save()
            return redirect("stays:detail", pk=obj.pk)
    else:
        form = StayForm()
    return render(request, "stays/stay_form.html", {"form": form})

def stay_edit(request, pk):
    obj = get_object_or_404(Stay, pk=pk)
    if request.method == "POST":
        form = StayForm(request.POST, instance=obj)
        if form.is_valid():
            obj = form.save()
            return redirect("stays:detail", pk=obj.pk)
    else:
        form = StayForm(instance=obj)
    return render(request, "stays/stay_form.html", {"form": form, "stay": obj})
"""

LIST_TEMPLATE = """{% extends 'base.html' %}
{% block title %}Stays{% endblock %}
{% block content %}
<div class="container mx-auto px-4 py-6">
  <h1 class="text-2xl font-semibold mb-3">Stays</h1>
  <p class="mb-4"><a class="btn btn-primary" href="{% url 'stays:add' %}">Add Stay</a></p>

  <form method="get" class="mb-6 space-y-3">
    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <div>
        <label class="block font-medium mb-1">State</label>
        <select name="state" multiple size="6" class="w-full border rounded p-2">
          {% for s in state_choices %}
            <option value="{{ s }}" {% if s in selected_states %}selected{% endif %}>{{ s }}</option>
          {% endfor %}
        </select>
      </div>
      <div>
        <label class="block font-medium mb-1">City</label>
        <select name="city" multiple size="6" class="w-full border rounded p-2">
          {% for c in city_choices %}
            <option value="{{ c }}" {% if c in selected_cities %}selected{% endif %}>{{ c }}</option>
          {% endfor %}
        </select>
      </div>
      <div>
        <label class="block font-medium mb-1">Rating</label>
        <select name="rating" multiple size="6" class="w-full border rounded p-2">
          {% for r in rating_choices %}
            <option value="{{ r }}" {% if r|stringformat:"s" in selected_ratings %}selected{% endif %}>{{ r }}</option>
          {% endfor %}
        </select>
      </div>
    </div>
    <div class="flex gap-3 mt-2">
      <button type="submit" class="btn btn-primary">Apply Filters</button>
      <a class="btn" href="{% url 'stays:list' %}">Clear</a>
      <a class="btn" href="{% url 'stays:map' %}{% if map_query %}?{{ map_query }}{% endif %}">View Filter on Map</a>
    </div>
  </form>

  <ul class="space-y-2">
    {% for s in stays %}
      <li class="p-3 rounded-lg border">
        <a href="{% url 'stays:detail' s.pk %}">
          {{ s.park }} {{ s.site }} {{ s.city }} {{ s.state }}
        </a>
        <span class="text-sm opacity-70">lat: {{ s.latitude }} lng: {{ s.longitude }}</span>
        [<a href="{% url 'stays:edit' s.pk %}">edit</a>]
      </li>
    {% empty %}
      <li>No stays yet.</li>
    {% endfor %}
  </ul>
</div>
{% endblock %}
"""

MAP_TEMPLATE = """{% extends 'base.html' %}
{% block title %}Stays Map{% endblock %}
{% block content %}
<div class="container mx-auto px-4 py-6">
  <h1 class="text-2xl font-semibold mb-4">Stays Map</h1>
  <div id="map" style="height: 70vh; border-radius: 10px; overflow: hidden;"></div>
  <p class="mt-4">
    <a class="btn" href="{% url 'stays:list' %}">Back to list</a>
  </p>
</div>

<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin=""/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin=""></script>

<script>
  const stays = JSON.parse(document.getElementById('stays-data').textContent);

  let center = [39.5, -98.35];
  const map = L.map('map').setView(center, stays.length ? 5 : 4);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19, attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);

  const group = L.featureGroup();
  stays.forEach(s => {
    if (s.lat == null || s.lng == null) return;
    const m = L.marker([s.lat, s.lng]).bindPopup(`<strong>${s.title}</strong><br>${s.subtitle}`);
    group.addLayer(m);
  });
  if (group.getLayers().length) {
    group.addTo(map);
    map.fitBounds(group.getBounds().pad(0.2));
  }
</script>

<script type="application/json" id="stays-data">{{ stays_json|safe }}</script>
{% endblock %}
"""

FORM_TEMPLATE = """{% extends 'base.html' %}
{% block title %}{{ stay|default_if_none:'New' }} Stay{% endblock %}
{% block content %}
<div class="container mx-auto px-4 py-6 max-w-xl">
  <h1 class="text-2xl font-semibold mb-4">{% if stay %}Edit{% else %}Add{% endif %} Stay</h1>
  <form method="post" class="space-y-4">
    {% csrf_token %}
    {{ form.non_field_errors }}
    {% for field in form.visible_fields %}
      <div>
        {{ field.label_tag }} {{ field }}
        {% if field.help_text %}<small class="opacity-70">{{ field.help_text }}</small>{% endif %}
        {{ field.errors }}
      </div>
    {% endfor %}
    <div class="flex gap-3">
      <button type="submit" class="btn btn-primary">Save</button>
      <a href="{% url 'stays:list' %}" class="btn">Cancel</a>
    </div>
  </form>
</div>
{% endblock %}
"""

DETAIL_TEMPLATE = """{% extends 'base.html' %}
{% block title %}Stay{% endblock %}
{% block content %}
<div class="container mx-auto px-4 py-6 max-w-3xl">
  <h1 class="text-2xl font-semibold mb-2">{{ stay.park }} {{ stay.site }}</h1>
  <p class="opacity-80 mb-4">{{ stay.city }}, {{ stay.state }}</p>
  <div class="grid grid-cols-2 gap-4 mb-6">
    <div><strong>Latitude:</strong> {{ stay.latitude }}</div>
    <div><strong>Longitude:</strong> {{ stay.longitude }}</div>
  </div>
  <div class="flex gap-4">
    <a class="btn btn-primary" href="{% url 'stays:edit' stay.pk %}">Edit</a>
    <a class="btn" href="{% url 'stays:list' %}">Back</a>
  </div>
</div>
{% endblock %}
"""

def ensure_urls():
    txt = read(URLS)
    changed = False
    if not txt.strip():
        write(URLS, URLS_WANTED)
        print("• Created stays/urls.py")
        return
    if "app_name" not in txt:
        txt = "app_name = 'stays'\n" + txt
        changed = True
    needed = {
        "name=\"list\"": "path(\"\", views.stay_list, name=\"list\"),",
        "name=\"map\"": "path(\"map/\", views.stay_map, name=\"map\"),",
        "name=\"add\"": "path(\"add/\", views.stay_add, name=\"add\"),",
        "name=\"detail\"": "path(\"<int:pk>/\", views.stay_detail, name=\"detail\"),",
        "name=\"edit\"": "path(\"<int:pk>/edit/\", views.stay_edit, name=\"edit\"),",
    }
    if "from django.urls import path" not in txt:
        txt = "from django.urls import path\n" + txt
        changed = True
    if "from . import views" not in txt:
        txt = txt.replace("from django.urls import path\n",
                          "from django.urls import path\nfrom . import views\n")
        if "from . import views" not in txt:
            txt = "from . import views\n" + txt
        changed = True
    if "urlpatterns" not in txt:
        txt += "\nurlpatterns = []\n"
        changed = True
    # append missing routes non-destructively
    to_add = []
    for key, line in needed.items():
        if key not in txt and key.replace('"', "'") not in txt:
            to_add.append("    " + line)
    if to_add:
        txt += "\n# auto-added by autofix\nurlpatterns += [\n" + "\n".join(to_add) + "\n]\n"
        changed = True
    if changed:
        write(URLS, txt)
        print("• Updated stays/urls.py")
    else:
        print("• stays/urls.py OK")

def ensure_views():
    txt = read(VIEWS)
    if not txt.strip():
        write(VIEWS, VIEWS_BLOCK)
        print("• Created stays/views.py (full block)")
        return
    changed = False
    # Ensure imports we rely on
    if "from django.shortcuts import render" not in txt:
        txt = "from django.shortcuts import render, get_object_or_404, redirect\n" + txt
        changed = True
    if "from urllib.parse import urlencode" not in txt:
        txt = "from urllib.parse import urlencode\n" + txt
        changed = True
    if "from .models import Stay" not in txt:
        txt = "from .models import Stay\n" + txt
        changed = True

    def need(name: str) -> bool:
        return f"def {name}(" not in txt

    blocks = []
    if "_apply_stay_filters" not in txt:
        blocks.append(VIEWS_BLOCK.split("def _apply_stay_filters",1)[1].split("def stay_list",1)[0])
        # prepend def line back
        blocks[-1] = "def _apply_stay_filters" + blocks[-1]
    if need("stay_list"):
        blocks.append("def stay_list" + VIEWS_BLOCK.split("def stay_list",1)[1].split("def stay_map",1)[0])
    if need("stay_map"):
        blocks.append("def stay_map" + VIEWS_BLOCK.split("def stay_map",1)[1].split("def stay_detail",1)[0])
    if need("stay_detail"):
        blocks.append("def stay_detail" + VIEWS_BLOCK.split("def stay_detail",1)[1].split("def stay_add",1)[0])
    if need("stay_add"):
        blocks.append("def stay_add" + VIEWS_BLOCK.split("def stay_add",1)[1].split("def stay_edit",1)[0])
    if need("stay_edit"):
        blocks.append("def stay_edit" + VIEWS_BLOCK.split("def stay_edit",1)[1])

    if blocks:
        txt = txt.rstrip() + "\n\n# --- auto-added by autofix_stays.py ---\n" + "\n\n".join(b.rstrip() for b in blocks) + "\n"
        changed = True

    if changed:
        write(VIEWS, txt)
        print("• Updated stays/views.py")
    else:
        print("• stays/views.py OK")

def ensure_templates():
    created = 0
    if not LIST_HTML.exists():
        write(LIST_HTML, LIST_TEMPLATE); created += 1; print("• Wrote stay_list.html")
    else:
        print("• stay_list.html OK")
    if not MAP_HTML.exists():
        write(MAP_HTML, MAP_TEMPLATE); created += 1; print("• Wrote map.html")
    else:
        print("• map.html OK")
    if not FORM_HTML.exists():
        write(FORM_HTML, FORM_TEMPLATE); created += 1; print("• Wrote stay_form.html")
    else:
        print("• stay_form.html OK")
    if not DETAIL_HTML.exists():
        write(DETAIL_HTML, DETAIL_TEMPLATE); created += 1; print("• Wrote stay_detail.html")
    else:
        print("• stay_detail.html OK")
    return created

def main():
    ensure_dirs()
    ensure_urls()
    ensure_views()
    ensure_templates()

    # Try to run the verifier if present
    verifier = PROJ / "verify_stays_setup.py"
    if verifier.exists():
        print("\nRunning verify_stays_setup.py ...")
        # Use the same interpreter
        try:
            proc = subprocess.run([sys.executable, str(verifier), "-v"], check=False)
            if proc.returncode == 0:
                print("✅ Verifier passed")
            else:
                print(f"⚠ Verifier returned non-zero exit code: {proc.returncode}")
        except Exception as e:
            print(f"⚠ Could not invoke verifier: {e}")
    else:
        print("\nTip: add verify_stays_setup.py and re-run this script to auto-check routes/templates.")

if __name__ == "__main__":
    main()

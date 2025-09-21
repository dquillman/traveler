# patch_stays_filters.py
from pathlib import Path
from datetime import datetime
import re

PROJ = Path.cwd()
STAYS = PROJ / "stays"
VIEWS = STAYS / "views.py"
URLS  = STAYS / "urls.py"
TPL   = STAYS / "templates" / "stays" / "stay_list.html"

def backup(p: Path):
    if p.exists():
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        p.with_suffix(p.suffix + f".{ts}.bak").write_bytes(p.read_bytes())

def write(p: Path, s: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding="utf-8", newline="\n")

def ensure_urls_list_name():
    txt = URLS.read_text(encoding="utf-8", errors="replace") if URLS.exists() else ""
    changed = False

    if "from django.urls import path" not in txt:
        txt = "from django.urls import path\n" + txt
        changed = True
    if "from . import views" not in txt:
        # add after first import if possible
        if "from django.urls import path\n" in txt:
            txt = txt.replace("from django.urls import path\n", "from django.urls import path\nfrom . import views\n")
        else:
            txt = "from . import views\n" + txt
        changed = True
    if "app_name" not in txt:
        txt += "\napp_name = 'stays'\n"
        changed = True
    if "urlpatterns" not in txt:
        txt += "\nurlpatterns = []\n"
        changed = True
    if "name='list'" not in txt and 'name="list"' not in txt:
        txt += "\n# Ensure list route exists\nurlpatterns += [\n    path('', views.stay_list, name='list'),\n]\n"
        changed = True

    if changed:
        backup(URLS)
        write(URLS, txt)

def patch_views():
    txt = VIEWS.read_text(encoding="utf-8", errors="replace") if VIEWS.exists() else ""

    # Ensure imports
    if "from django.shortcuts import render" not in txt:
        txt = "from django.shortcuts import render\n" + txt
    if "from django.db.models" not in txt:
        txt = "from django.db.models import Count, Sum, Avg\n" + txt
    if "from django.db.models.functions" not in txt:
        txt = "from django.db.models.functions import TruncDate\n" + txt
    if "from .models import Stay" not in txt:
        txt = "from .models import Stay\n" + txt

    # Helper to apply filters (state, city, rating) – multi-select
    if "def _apply_stay_filters(" not in txt:
        txt += """

def _apply_stay_filters(qs, request):
    \"\"\"Apply multi-filters: state (list), city (list), rating (list).
    Works even if 'rating' field doesn't exist (ignored).\"\"\"
    states = request.GET.getlist("state")
    cities = request.GET.getlist("city")
    ratings = request.GET.getlist("rating")
    # Back-compat: allow single values
    if not states and request.GET.get("state"):
        states = [request.GET.get("state")]
    if not cities and request.GET.get("city"):
        cities = [request.GET.get("city")]
    if not ratings and request.GET.get("rating"):
        ratings = [request.GET.get("rating")]
    # Normalize empties
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

    # Only filter rating if the field exists
    field_names = {getattr(f, 'attname', None) or getattr(f, 'name', None) for f in Stay._meta.get_fields()}
    if ratings_clean and 'rating' in field_names:
        qs = qs.filter(rating__in=ratings_clean)

    return qs
"""

    # Update/define stay_list to use filters and provide choices plus querystring for map link
    if "def stay_list(" in txt:
        # Replace the body safely: find def ... stay_list ... next def or EOF
        pattern = re.compile(r"def\s+stay_list\s*\(.*?\):.*?(?=^\s*def\s|\Z)", re.S | re.M)
        def_block = pattern.search(txt)
        new_block = """
def stay_list(request):
    qs = Stay.objects.all()

    # Build distinct choices
    state_choices = list(
        Stay.objects.values_list('state', flat=True).exclude(state__isnull=True).exclude(state__exact='').distinct().order_by('state')
    )
    city_choices = list(
        Stay.objects.values_list('city', flat=True).exclude(city__isnull=True).exclude(city__exact='').distinct().order_by('city')
    )

    # Apply filters
    qs = _apply_stay_filters(qs, request)

    # selected for re-rendering the form
    selected_states = request.GET.getlist('state') or ([request.GET.get('state')] if request.GET.get('state') else [])
    selected_cities = request.GET.getlist('city') or ([request.GET.get('city')] if request.GET.get('city') else [])
    selected_ratings = request.GET.getlist('rating') or ([request.GET.get('rating')] if request.GET.get('rating') else [])

    # Build querystring for "View Filter on Map"
    from urllib.parse import urlencode
    qs_params = []
    for s in selected_states:
        qs_params.append(('state', s))
    for c in selected_cities:
        qs_params.append(('city', c))
    for r in selected_ratings:
        qs_params.append(('rating', r))
    map_query = urlencode(qs_params)

    return render(request, "stays/stay_list.html", {
        "stays": qs,
        "state_choices": state_choices,
        "city_choices": city_choices,
        "selected_states": selected_states,
        "selected_cities": selected_cities,
        "selected_ratings": selected_ratings,
        "map_query": map_query,
    })
"""
        if def_block:
            txt = txt[:def_block.start()] + new_block + txt[def_block.end():]
        else:
            txt += "\n\n" + new_block
    else:
        # Define fresh stay_list
        txt += """
def stay_list(request):
    qs = Stay.objects.all()
    state_choices = list(
        Stay.objects.values_list('state', flat=True).exclude(state__isnull=True).exclude(state__exact='').distinct().order_by('state')
    )
    city_choices = list(
        Stay.objects.values_list('city', flat=True).exclude(city__isnull=True).exclude(city__exact='').distinct().order_by('city')
    )
    qs = _apply_stay_filters(qs, request)

    selected_states = request.GET.getlist('state') or ([request.GET.get('state')] if request.GET.get('state') else [])
    selected_cities = request.GET.getlist('city') or ([request.GET.get('city')] if request.GET.get('city') else [])
    selected_ratings = request.GET.getlist('rating') or ([request.GET.get('rating')] if request.GET.get('rating') else [])

    from urllib.parse import urlencode
    qs_params = []
    for s in selected_states: qs_params.append(('state', s))
    for c in selected_cities: qs_params.append(('city', c))
    for r in selected_ratings: qs_params.append(('rating', r))
    map_query = urlencode(qs_params)

    return render(request, "stays/stay_list.html", {
        "stays": qs,
        "state_choices": state_choices,
        "city_choices": city_choices,
        "selected_states": selected_states,
        "selected_cities": selected_cities,
        "selected_ratings": selected_ratings,
        "map_query": map_query,
    })
"""

    # Make stay_map honor filters (fit to filtered when filters present; otherwise all)
    if "def stay_map(" in txt:
        # Patch the query inside stay_map
        txt = re.sub(
            r"qs\s*=\s*Stay\.objects\.exclude\(latitude__isnull=True\)\.exclude\(longitude__isnull=True\)",
            "qs = _apply_stay_filters(Stay.objects.all(), request).exclude(latitude__isnull=True).exclude(longitude__isnull=True)",
            txt
        )

    backup(VIEWS)
    write(VIEWS, txt)

def write_template():
    # Original-ish layout + filters + "View Filter on Map"
    html = """{% extends 'base.html' %}
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
          {% for r in "1,2,3,4,5".split(",") %}
            <option value="{{ r }}" {% if r in selected_ratings %}selected{% endif %}>{{ r }}</option>
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
    backup(TPL)
    write(TPL, html)

def main():
    ensure_urls_list_name()
    patch_views()
    write_template()
    print("Stays list restored + multi-filters + 'View Filter on Map' wired. Map view now honors filters.")

if __name__ == "__main__":
    main()

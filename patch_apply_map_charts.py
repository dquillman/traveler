
from pathlib import Path
from datetime import datetime
import re, json

PROJ = Path.cwd()
STAYS = PROJ / "stays"
TPL_DIR = STAYS / "templates" / "stays"
URLS = STAYS / "urls.py"
VIEWS = STAYS / "views.py"

def backup(p: Path):
    if p.exists():
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        p.with_suffix(p.suffix + f".{ts}.bak").write_bytes(p.read_bytes())

def write_file(p: Path, content: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8", newline="\n")

# --- Templates ---
MAP_HTML = r'''{% extends 'base.html' %}
{% block title %}Stays Map{% endblock %}
{% block content %}
<div class="container mx-auto px-4 py-6">
  <h1 class="text-2xl font-semibold mb-4">Stays Map</h1>
  <div id="map" style="height: 70vh; border-radius: 10px; overflow: hidden;"></div>
  <p class="mt-4"><a class="btn" href="{% url 'stays:list' %}">Back to list</a> | <a class="btn" href="{% url 'stays:charts' %}">Charts</a></p>
</div>

<!-- Leaflet CSS/JS -->
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin=""/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>

<script>
  const stays = JSON.parse(document.getElementById('stays-data').textContent);
  let center = [39.5, -98.35];
  if (stays.length) {
    const first = stays.find(s => s.lat !== null && s.lng !== null);
    if (first) center = [first.lat, first.lng];
  }
  const map = L.map('map').setView(center, stays.length ? 5 : 4);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);

  const group = L.featureGroup();
  stays.forEach(s => {
    if (s.lat === null || s.lng === null) return;
    const m = L.marker([s.lat, s.lng]).bindPopup(`<strong>${s.title}</strong><br>${s.subtitle}`);
    group.addLayer(m);
  });
  if (group.getLayers().length) {
    group.addTo(map);
    map.fitBounds(group.getBounds().pad(0.2));
  }
</script>

<script type="application/json" id="stays-data">{{ stays_json|safe }}</script>
{% endblock %}'''

CHARTS_HTML = r'''{% extends 'base.html' %}
{% block title %}Stays Charts{% endblock %}
{% block content %}
<div class="container mx-auto px-4 py-6">
  <h1 class="text-2xl font-semibold mb-6">Stays — Charts</h1>

  <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
    <div>
      <h2 class="font-semibold mb-2">Stays per State</h2>
      <canvas id="staysByState"></canvas>
    </div>
    <div>
      <h2 class="font-semibold mb-2">Nights by State</h2>
      <canvas id="nightsByState"></canvas>
      <p class="opacity-70 text-sm mt-2">If empty, your model may not have a <code>nights</code> field.</p>
    </div>
    <div class="lg:col-span-2">
      <h2 class="font-semibold mb-2">Price per Night (avg) over Time</h2>
      <canvas id="priceTrend"></canvas>
      <p class="opacity-70 text-sm mt-2">If empty, your model may not have <code>price_per_night</code> and/or <code>check_in</code>.</p>
    </div>
  </div>

  <p class="mt-6"><a class="btn" href="{% url 'stays:list' %}">Back to list</a> | <a class="btn" href="{% url 'stays:map' %}">Map</a></p>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<script>
  const staysByState = JSON.parse(document.getElementById('stays-by-state').textContent);
  const nightsByState = JSON.parse(document.getElementById('nights-by-state').textContent);
  const priceTrend = JSON.parse(document.getElementById('price-trend').textContent);

  const sbsLabels = Object.keys(staysByState);
  const sbsValues = Object.values(staysByState);
  new Chart(document.getElementById('staysByState'), {
    type: 'bar',
    data: { labels: sbsLabels, datasets: [{ label: 'Stays per State', data: sbsValues }] },
    options: { responsive: true, plugins: { legend: { display: false } } }
  });

  const nbsLabels = Object.keys(nightsByState);
  const nbsValues = Object.values(nightsByState);
  if (nbsLabels.length) {
    new Chart(document.getElementById('nightsByState'), {
      type: 'pie',
      data: { labels: nbsLabels, datasets: [{ data: nbsValues }] },
      options: { responsive: true }
    });
  }

  const ptLabels = Object.keys(priceTrend);
  const ptValues = Object.values(priceTrend);
  if (ptLabels.length) {
    new Chart(document.getElementById('priceTrend'), {
      type: 'line',
      data: { labels: ptLabels, datasets: [{ label: 'Avg $/night', data: ptValues, fill: false }] },
      options: { responsive: true, scales: { x: { ticks: { autoSkip: true, maxTicksLimit: 12 } } } }
    });
  }
</script>

<script type="application/json" id="stays-by-state">{{ stays_by_state_json|safe }}</script>
<script type="application/json" id="nights-by-state">{{ nights_by_state_json|safe }}</script>
<script type="application/json" id="price-trend">{{ price_trend_json|safe }}</script>
{% endblock %}'''

def ensure_templates():
    write_file(TPL_DIR / "map.html", MAP_HTML)
    write_file(TPL_DIR / "charts.html", CHARTS_HTML)

# --- URLs ---
def ensure_urls():
    if not URLS.exists():
        content = (
            "from django.urls import path\n"
            "from . import views\n\n"
            "app_name = 'stays'\n\n"
            "urlpatterns = [\n"
            "    path('', views.stay_list, name='list'),\n"
            "    path('map/', views.stay_map, name='map'),\n"
            "    path('charts/', views.stay_charts, name='charts'),\n"
            "    path('add/', views.stay_add, name='add'),\n"
            "    path('<int:pk>/', views.stay_detail, name='detail'),\n"
            "    path('<int:pk>/edit/', views.stay_edit, name='edit'),\n"
            "]\n"
        )
        write_file(URLS, content); return

    txt = URLS.read_text(encoding="utf-8", errors="replace")
    orig = txt
    if "from django.urls" not in txt:
        txt = "from django.urls import path\n" + txt
    if re.search(r"from\s+\.\s+import\s+views", txt) is None:
        txt = re.sub(r"(from\s+django\.urls\s+import[^\n]*\n)", r"\\1from . import views\n", txt, count=1) or ("from . import views\n" + txt)
    if "app_name" not in txt:
        txt = re.sub(r"(from\s+\.\s+import\s+views[^\n]*\n)", r"\\1\napp_name = 'stays'\\n", txt, count=1) or (txt + "\napp_name = 'stays'\n")
    if "urlpatterns" not in txt:
        txt += "\nurlpatterns = []\n"

    def add_route(pattern, view, name):
        nonlocal txt
        if re.search(rf"name\\s*=\\s*['\\\"]{name}['\\\"]", txt):
            return
        txt = re.sub(r"urlpatterns\\s*=\\s*\\[",
                     lambda m: m.group(0) + f"\\n    path('{pattern}', views.{view}, name='{name}'),",
                     txt, count=1)

    add_route("map/", "stay_map", "map")
    add_route("charts/", "stay_charts", "charts")

    if txt != orig:
        backup(URLS)
        write_file(URLS, txt)

# --- Views ---
VIEWS_BLOCK = r'''
import json
from django.shortcuts import render
from django.db.models import Count, Sum, Avg
from django.db.models.functions import TruncDate

def stay_map(request):
    try:
        from .models import Stay
    except Exception:
        stays = []
    else:
        qs = Stay.objects.exclude(latitude__isnull=True).exclude(longitude__isnull=True)
        stays = []
        for s in qs:
            stays.append({
                "lat": float(s.latitude) if s.latitude is not None else None,
                "lng": float(s.longitude) if s.longitude is not None else None,
                "title": f"{getattr(s, 'park', '')}".strip() or f"Stay {s.pk}",
                "subtitle": f"{getattr(s, 'city', '')}, {getattr(s, 'state', '')}".strip(", ")
            })
    return render(request, "stays/map.html", {
        "stays_json": json.dumps(stays),
    })

def stay_charts(request):
    try:
        from .models import Stay
    except Exception:
        stays_by_state = {}
        nights_by_state = {}
        price_trend = {}
    else:
        qs = Stay.objects.all()
        sbs_pairs = list(qs.values_list('state').annotate(c=Count('id')).values_list('state', 'c'))
        stays_by_state = { (k or 'Unknown'): int(v or 0) for k, v in sbs_pairs }

        field_names = {f.name for f in Stay._meta.get_fields() if hasattr(f, 'attname')}

        nights_by_state = {}
        if 'nights' in field_names:
            nbs_pairs = list(qs.values_list('state').annotate(total=Sum('nights')).values_list('state', 'total'))
            nights_by_state = { (k or 'Unknown'): int(v or 0) for k, v in nbs_pairs if v is not None }

        price_trend = {}
        if 'price_per_night' in field_names and 'check_in' in field_names:
            rows = list(
                qs.exclude(check_in__isnull=True)
                  .annotate(date=TruncDate('check_in'))
                  .values_list('date')
                  .annotate(avg=Avg('price_per_night'))
                  .values_list('date', 'avg')
                  .order_by('date')
            )
            for d, avg in rows:
                if d is not None and avg is not None:
                    price_trend[d.strftime("%Y-%m-%d")] = float(avg)

    return render(request, "stays/charts.html", {
        "stays_by_state_json": json.dumps(stays_by_state),
        "nights_by_state_json": json.dumps(nights_by_state),
        "price_trend_json": json.dumps(price_trend),
    })
'''

def ensure_views():
    if not VIEWS.exists():
        content = "from django.shortcuts import render\n" + VIEWS_BLOCK
        write_file(VIEWS, content); return

    txt = VIEWS.read_text(encoding="utf-8", errors="replace")
    orig = txt
    if "def stay_map(" not in txt and "def stay_charts(" not in txt:
        txt += "\n\n" + VIEWS_BLOCK
    else:
        if "def stay_map(" not in txt:
            txt += "\n\n" + VIEWS_BLOCK.split("def stay_map",1)[1].split("def stay_charts")[0].join(["def stay_map", ""])
        if "def stay_charts(" not in txt:
            txt += "\n\n" + "def stay_charts" + VIEWS_BLOCK.split("def stay_charts",1)[1]

    if txt != orig:
        backup(VIEWS)
        write_file(VIEWS, txt)

def main():
    (TPL_DIR).mkdir(parents=True, exist_ok=True)
    write_file(TPL_DIR / "map.html", MAP_HTML)
    write_file(TPL_DIR / "charts.html", CHARTS_HTML)
    ensure_urls()
    ensure_views()
    print("Map & Charts installed. Routes: /stays/map/ and /stays/charts/")

if __name__ == "__main__":
    main()

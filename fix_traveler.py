"""
Automated fixer for the Traveler Django project.

This script backs up the existing `views.py`, `urls.py` files and then
replaces them with known-good versions that define the necessary views
(`stay_list`, `stay_map`, `stay_detail`, `stay_add`, `stay_edit`, `stay_charts`,
`appearance_view`, `import_view`, `export_view`, `stays_map_data`) and URL
patterns. Run this script from the root of your project (`traveler`).
"""

import os
import shutil
import datetime

# Contents for stays/views.py
VIEWS_CONTENT = '''import json
from urllib.parse import urlencode

from django.shortcuts import render, get_object_or_404, redirect
from django.db.models import Count, Sum, Avg
from django.db.models.functions import TruncDate
from django.http import JsonResponse

from stays.models import Stay

# Try to use your app's form; fallback to a simple ModelForm
try:
    from stays.forms import StayForm
except Exception:
    from django.forms import ModelForm
    class StayForm(ModelForm):
        class Meta:
            model = Stay
            fields = "__all__"

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
    """Leaflet map of stays; zooms to filtered stays if filters present, otherwise all."""
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

# --- Charts (basic, graceful if fields missing) ---
def stay_charts(request):
    """Three charts: by State, by Year (if date field exists), Rating distribution (if rating exists)."""
    field_names = {getattr(f, "attname", None) or getattr(f, "name", None) for f in Stay._meta.get_fields()}

    # 1) by State
    state_counts = Stay.objects.values_list("state").exclude(state__isnull=True).exclude(state__exact="")
    state_map = {}
    for s, in state_counts:
        state_map[s] = state_map.get(s, 0) + 1
    states = sorted(state_map.keys())
    states_series = [state_map[s] for s in states]

    # 2) by Year (best-effort)
    years_labels, years_series = [], []
    date_field = None
    for cand in ("date", "start_date", "arrival_date", "created", "created_at", "updated", "updated_at"):
        if cand in field_names:
            date_field = cand
            break
    if date_field:
        from django.db.models.functions import ExtractYear
        qs_years = (Stay.objects.exclude(**{f"{date_field}__isnull": True})
                    .annotate(y=ExtractYear(date_field))
                    .values_list("y"))
        ym = {}
        for y, in qs_years:
            if y is None:
                continue
            ym[y] = ym.get(y, 0) + 1
        for y in sorted(ym.keys()):
            years_labels.append(str(y))
            years_series.append(ym[y])

    # 3) Rating distribution
    rating_labels, rating_series = [], []
    if "rating" in field_names:
        vals = Stay.objects.exclude(rating__isnull=True).values_list("rating", flat=True)
        rm = {}
        for r in vals:
            try:
                r = int(r)
                rm[r] = rm.get(r, 0) + 1
            except Exception:
                continue
        for r in sorted(rm.keys()):
            rating_labels.append(str(r))
            rating_series.append(rm[r])

    ctx = {
        "states": json.dumps(states),
        "states_series": json.dumps(states_series),
        "years_labels": json.dumps(years_labels),
        "years_series": json.dumps(years_series),
        "rating_labels": json.dumps(rating_labels),
        "rating_series": json.dumps(rating_series),
        "has_years": bool(years_labels),
        "has_rating": bool(rating_labels),
    }
    return render(request, "stays/charts.html", ctx)

def appearance_view(request):
    """Render a simple Appearance settings page."""
    return render(request, "appearance.html")

def import_view(request):
    """Render the import page for stays."""
    return render(request, "stays/import.html")

def export_view(request):
    """Render the export page for stays."""
    return render(request, "stays/export.html")

def stays_map_data(request):
    """Return JSON data for all stays with latitude and longitude."""
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
    return JsonResponse(points, safe=False)
'''

# Contents for stays/urls.py
STAYS_URLS_CONTENT = '''from django.urls import path
from . import views

app_name = 'stays'

urlpatterns = [
    path('', views.stay_list, name='list'),
    path('add/', views.stay_add, name='add'),
    path('<int:pk>/', views.stay_detail, name='detail'),
    path('<int:pk>/edit/', views.stay_edit, name='edit'),
    path('map/', views.stay_map, name='map'),
    path('charts/', views.stay_charts, name='charts'),
    path('map-data/', views.stays_map_data, name='stays_map_data'),
]
'''

# Contents for config/urls.py
CONFIG_URLS_CONTENT = '''from django.contrib import admin
from django.urls import path, include, reverse_lazy
from django.views.generic.base import RedirectView
from django.shortcuts import render

def appearance_view(request):
    return render(request, "appearance.html")

def import_view(request):
    return render(request, "stays/import.html")

def export_view(request):
    return render(request, "stays/export.html")

urlpatterns = [
    path("", RedirectView.as_view(url=reverse_lazy("stays:list"), permanent=False)),
    path("appearance/", appearance_view, name="appearance"),
    path("import/", import_view, name="import"),
    path("export/", export_view, name="export"),
    path("stays/", include(("stays.urls", "stays"), namespace="stays")),
    path("admin/", admin.site.urls),
]
'''

def backup_and_write(path: str, content: str) -> None:
    """Backup the file at `path` (if it exists) and overwrite it with `content`."""
    if os.path.exists(path):
        timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_path = f"{path}.bak.{timestamp}"
        shutil.copy2(path, backup_path)
        print(f"Backed up {path} to {backup_path}")
    else:
        # ensure parent directories exist
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print(f"Creating {path}")
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
        print(f"Wrote new content to {path}")

def main() -> None:
    project_root = os.path.abspath(os.path.dirname(__file__))
    # Paths relative to project root
    files = {
        os.path.join(project_root, 'stays', 'views.py'): VIEWS_CONTENT,
        os.path.join(project_root, 'stays', 'urls.py'): STAYS_URLS_CONTENT,
        os.path.join(project_root, 'config', 'urls.py'): CONFIG_URLS_CONTENT,
    }
    for path, content in files.items():
        backup_and_write(path, content)

if __name__ == '__main__':
    main()
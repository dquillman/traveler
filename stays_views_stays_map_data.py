# Drop this into stays/views.py (replace the existing stays_map_data)

from django.http import JsonResponse
from django.utils.html import escape
from .models import Stay

def stays_map_data(request):
    qs = Stay.objects.all()

    # Optional filters
    state = request.GET.get("state")
    city = request.GET.get("city")
    if state:
        qs = qs.filter(state__iexact=state)
    if city:
        qs = qs.filter(city__iexact=city)

    qs = qs.exclude(latitude__isnull=True).exclude(longitude__isnull=True)

    out = []
    for s in qs:
        name = getattr(s, "park", None) or getattr(s, "name", "") or f"Stay #{s.pk}"
        city_val = getattr(s, "city", "") or ""
        state_val = getattr(s, "state", "") or ""
        popup = f"<strong>{escape(name)}</strong><br>{escape(city_val)}, {escape(state_val)}"

        out.append({
            "id": s.pk,
            "name": name,
            "latitude": float(s.latitude) if s.latitude is not None else None,
            "longitude": float(s.longitude) if s.longitude is not None else None,
            "popup_html": popup,
        })

    return JsonResponse({"stays": out})

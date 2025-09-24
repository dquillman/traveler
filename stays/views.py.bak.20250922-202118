from io import StringIO
import csv
from django.db.models import Count
from django.http import HttpResponse, StreamingHttpResponse
from django.shortcuts import render, redirect, get_object_or_404
from django.forms import ModelForm
from .models import Stay

class StayForm(ModelForm):
    class Meta:
        model = Stay
        fields = [
            "photo","park","city","state","check_in","leave","nights",
            "rate_per_night","total","fees","paid","site","rating",
            "elect_extra","latitude","longitude"
        ]

def stay_list(request):
    stays = Stay.objects.all().order_by("-check_in")
    return render(request, "stays/stay_list.html", {"stays": stays})

def stay_add(request):
    if request.method == "POST":
        form = StayForm(request.POST, request.FILES)
        if form.is_valid():
            form.save()
            return redirect("stays:list")
    else:
        form = StayForm()
    return render(request, "stays/stay_form.html", {"form": form, "mode": "add"})

def stay_edit(request, pk):
    stay = get_object_or_404(Stay, pk=pk)
    if request.method == "POST":
        form = StayForm(request.POST, request.FILES, instance=stay)
        if form.is_valid():
            form.save()
            return redirect("stays:list")
    else:
        form = StayForm(instance=stay)
    return render(request, "stays/stay_form.html", {"form": form, "mode": "edit", "stay": stay})



































def map_view(request):
    from .models import Stay
    stays = Stay.objects.all()
    return render(request, "pages/map.html", {"stays": stays})

def charts_view(request):
    from .models import Stay
    agg = list(Stay.objects.values("state").annotate(count=Count("id")).order_by("state"))
    labels = [a["state"] or "—" for a in agg]
    data = [a["count"] for a in agg]
    return render(request, "pages/charts.html", {"labels": labels, "data": data})

def import_view(request):
    """
    CSV headers: park,city,state,check_in,leave,nights,rate_per_night,total,fees,paid,site,rating,elect_extra,latitude,longitude
    Dates YYYY-MM-DD; booleans: true/false/1/0/yes/no
    """
    from .models import Stay
    summary = {"created": 0, "errors": []}
    if request.method == "POST" and request.FILES.get("csvfile"):
        f = request.FILES["csvfile"]
        text = f.read().decode("utf-8", errors="ignore")
        rdr = csv.DictReader(StringIO(text))
        def to_bool(s): return (s or '').strip().lower() in ('1','true','yes','y','on')
        def to_int(s):
            try: return int(s)
            except: return None
        def to_dec(s):
            try: return float(s)
            except: return None
        for i, row in enumerate(rdr, start=2):
            try:
                payload = {
                    "park": (row.get("park") or "").strip(),
                    "city": (row.get("city") or "").strip(),
                    "state": (row.get("state") or "").strip(),
                    "check_in": (row.get("check_in") or "").strip() or None,
                    "leave": (row.get("leave") or "").strip() or None,
                    "nights": to_int(row.get("nights")),
                    "rate_per_night": to_dec(row.get("rate_per_night")),
                    "total": to_dec(row.get("total")),
                    "fees": to_dec(row.get("fees")),
                    "paid": to_bool(row.get("paid")),
                    "site": (row.get("site") or "").strip(),
                    "rating": to_int(row.get("rating")),
                    "elect_extra": to_bool(row.get("elect_extra")),
                    "latitude": to_dec(row.get("latitude")),
                    "longitude": to_dec(row.get("longitude")),
                }
                Stay.objects.create(**payload)
                summary["created"] += 1
            except Exception as e:
                summary["errors"].append(f"Line {i}: {e}")
    return render(request, "pages/import.html", {"summary": summary})

def export_view(request):
    from .models import Stay
    rows = Stay.objects.all().order_by("id")
    def gen():
        header = ["id","park","city","state","check_in","leave","nights","rate_per_night","total","fees","paid","site","rating","elect_extra","latitude","longitude"]
        yield ",".join(header) + "\n"
        for s in rows:
            vals = [
                s.id, s.park or "", s.city or "", s.state or "",
                s.check_in.isoformat() if getattr(s, "check_in", None) else "",
                s.leave.isoformat() if getattr(s, "leave", None) else "",
                s.nights or "",
                s.rate_per_night if getattr(s, "rate_per_night", None) is not None else "",
                s.total if getattr(s, "total", None) is not None else "",
                s.fees if getattr(s, "fees", None) is not None else "",
                "true" if s.paid else "false",
                s.site or "",
                s.rating or "",
                "true" if s.elect_extra else "false",
                s.latitude if getattr(s, "latitude", None) is not None else "",
                s.longitude if getattr(s, "longitude", None) is not None else "",
            ]
            yield ",".join(map(lambda x: str(x).replace(",", " "), vals)) + "\n"
    resp = StreamingHttpResponse(gen(), content_type="text/csv")
    resp["Content-Disposition"] = 'attachment; filename="stays_export.csv"'
    return resp

def appearance_view(request):
    return render(request, "pages/appearance.html")

# reset_views_clean.ps1
$ErrorActionPreference = 'Stop'
$file = 'stays\views.py'
if (-not (Test-Path $file)) { Write-Error 'Missing stays\views.py'; exit 1 }

# Backup
$ts  = (Get-Date).ToString('yyyyMMdd_HHmmss')
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

# Clean, minimal working views.py content
$content = @'
# -*- coding: utf-8 -*-
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from django.http import JsonResponse
from django.forms import ModelForm
from .models import Stay

# Try to use your app's StayForm; fallback to a simple ModelForm if missing
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
    states = request.GET.getlist("state") or (
        [request.GET.get("state")] if request.GET.get("state") else []
    )
    cities = request.GET.getlist("city") or (
        [request.GET.get("city")] if request.GET.get("city") else []
    )
    ratings = request.GET.getlist("rating") or (
        [request.GET.get("rating")] if request.GET.get("rating") else []
    )

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
    field_names = {
        getattr(f, "attname", None) or getattr(f, "name", None)
        for f in Stay._meta.get_fields()
    }
    if ratings_clean and "rating" in field_names:
        qs = qs.filter(rating__in=ratings_clean)

    return qs


def stay_list(request):
    qs = Stay.objects.all()

    state_choices = list(
        Stay.objects.values_list("state", flat=True)
        .exclude(state__isnull=True)
        .exclude(state__exact="")
        .distinct()
        .order_by("state")
    )
    city_choices = list(
        Stay.objects.values_list("city", flat=True)
        .exclude(city__isnull=True)
        .exclude(city__exact="")
        .distinct()
        .order_by("city")
    )

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
    qs = Stay.objects.exclude(latitude__isnull=True).exclude(longitude__isnull=True)
    stays = list(qs.values("id", "city", "state", "latitude", "longitude"))
    return JsonResponse({"stays": stays})
'@

# Write the new file
Set-Content -Path $file -Value $content -Encoding UTF8
Write-Host 'Wrote clean stays\views.py'

# Optional: quick syntax check
try {
    & python -m py_compile $file
    Write-Host 'Python compile OK.'
} catch {
    Write-Warning 'Python reported an error. Paste the file/line/caret and we will patch immediately.'
}

# fix_views_v4.ps1
$ErrorActionPreference = "Stop"
$file = "stays\views.py"
if (-not (Test-Path $file)) { Write-Error "Missing stays\views.py"; exit 1 }

# Backup
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup created: $bak"

# Read file
$text = Get-Content -Raw -Encoding UTF8 $file

# ---------- Replacement blocks (plain Python) ----------
$replacement_filters = @'
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

    field_names = {
        getattr(f, "attname", None) or getattr(f, "name", None)
        for f in Stay._meta.get_fields()
    }
    if ratings_clean and "rating" in field_names:
        qs = qs.filter(rating__in=ratings_clean)

    return qs
'@

$replacement_stay_list = @'
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
'@

$replacement_add = @'
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
'@

$replacement_edit = @'
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
'@

# ---------- Helper to replace a Python def by name ----------
function Replace-PyDef {
    param(
        [string]$Source,
        [string]$FuncName,
        [string]$Replacement
    )
    $pattern = "(?ms)^[ \t]*def[ \t]+$([regex]::Escape($FuncName))[ \t]*\([^\)]*\)[ \t]*:[\s\S]*?(?=^[ \t]*def[ \t]+\w+[ \t]*\(|\Z)"
    if ([regex]::IsMatch($Source, $pattern)) {
        return ([regex]::Replace($Source, $pattern, $Replacement))
    } else {
        return $null
    }
}

# Ensure _apply_stay_filters
$updated = Replace-PyDef -Source $text -FuncName "_apply_stay_filters" -Replacement $replacement_filters
if ($null -ne $updated) {
    $text = $updated
    Write-Host "Replaced: _apply_stay_filters"
} else {
    $insertBefore = "(?m)^[ \t]*def[ \t]+stay_list[ \t]*\("
    if ([regex]::IsMatch($text, $insertBefore)) {
        $text = [regex]::Replace($text, $insertBefore, $replacement_filters + "`r`n`r`n" + "def stay_list(", 1)
        Write-Host "Inserted: _apply_stay_filters before stay_list"
    } else {
        $text = $text.TrimEnd() + "`r`n`r`n" + $replacement_filters + "`r`n"
        Write-Host "Appended: _apply_stay_filters at end"
    }
}

# Replace or append stay_list
$updated = Replace-PyDef -Source $text -FuncName "stay_list" -Replacement $replacement_stay_list
if ($null -ne $updated) {
    $text = $updated
    Write-Host "Replaced: stay_list"
} else {
    $text = $text.TrimEnd() + "`r`n`r`n" + $replacement_stay_list + "`r`n"
    Write-Host "Appended: stay_list (missing)"
}

# Replace or append stay_add
$updated = Replace-PyDef -Source $text -FuncName "stay_add" -Replacement $replacement_add
if ($null -ne $updated) {
    $text = $updated
    Write-Host "Replaced: stay_add"
} else {
    $text = $text.TrimEnd() + "`r`n`r`n" + $replacement_add + "`r`n"
    Write-Host "Appended: stay_add (missing)"
}

# Replace or append stay_edit
$updated = Replace-PyDef -Source $text -FuncName "stay_edit" -Replacement $replacement_edit
if ($null -ne $updated) {
    $text = $updated
    Write-Host "Replaced: stay_edit"
} else {
    $text = $text.TrimEnd() +

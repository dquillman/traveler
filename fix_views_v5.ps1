# fix_views_v5.ps1 — minimal + stable
$ErrorActionPreference = "Stop"
$file = "stays\views.py"
if (-not (Test-Path $file)) { Write-Error "Missing stays\views.py"; exit 1 }

# Backup
$ts  = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

function Read-Text { Get-Content -Raw -Encoding UTF8 $file }

# --- Clean function blocks (plain Python) ---
$block_filters = @'
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

$block_stay_list = @'
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

$block_add = @'
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

$block_edit = @'
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

# --- Replace-or-append helper (no string '+' gymnastics) ---
function ReplaceOrAppend {
    param(
        [string]$FuncName,
        [string]$Block
    )
    $pattern = "(?ms)^[ \t]*def[ \t]+$([regex]::Escape($FuncName))[ \t]*\([^\)]*\)[ \t]*:[\s\S]*?(?=^[ \t]*def[ \t]+\w+[ \t]*\(|\Z)"
    $text = Read-Text
    if ([regex]::IsMatch($text, $pattern)) {
        $new = [regex]::Replace($text, $pattern, { param($m) $Block })
        Set-Content -Path $file -Value $new -Encoding UTF8
        Write-Host ("Replaced: {0}" -f $FuncName)
    } else {
        Add-Content -Path $file -Value "`r`n$Block`r`n" -Encoding UTF8
        Write-Host ("Appended: {0}" -f $FuncName)
    }
}

ReplaceOrAppend "_apply_stay_filters" $block_filters
ReplaceOrAppend "stay_list"            $block_stay_list
ReplaceOrAppend "stay_add"             $block_add
ReplaceOrAppend "stay_edit"            $block_edit

Write-Host "Done. Now run:  python -m py_compile stays\views.py"

<#
fix_views_v2.ps1
Replaces broken blocks in stays\views.py with correct Python (no escaping).
Safe to run multiple times. Makes a backup first.
#>

$file = "stays\views.py"
if (-not (Test-Path $file)) { Write-Error "Missing $file"; exit 1 }

# Backup
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

# Load current text
$text = Get-Content -Raw -Encoding UTF8 $file

# ---------- Replacement blobs (plain Python, unescaped) ----------
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

$replacement_add_edit = @'
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
'@

# ---------- Regex patterns (don’t touch) ----------
$opt = [System.Text.RegularExpressions.RegexOptions]::Singleline

# 1) Replace _apply_stay_filters block
$pat_filters = 'def\s+_apply_stay_filters\s*\(.*?^ {0,4}return\s+qs\s*$'
if ($text -match $pat_filters) {
    $text = [regex]::Replace($text, $pat_filters, { param($m) $replacement_filters }, $opt)
    Write-Host "Fixed: _apply_stay_filters"
} else {
    # If a mangled (escaped) version exists, nuke it by matching the def line to the next double newline and reinsert.
    $pat_filters_mangled = 'def\\\s*_apply_stay_filters\\\(.*?)(\r?\n){2,}'
    if ($text -match $pat_filters_mangled) {
        $text = [regex]::Replace($text, $pat_filters_mangled, { param($m) "$replacement_filters`r`n`r`n" }, $opt)
        Write-Host "Fixed: _apply_stay_filters (mangled)"
    } else {
        Write-Warning "Could not locate _apply_stay_filters to replace."
    }
}

# 2) Replace stay_list block (from def to return render(...stay_list.html))
$pat_stay_list = 'def\s+stay_list\s*\(.*?return\s+render\s*\(.*?stays/stay_list\.html.*?\)\s*$'
if ($text -match $pat_stay_list) {
    $text = [regex]::Replace($text, $pat_stay_list, { param($m) $replacement_stay_list }, $opt)
    Write-Host "Fixed: stay_list"
} else {
    Write-Warning "Could not locate stay_list to replace."
}

# 3) Replace stay_add + stay_edit blocks together if possible
$pat_add_edit_combo = 'def\s+stay_add\s*\(.*?stays/stay_form\.html.*?\)\s*[\r\n]+\s*def\s+stay_edit\s*\(.*?stays/stay_form\.html.*?\)\s*'
if ($text -match $pat_add_edit_combo) {
    $text = [regex]::Replace($text, $pat_add_edit_combo, { param($m) $replacement_add_edit }, $opt)
    Write-Host "Fixed: stay_add & stay_edit (combo)"
} else {
    # try separately
    $pat_add = 'def\s+stay_add\s*\(.*?stays/stay_form\.html.*?\)\s*'
    $pat_edit = 'def\s+stay_edit\s*\(.*?stays/stay_form\.html.*?\)\s*'
    $done = $false
    if ($text -match $pat_add) {
        $text = [regex]::Replace($text, $pat_add, { param($m) $replacement_add_edit }, $opt)
        Write-Host "Fixed: stay_add (standalone -> inserted add+edit)"
        $done = $true
    }
    if (-not $done -and $text -match $pat_edit) {
        $text = [regex]::Replace($text, $pat_edit, { param($m) $replacement_add_edit }, $opt)
        Write-Host "Fixed: stay_edit (standalone -> inserted add+edit)"
        $done = $true
    }
    if (-not $done) { Write-Warning "Could not locate stay_add/stay_edit to replace." }
}

# Write out
Set-Content -Path $file -Value $text -Encoding UTF8
Write-Host "Wrote: $file"

# Syntax check
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    Write-Host "Checking syntax wi

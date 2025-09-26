<#
fix_views.ps1
Creates a backup of stays\views.py and attempts to automatically replace
the broken filter/helper and stay add/edit blocks with corrected code.

Run from the project root (where the 'stays' package folder sits):
powershell -ExecutionPolicy Bypass -File .\fix_views.ps1
#>

$file = "stays\views.py"

if (-not (Test-Path $file)) {
    Write-Error "File not found: $file. Run this from your project root where 'stays' folder is located."
    exit 1
}

# Backup
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bak = "$file.bak.$ts"
Copy-Item -Path $file -Destination $bak -Force
Write-Host "Backup created: $bak"

# Read file raw as UTF8
$text = Get-Content -Raw -Encoding UTF8 $file

# Replacement 1: _apply_stay_filters (def ... return qs)
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

$pattern_filters = '(?s)def\s+_apply_stay_filters\s*\(.*?return\s+qs\s*'
if ($text -match $pattern_filters) {
    $text = [regex]::Replace($text, $pattern_filters, [System.Text.RegularExpressions.Regex]::Escape($replacement_filters), [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Write-Host "Replaced _apply_stay_filters block."
} else {
    Write-Warning "Could not find an existing _apply_stay_filters block to replace. No change for filters."
}

# Replacement 2: stay_list top + choices + simple render (replace from def stay_list to the first return render or until qs = _apply_stay_filters)
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

# Pattern: match def stay_list up to the return render(...) that likely ends the function.
$pattern_stay_list = '(?s)def\s+stay_list\s*\(.*?return\s+render\s*\(.*?stays/stay_list\.html.*?\)\s*'

if ($text -match $pattern_stay_list) {
    $text = [regex]::Replace($text, $pattern_stay_list, [System.Text.RegularExpressions.Regex]::Escape($replacement_stay_list), [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Write-Host "Replaced stay_list block."
} else {
    Write-Warning "Could not find a stay_list block matching the expected pattern. No change for stay_list."
}

# Replacement 3: stay_add and stay_edit minimal safe implementations
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

# Pattern: try to find def stay_add ... return render(...) and def stay_edit ... return render(...)
$pattern_add = '(?s)def\s+stay_add\s*\(.*?return\s+render\s*\(.*?stays/stay_form\.html.*?\)\s*'
$pattern_edit = '(?s)def\s+stay_edit\s*\(.*?return\s+render\s*\(.*?stays/stay_form\.html.*?\)\s*'

$foundAdd = $false
$foundEdit = $false

if ($text -match $pattern_add -and $text -match $pattern_edit) {
    # Replace both together by replacing from the first 'def stay_add' up to the end of stay_edit render
    $pattern_add_edit_combo = '(?s)def\s+stay_add\s*\(.*?return\s+render\s*\(.*?stays/stay_form\.html.*?\)\s*.*?def\s+stay_edit\s*\(.*?return\s+render\s*\(.*?stays/stay_form\.html.*?\)\s*'
    if ($text -match $pattern_add_edit_combo) {
        $text = [regex]::Replace($text, $pattern_add_edit_combo, [System.Text.RegularExpressions.Regex]::Escape($replacement_add_edit), [System.Text.RegularExpressions.RegexOptions]::Singleline)
        Write-Host "Replaced stay_add and stay_edit blocks (combo)."
        $foundAdd = $true
        $foundEdit = $true
    }
}

if (-not ($foundAdd -and $foundEdit)) {
    if ($text -match $pattern_add) {
        $text = [regex]::Replace($text, $pattern_add, [System.Text.RegularExpressions.Regex]::Escape($replacement_add_edit), [System.Text.RegularExpressions.RegexOptions]::Singleline)
        Write-Host "Replaced stay_add block (standalone)."
        $foundAdd = $true
    }
    if ($text -match $pattern_edit) {
        $text = [regex]::Replace($text, $pattern_edit, [System.Text.RegularExpressions.Regex]::Escape($replacement_add_edit), [System.Text.RegularExpressions.RegexOptions]::Singleline)
        Write-Host "Replaced stay_edit block (standalone)."
        $foundEdit = $true
    }
}

if (-not ($foundAdd -or $foundEdit)) {
    Write-Warning "Could not find stay_add or stay_edit blocks to replace. No changes made for add/edit."
}

# Write out the new file
Set-Content -Path $file -Value $text -Encoding UTF8
Write-Host "Wrote updated file: $file"

# Simple syntax check by attempting to compile the file with python -m py_compile (if python available)
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    Write-Host "Attempting python -m py_compile to check syntax..."
    $proc = Start-Process -FilePath $py.Path -ArgumentList "-m","py_compile",$file -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -eq 0) {
        Write-Host "Python compiled the file successfully (no SyntaxError detected)."
    } else {
        Write-Warning "python -m py_compile returned exit code $($proc.ExitCode). There may still be syntax errors. Open $file and inspect."
    }
} else {
    Write-Warning "python not found on PATH, skipping python compile check. Run 'python -m py_compile stays/views.py' yourself to verify."
}

Write-Host "Done. If anything still fails, paste the new traceback here (no need to resend the whole file)."

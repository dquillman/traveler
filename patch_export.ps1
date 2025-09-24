# patch_export.ps1
# Patches stays/views.py, stays/urls.py, and templates/stays/export.html
# Run from project root (same dir as manage.py)

$ErrorActionPreference = "Stop"

function Backup-File($path) {
  if (Test-Path $path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $path "$path.bak.$stamp"
  }
}

# --- Resolve paths ---
$proj = (Get-Location).Path
$staysDir = Join-Path $proj "stays"
$templatesDir = Join-Path $proj "templates"
$staysTemplatesDir = Join-Path $templatesDir "stays"

$viewsPy = Join-Path $staysDir "views.py"
$urlsPy  = Join-Path $staysDir "urls.py"
$exportHtml = Join-Path $staysTemplatesDir "export.html"

# --- Sanity checks ---
if (!(Test-Path $viewsPy)) { throw "Missing: $viewsPy" }
if (!(Test-Path $urlsPy))  { throw "Missing: $urlsPy" }
if (!(Test-Path $staysTemplatesDir)) { New-Item -ItemType Directory -Force -Path $staysTemplatesDir | Out-Null }

# =========================
# 1) Patch stays/views.py
# =========================
Backup-File $viewsPy
$views = Get-Content $viewsPy -Raw

# Ensure imports
$needImports = @()
if ($views -notmatch "import csv")                { $needImports += "import csv" }
if ($views -notmatch "from django.http import HttpResponse") { $needImports += "from django.http import HttpResponse" }
if ($views -notmatch "from django.shortcuts import render")  { $needImports += "from django.shortcuts import render" }
if ($views -notmatch "from django.utils import timezone")    { $needImports += "from django.utils import timezone" }
if ($views -notmatch "from \.models import Stay")            { $needImports += "from .models import Stay" }

if ($needImports.Count -gt 0) {
  $importsText = "`n" + ($needImports -join "`n") + "`n"
  # Insert imports after the first line of file
  $views = $importsText + $views
}

# Add export views if missing
$exportViews = @'
def export_home(request):
    """Renders the Export page with simple stats/links."""
    total = Stay.objects.count()
    current_year = timezone.now().year
    this_year = Stay.objects.filter(check_in__year=current_year).count()
    return render(request, "stays/export.html", {
        "total": total,
        "current_year": current_year,
        "this_year": this_year,
    })

def export_stays_csv(request):
    """
    Downloads stays as CSV.
    Optional filter: ?year=YYYY
    """
    qs = Stay.objects.all().order_by("check_in", "city")
    year = request.GET.get("year")
    if year and year.isdigit():
        qs = qs.filter(check_in__year=int(year))

    response = HttpResponse(content_type="text/csv; charset=utf-8")
    fname = "stays_export.csv" if not year else f"stays_{year}.csv"
    response["Content-Disposition"] = f'attachment; filename="{fname}"'
    writer = csv.writer(response)
    writer.writerow(["Park","City","State","Check In","Leave","Nights","Rate/Nt","Price/Night","Paid?"])
    for s in qs:
        writer.writerow([
            s.park or "",
            s.city or "",
            s.state or "",
            getattr(s, "check_in", "") or "",
            getattr(s, "leave", "") or "",
            getattr(s, "nights", 0) or 0,
            getattr(s, "rate_per_night", 0) or 0,
            getattr(s, "price_per_night", 0) or 0,
            "Yes" if getattr(s, "paid", False) else "No",
        ])
    return response
'@

if ($views -notmatch "def\s+export_home\(") {
  $views = $views.TrimEnd() + "`n`n" + $exportViews + "`n"
}

Set-Content -Path $viewsPy -Value $views -Encoding UTF8

# ========================
# 2) Patch stays/urls.py
# ========================
Backup-File $urlsPy
$urls = Get-Content $urlsPy -Raw

# Ensure "from . import views"
if ($urls -notmatch "from\s+\.\s+import\s+views") {
  if ($urls -match "from\s+django\.urls\s+import\s+[^\n]+") {
    $urls = $urls -replace "(from\s+django\.urls\s+import[^\n]+)", '$1' + "`r`nfrom . import views"
  } else {
    $urls = "from django.urls import path`r`nfrom . import views`r`n" + $urls
  }
}

# Insert routes inside urlpatterns list
if ($urls -notmatch "name=['""]stays_export['""]") {
  $newLines = @"
    path('export/', views.export_home, name='stays_export'),
    path('export/csv/', views.export_stays_csv, name='stays_export_csv'),
"@

  # Find the last occurrence of ']' that closes urlpatterns
  $pattern = "(?s)(urlpatterns\s*=\s*\[)(.*?)(\])"
  if ($urls -match $pattern) {
    $prefix = $Matches[1]
    $middle = $Matches[2]
    $suffix = $Matches[3]
    # If lines not already present, add before closing bracket
    if ($middle -notmatch "stays_export") {
      $middle = $middle.TrimEnd() + "`r`n" + $newLines
      $urls = $prefix + $middle + $suffix
    }
  } else {
    throw "Couldn't find urlpatterns list in $urlsPy"
  }
}

Set-Content -Path $urlsPy -Value $urls -Encoding UTF8

# ===================================
# 3) Write templates/stays/export.html
# ===================================
Backup-File $exportHtml
@'
{% load static %}
<!doctype html><meta charset="utf-8">
<title>Traveler • Export</title>
<style>
:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Arial}
.wrap{max-width:1200px;margin:0 auto;padding:16px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px}
.muted{color:var(--muted)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px;margin-top:12px}
.card{background:#12162a;border:1px solid var(--line);border-radius:12px;padding:14px}
a.button{display:inline-block;padding:10px 14px;border:1px solid var(--accent);border-radius:10px;text-decoration:none;color:var(--ink)}
a.button:hover{background:rgba(185,198,255,.08)}
.small{font-size:.9rem}
.kv{display:flex;gap:10px;flex-wrap:wrap;margin:8px 0}
.kv span{background:#0e1330;border:1px solid var(--line);border-radius:8px;padding:6px 8px}
</style>

<div class="wrap">
  <div class="panel">
    <h1>Export</h1>
    <p class="muted small">Download your data as CSV. Use the year filter if you want a slice.</p>

    <div class="kv">
      <span>Total stays: <strong>{{ total }}</strong></span>
      <span>This year ({{ current_year }}): <strong>{{ this_year }}</strong></span>
    </div>

    <div class="grid">
      <div class="card">
        <h3>All Stays (CSV)</h3>
        <p class="muted small">Everything in one file.</p>
        <a class="button" href="{% url 'stays_export_csv' %}">Download CSV</a>
      </div>

      <div class="card">
        <h3>Current Year (CSV)</h3>
        <p class="muted small">Only {{ current_year }} records.</p>
        <a class="button" href="{% url 'stays_export_csv' %}?year={{ current_year }}">Download {{ current_year }}</a>
      </div>

      <div class="card">
        <h3>Pick a Year</h3>
        <form method="get" action="{% url 'stays_export_csv' %}">
          <label for="year" class="small muted">Year</label><br>
          <input id="year" name="year" type="number" min="1990" max="2099" step="1" style="margin:8px 0;padding:8px;border-radius:8px;border:1px solid var(--line);background:#0e1330;color:var(--ink)">
          <br>
          <button class="button" type="submit">Download CSV</button>
        </form>
      </div>
    </div>
  </div>
</div>
'@ | Set-Content -Path $exportHtml -Encoding UTF8

Write-Host "`n✅ Export page and CSV endpoints patched."
Write-Host "Open: http://127.0.0.1:8000/stays/export/"

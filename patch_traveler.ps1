# patch_traveler.ps1
# Bundles: Export page + CSV download, Charts page + JSON endpoint, CSV Import page
# Backups are created alongside each changed file.

$ErrorActionPreference = "Stop"

function Backup-File($path) {
  if (Test-Path $path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $path "$path.bak.$stamp" -Force
  }
}

# --- Paths ---
$ROOT = (Get-Location).Path
$staysDir = Join-Path $ROOT "stays"
$templatesDir = Join-Path $ROOT "templates"
$staysTemplatesDir = Join-Path $templatesDir "stays"

$viewsPy = Join-Path $staysDir "views.py"
$urlsPy  = Join-Path $staysDir "urls.py"
$formsPy = Join-Path $staysDir "forms.py"

$exportHtml = Join-Path $staysTemplatesDir "export.html"
$chartsHtml = Join-Path $staysTemplatesDir "charts.html"
$importHtml = Join-Path $staysTemplatesDir "import.html"

# --- Sanity checks ---
if (!(Test-Path $viewsPy)) { throw "Missing: $viewsPy" }
if (!(Test-Path $urlsPy))  { throw "Missing: $urlsPy" }
if (!(Test-Path $staysTemplatesDir)) { New-Item -ItemType Directory -Force -Path $staysTemplatesDir | Out-Null }

# =========================
# 1) Patch stays/forms.py (import form)
# =========================
if (!(Test-Path $formsPy)) {
  Backup-File $formsPy
  @'
from django import forms

class StayImportForm(forms.Form):
    file = forms.FileField()
'@ | Set-Content -Path $formsPy -Encoding UTF8
} else {
  $forms = Get-Content $formsPy -Raw
  if ($forms -notmatch "class\s+StayImportForm") {
    Backup-File $formsPy
    $forms = $forms.TrimEnd() + @"

class StayImportForm(forms.Form):
    file = forms.FileField()
"@
    Set-Content -Path $formsPy -Value $forms -Encoding UTF8
  }
}

# =========================
# 2) Patch stays/views.py
# =========================
Backup-File $viewsPy
$views = Get-Content $viewsPy -Raw

# Ensure base imports
$need = @()
if ($views -notmatch "(?m)^\s*import\s+csv") { $need += "import csv" }
if ($views -notmatch "from django.http import HttpResponse") { $need += "from django.http import HttpResponse" }
if ($views -notmatch "from django.http import JsonResponse") { $need += "from django.http import JsonResponse" }
if ($views -notmatch "from django.shortcuts import render") { $need += "from django.shortcuts import render" }
if ($views -notmatch "from django.shortcuts import redirect") { $need += "from django.shortcuts import redirect" }
if ($views -notmatch "from django.contrib import messages") { $need += "from django.contrib import messages" }
if ($views -notmatch "from django.utils import timezone") { $need += "from django.utils import timezone" }
if ($views -notmatch "from django.db.models import Sum, Count") { $need += "from django.db.models import Sum, Count" }
if ($views -notmatch "from \.models import Stay") { $need += "from .models import Stay" }
if ($views -notmatch "from \.forms import StayImportForm") { $need += "from .forms import StayImportForm" }

if ($need.Count -gt 0) {
  $views = ($need -join "`r`n") + "`r`n" + $views
}

# Export views
$exportBlock = @'
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
  $views = $views.TrimEnd() + "`r`n`r`n" + $exportBlock + "`r`n"
}

# Charts views
$chartsBlock = @'
def charts_page(request):
    return render(request, "stays/charts.html")

def stays_chart_data(request):
    # Example: total nights per state
    qs = (Stay.objects
                .values('state')
                .annotate(nights=Sum('nights'), count=Count('id'))
                .order_by('state'))
    labels = [r['state'] or '—' for r in qs]
    data = [int(r['nights'] or 0) for r in qs]
    return JsonResponse({'labels': labels, 'datasets': [{'label': 'Nights', 'data': data}]})
'@

if ($views -notmatch "def\s+charts_page\(") {
  $views = $views.TrimEnd() + "`r`n`r`n" + $chartsBlock + "`r`n"
}

# Import view
$importBlock = @'
import io, csv as _csv

def import_stays(request):
    if request.method == 'POST':
        form = StayImportForm(request.POST, request.FILES)
        if form.is_valid():
            f = request.FILES['file']
            raw = f.read()

            # Try encodings (handles Windows-1252 mojibake)
            text = None
            for enc in ('utf-8-sig', 'cp1252'):
                try:
                    text = raw.decode(enc)
                    break
                except UnicodeDecodeError:
                    pass
            if text is None:
                text = raw.decode('utf-8', errors='ignore')

            reader = _csv.DictReader(io.StringIO(text))
            created = updated = skipped = 0

            for row in reader or []:
                if not row:
                    skipped += 1
                    continue
                row = { (k or '').strip().lower().replace('\ufeff',''): (v or '').strip() for k,v in row.items() }

                park  = row.get('park','')
                city  = row.get('city','')
                state = row.get('state','')
                check_in = row.get('check in') or row.get('check_in') or row.get('checkin') or ''
                leave    = row.get('leave','')
                try:
                    nights = int(row.get('nights') or 0)
                except:
                    nights = 0
                try:
                    rate = float(row.get('rate/nt') or row.get('rate_per_night') or 0)
                except:
                    rate = 0.0
                try:
                    price = float(row.get('price/night') or row.get('price_per_night') or rate or 0)
                except:
                    price = 0.0
                paid = (row.get('paid?') or row.get('paid') or '').lower() in ('yes','true','1','y')

                obj, is_created = Stay.objects.update_or_create(
                    park=park, city=city, state=state, check_in=check_in, leave=leave,
                    defaults={'nights': nights, 'rate_per_night': rate, 'price_per_night': price, 'paid': paid}
                )
                created += int(is_created)
                updated += int(not is_created)

            messages.success(request, f'Import complete. Created {created}, updated {updated}, skipped {skipped}.')
            return redirect('stay_list') if 'stay_list' in globals() or 'stay_list' in locals() else redirect('stays_import')
    else:
        form = StayImportForm()
    return render(request, 'stays/import.html', {'form': form})
'@

if ($views -notmatch "def\s+import_stays\(") {
  $views = $views.TrimEnd() + "`r`n`r`n" + $importBlock + "`r`n"
}

Set-Content -Path $viewsPy -Value $views -Encoding UTF8

# =========================
# 3) Patch stays/urls.py
# =========================
Backup-File $urlsPy
$urls = Get-Content $urlsPy -Raw

# Ensure import
if ($urls -notmatch "from\s+\.\s+import\s+views") {
  if ($urls -match "from\s+django\.urls\s+import\s+[^\n]+") {
    $urls = $urls -replace "(from\s+django\.urls\s+import[^\n]+)", '$1' + "`r`nfrom . import views"
  } else {
    $urls = "from django.urls import path`r`nfrom . import views`r`n" + $urls
  }
}

# Ensure urlpatterns entries
$newRoutes = @"
    path('export/', views.export_home, name='stays_export'),
    path('export/csv/', views.export_stays_csv, name='stays_export_csv'),
    path('charts/', views.charts_page, name='stays_charts'),
    path('charts/data/', views.stays_chart_data, name='stays_chart_data'),
    path('import/', views.import_stays, name='stays_import'),
"@

$pattern = "(?s)(urlpatterns\s*=\s*\[)(.*?)(\])"
if ($urls -match $pattern) {
  $pre = $Matches[1]; $mid = $Matches[2]; $post = $Matches[3]
  $needInsert = $false
  foreach ($name in @("stays_export","stays_export_csv","stays_charts","stays_chart_data","stays_import")) {
    if ($mid -notmatch [Regex]::Escape($name)) { $needInsert = $true }
  }
  if ($needInsert) {
    $mid = $mid.TrimEnd() + "`r`n" + $newRoutes
    $urls = $pre + $mid + $post
  }
} else {
  throw "Couldn't find urlpatterns list in $urlsPy"
}

Set-Content -Path $urlsPy -Value $urls -Encoding UTF8

# =========================
# 4) Write templates
# =========================

# Export page
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

# Charts page (uses CDN for Chart.js to avoid local file hassles)
Backup-File $chartsHtml
@'
{% load static %}
<!doctype html><meta charset="utf-8">
<title>Traveler • Charts</title>
<style>
:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Arial}
.wrap{max-width:1200px;margin:0 auto;padding:16px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px;min-height:520px}
</style>
<div class="wrap">
  <div class="panel">
    <h1>Charts</h1>
    <canvas id="nightsByState" style="width:100%; height:420px;"></canvas>
  </div>
</div>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
(async function(){
  const res = await fetch("{% url 'stays_chart_data' %}", {headers: {'X-Requested-With':'fetch'}});
  const payload = await res.json();
  const ctx = document.getElementById('nightsByState').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: { labels: payload.labels, datasets: payload.datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { display: true } },
      scales: { y: { beginAtZero: true } }
    }
  });
})();
</script>
'@ | Set-Content -Path $chartsHtml -Encoding UTF8

# Import page
Backup-File $importHtml
@'
{% load static %}
<!doctype html><meta charset="utf-8">
<title>Traveler • Import</title>
<style>
:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Arial}
.wrap{max-width:900px;margin:0 auto;padding:16px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px}
label{display:block;margin:10px 0 6px}
input[type="file"]{padding:10px;border-radius:10px;border:1px solid var(--line);background:#0e1330;color:var(--ink);width:100%}
button{margin-top:12px;padding:10px 14px;border:1px solid var(--accent);border-radius:10px;background:transparent;color:var(--ink)}
button:hover{background:rgba(185,198,255,.08)}
.small{color:var(--muted)}
</style>
<div class="wrap">
  <div class="panel">
    <h1>Import Stays (CSV)</h1>
    <form method="post" enctype="multipart/form-data">
      {% csrf_token %}
      <label>CSV file</label>
      {{ form.file }}
      <button type="submit">Import</button>
    </form>
    <p class="small" style="margin-top:14px">
      Headers accepted (case-insensitive): <code>Park, City, State, Check In, Leave, Nights, Rate/Nt, Price/Night, Paid?</code>
    </p>
  </div>
</div>
'@ | Set-Content -Path $importHtml -Encoding UTF8

Write-Host "`n✅ Done. Pages added:"
Write-Host "   • /stays/export/ (CSV downloads with optional ?year=YYYY)"
Write-Host "   • /stays/charts/ (Chart.js via CDN)"
Write-Host "   • /stays/import/ (CSV importer with Windows-1252 fallback)"
Write-Host "`nRestart your dev server and visit those URLs."

# fix_traveler_all_v2.ps1
# Repairs Export, Charts, Map, Import (with file chooser) safely.
# Backs up changed files: *.bak.YYYYMMDD_HHMMSS

$ErrorActionPreference = "Stop"

function Backup($p) {
  if (Test-Path $p) { Copy-Item $p "$p.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force }
}

$ROOT = (Get-Location).Path
$staysDir = Join-Path $ROOT "stays"
$viewsPy  = Join-Path $staysDir "views.py"
$urlsPy   = Join-Path $staysDir "urls.py"
$formsPy  = Join-Path $staysDir "forms.py"

$tplDir   = Join-Path $ROOT "templates"
$stTplDir = Join-Path $tplDir "stays"
$exportHtml = Join-Path $stTplDir "export.html"
$chartsHtml = Join-Path $stTplDir "charts.html"
$mapHtml    = Join-Path $stTplDir "map.html"
$importHtml = Join-Path $stTplDir "import.html"

if (!(Test-Path $stTplDir)) { New-Item -ItemType Directory -Force -Path $stTplDir | Out-Null }
if (!(Test-Path $viewsPy))  { throw "Missing: $viewsPy" }
if (!(Test-Path $urlsPy))   { throw "Missing: $urlsPy" }

# ---------------------------
# Ensure forms.py with file field
# ---------------------------
if (!(Test-Path $formsPy)) {
  @'
from django import forms

class StayImportForm(forms.Form):
    file = forms.FileField()
'@ | Set-Content -Path $formsPy -Encoding UTF8
} else {
  $f = Get-Content $formsPy -Raw
  if ($f -notmatch "class\s+StayImportForm") {
    Backup $formsPy
@'

class StayImportForm(forms.Form):
    file = forms.FileField()
'@ | Add-Content -Path $formsPy -Encoding UTF8
  }
}

# ---------------------------
# Patch stays/views.py
# ---------------------------
Backup $viewsPy
$views = Get-Content $viewsPy -Raw

# Ensure imports
$need = @()
if ($views -notmatch "(?m)^\s*import\s+csv")                    { $need += "import csv" }
if ($views -notmatch "(?m)^\s*import\s+io")                     { $need += "import io" }
if ($views -notmatch "from django.http import HttpResponse")    { $need += "from django.http import HttpResponse" }
if ($views -notmatch "from django.http import JsonResponse")    { $need += "from django.http import JsonResponse" }
if ($views -notmatch "from django.shortcuts import render")     { $need += "from django.shortcuts import render" }
if ($views -notmatch "from django.shortcuts import redirect")   { $need += "from django.shortcuts import redirect" }
if ($views -notmatch "from django.contrib import messages")     { $need += "from django.contrib import messages" }
if ($views -notmatch "from django.utils import timezone")       { $need += "from django.utils import timezone" }
if ($views -notmatch "from django.db.models import Sum, Count") { $need += "from django.db.models import Sum, Count" }
if ($views -notmatch "from \.models import Stay")               { $need += "from .models import Stay" }
if ($views -notmatch "from \.forms import StayImportForm")      { $need += "from .forms import StayImportForm" }

if ($need.Count -gt 0) {
  $prepend = ($need -join "`r`n") + "`r`n"
  $views   = $prepend + $views
  $views | Set-Content -Path $viewsPy -Encoding UTF8
}

# Export views
if ((Get-Content $viewsPy -Raw) -notmatch "def\s+export_home\(") {
@'
def export_home(request):
    total = Stay.objects.count()
    current_year = timezone.now().year
    this_year = Stay.objects.filter(check_in__year=current_year).count()
    return render(request, 'stays/export.html', {
        'total': total,
        'current_year': current_year,
        'this_year': this_year,
    })

def export_stays_csv(request):
    qs = Stay.objects.all().order_by('check_in', 'city')
    year = request.GET.get('year')
    if year and str(year).isdigit():
        qs = qs.filter(check_in__year=int(year))
    response = HttpResponse(content_type='text/csv; charset=utf-8')
    fname = 'stays_export.csv' if not year else f'stays_{year}.csv'
    response['Content-Disposition'] = f'attachment; filename="{fname}"'
    writer = csv.writer(response)
    writer.writerow(['Park','City','State','Check In','Leave','Nights','Rate/Nt','Price/Night','Paid?'])
    for s in qs:
        writer.writerow([
            getattr(s,'park','') or '',
            getattr(s,'city','') or '',
            getattr(s,'state','') or '',
            getattr(s,'check_in','') or '',
            getattr(s,'leave','') or '',
            getattr(s,'nights',0) or 0,
            getattr(s,'rate_per_night',0) or 0,
            getattr(s,'price_per_night',0) or 0,
            'Yes' if getattr(s,'paid',False) else 'No'
        ])
    return response
'@ | Add-Content -Path $viewsPy -Encoding UTF8
}

# Charts views
if ((Get-Content $viewsPy -Raw) -notmatch "def\s+charts_page\(") {
@'
def charts_page(request):
    return render(request, 'stays/charts.html')

def stays_chart_data(request):
    qs = (Stay.objects.values('state')
          .annotate(nights=Sum('nights'), count=Count('id'))
          .order_by('state'))
    labels = [r['state'] or '—' for r in qs]
    data = [int(r['nights'] or 0) for r in qs]
    return JsonResponse({'labels': labels, 'datasets': [{'label': 'Nights', 'data': data}]})
'@ | Add-Content -Path $viewsPy -Encoding UTF8
}

# Map views
if ((Get-Content $viewsPy -Raw) -notmatch "def\s+map_page\(") {
@'
def map_page(request):
    return render(request, 'stays/map.html')

def stays_map_data(request):
    features = []
    for s in Stay.objects.all():
        lat = getattr(s, 'latitude', None)
        lng = getattr(s, 'longitude', None)
        if lat is None or lng is None:
            continue
        props = {
            'park': getattr(s,'park',''),
            'city': getattr(s,'city',''),
            'state': getattr(s,'state',''),
            'nights': getattr(s,'nights',0) or 0,
            'price_per_night': getattr(s,'price_per_night',0) or 0,
            'id': s.id,
        }
        features.append({
            'type': 'Feature',
            'properties': props,
            'geometry': {'type': 'Point', 'coordinates': [float(lng), float(lat)]}
        })
    return JsonResponse({'type': 'FeatureCollection', 'features': features})
'@ | Add-Content -Path $viewsPy -Encoding UTF8
}

# Import view
if ((Get-Content $viewsPy -Raw) -notmatch "def\s+import_stays\(") {
@'
def import_stays(request):
    if request.method == 'POST':
        form = StayImportForm(request.POST, request.FILES)
        if form.is_valid() and 'file' in request.FILES:
            raw = request.FILES['file'].read()
            text = None
            for enc in ('utf-8-sig','cp1252'):
                try:
                    text = raw.decode(enc)
                    break
                except UnicodeDecodeError:
                    pass
            if text is None:
                text = raw.decode('utf-8', errors='ignore')

            import csv as _csv, io as _io
            reader = _csv.DictReader(_io.StringIO(text))
            created = updated = skipped = 0
            for row in reader or []:
                if not row:
                    skipped += 1
                    continue
                row = {(k or '').strip().lower().replace('\ufeff',''): (v or '').strip() for k,v in row.items()}
                park  = row.get('park','')
                city  = row.get('city','')
                state = row.get('state','')
                check_in = row.get('check in') or row.get('check_in') or row.get('checkin') or ''
                leave    = row.get('leave','')
                try: nights = int(row.get('nights') or 0)
                except: nights = 0
                try: rate = float(row.get('rate/nt') or row.get('rate_per_night') or 0)
                except: rate = 0.0
                try: price = float(row.get('price/night') or row.get('price_per_night') or rate or 0)
                except: price = 0.0
                paid = (row.get('paid?') or row.get('paid') or '').lower() in ('yes','true','1','y')

                obj, is_created = Stay.objects.update_or_create(
                    park=park, city=city, state=state, check_in=check_in, leave=leave,
                    defaults={'nights': nights, 'rate_per_night': rate, 'price_per_night': price, 'paid': paid}
                )
                created += int(is_created); updated += int(not is_created)
            messages.success(request, f'Import complete. Created {created}, updated {updated}, skipped {skipped}.')
            return redirect('stays:stays_import')
    else:
        form = StayImportForm()
    return render(request, 'stays/import.html', {'form': form})
'@ | Add-Content -Path $viewsPy -Encoding UTF8
}

# ---------------------------
# Patch stays/urls.py
# ---------------------------
Backup $urlsPy
$urls = Get-Content $urlsPy -Raw

if ($urls -notmatch "(?m)^\s*from\s+django\.urls\s+import\s+path") {
  $urls = "from django.urls import path`r`n" + $urls
}
if ($urls -notmatch "(?m)^\s*from\s+\.\s+import\s+views") {
  $urls = $urls -replace "(?m)(from\s+django\.urls\s+import[^\n]+)", '$1' + "`r`nfrom . import views"
}
if ($urls -notmatch "(?m)^\s*app_name\s*=\s*['""]stays['""]") {
  $urls = $urls -replace "(?m)(from\s+\.\s+import\s+views\s*)", "$1`r`napp_name = 'stays'"
}

if ($urls -notmatch "urlpatterns\s*=\s*\[") {
  $urls += "`r`nurlpatterns = []`r`n"
}

$block = @'
    path('export/', views.export_home, name='stays_export'),
    path('export/csv/', views.export_stays_csv, name='stays_export_csv'),
    path('charts/', views.charts_page, name='stays_charts'),
    path('charts/data/', views.stays_chart_data, name='stays_chart_data'),
    path('map/', views.map_page, name='stays_map'),
    path('map/data/', views.stays_map_data, name='stays_map_data'),
    path('import/', views.import_stays, name='stays_import'),
'@

$urls = [regex]::Replace($urls, "(?s)(urlpatterns\s*=\s*\[)(.*?)(\])", {
  $pre = $args[0].Groups[1].Value
  $mid = $args[0].Groups[2].Value
  $post= $args[0].Groups[3].Value
  foreach ($n in @('stays_export','stays_export_csv','stays_charts','stays_chart_data','stays_map','stays_map_data','stays_import')) {
    if ($mid -notmatch [regex]::Escape($n)) { $mid = $mid.TrimEnd() + "`r`n" + $block; break }
  }
  return $pre + $mid + $post
})

$urls | Set-Content -Path $urlsPy -Encoding UTF8

# ---------------------------
# Templates
# ---------------------------

# Export
Backup $exportHtml
@'
{% load static %}
<!doctype html><meta charset="utf-8"><title>Traveler • Export</title>
<style>:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Arial}
.wrap{max-width:1200px;margin:0 auto;padding:16px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px}
.muted{color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px;margin-top:12px}
.card{background:#12162a;border:1px solid var(--line);border-radius:12px;padding:14px}
a.button{display:inline-block;padding:10px 14px;border:1px solid var(--accent);border-radius:10px;text-decoration:none;color:var(--ink)}
a.button:hover{background:rgba(185,198,255,.08)}.small{font-size:.9rem}
.kv{display:flex;gap:10px;flex-wrap:wrap;margin:8px 0}.kv span{background:#0e1330;border:1px solid var(--line);border-radius:8px;padding:6px 8px}</style>
<div class="wrap"><div class="panel">
  <h1>Export</h1>
  <p class="muted small">Download your data as CSV. Use the year filter if you want a slice.</p>
  <div class="kv"><span>Total stays: <strong>{{ total }}</strong></span><span>This year ({{ current_year }}): <strong>{{ this_year }}</strong></span></div>
  <div class="grid">
    <div class="card"><h3>All Stays (CSV)</h3><p class="muted small">Everything in one file.</p><a class="button" href="{% url 'stays:stays_export_csv' %}">Download CSV</a></div>
    <div class="card"><h3>Current Year (CSV)</h3><p class="muted small">Only {{ current_year }} records.</p><a class="button" href="{% url 'stays:stays_export_csv' %}?year={{ current_year }}">Download {{ current_year }}</a></div>
    <div class="card"><h3>Pick a Year</h3>
      <form method="get" action="{% url 'stays:stays_export_csv' %}">
        <label for="year" class="small muted">Year</label><br>
        <input id="year" name="year" type="number" min="1990" max="2099" step="1" style="margin:8px 0;padding:8px;border-radius:8px;border:1px solid var(--line);background:#0e1330;color:var(--ink)">
        <br><button class="button" type="submit">Download CSV</button>
      </form>
    </div>
  </div>
</div></div>
'@ | Set-Content -Path $exportHtml -Encoding UTF8

# Charts
Backup $chartsHtml
@'
<!doctype html><meta charset="utf-8"><title>Traveler • Charts</title>
<style>:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Arial}
.wrap{max-width:1200px;margin:0 auto;padding:16px}.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px;min-height:520px}</style>
<div class="wrap"><div class="panel">
  <h1>Charts</h1>
  <canvas id="nightsByState" style="width:100%;height:420px;"></canvas>
</div></div>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
(async function(){
  const res = await fetch("{% url 'stays:stays_chart_data' %}");
  const data = await res.json();
  const ctx = document.getElementById('nightsByState').getContext('2d');
  new Chart(ctx,{type:'bar',data:{labels:data.labels,datasets:data.datasets},
    options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:true}},scales:{y:{beginAtZero:true}}}});
})();
</script>
'@ | Set-Content -Path $chartsHtml -Encoding UTF8

# Map (Leaflet)
Backup $mapHtml
@'
<!doctype html><meta charset="utf-8"><title>Traveler • Map</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<style>:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto}
#map{height:calc(100vh - 24px);margin:12px;border:1px solid var(--line);border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.25)}</style>
<div id="map"></div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
(async function(){
  const res = await fetch("{% url 'stays:stays_map_data' %}");
  const gj = await res.json();
  const map = L.map('map').setView([39.5,-98.35], 4);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:18, attribution:'© OpenStreetMap'}).addTo(map);
  const markers = L.geoJSON(gj, {
    onEachFeature: (f, layer) => {
      const p = f.properties||{};
      const html = `<strong>${p.park||'Unnamed'}</strong><br>${p.city||''}, ${p.state||''}<br>Nights: ${p.nights||0}<br>Price/Night: $${p.price_per_night||0}<br><a href="/stays/${p.id}/edit/">Open / Edit</a>`;
      layer.bindPopup(html);
    }
  }).addTo(map);
  if (markers.getLayers().length) map.fitBounds(markers.getBounds(),{padding:[20,20]});
})();
</script>
'@ | Set-Content -Path $mapHtml -Encoding UTF8

# Import (file chooser + enctype)
Backup $importHtml
@'
<!doctype html><meta charset="utf-8"><title>Traveler • Import</title>
<style>:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41;--accent:#b9c6ff}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto}
.wrap{max-width:900px;margin:0 auto;padding:16px}.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px}
label{display:block;margin:10px 0 6px}input[type="file"]{padding:10px;border-radius:10px;border:1px solid var(--line);background:#0e1330;color:var(--ink);width:100%}
button{margin-top:12px;padding:10px 14px;border:1px solid var(--accent);border-radius:10px;background:transparent;color:var(--ink)}
button:hover{background:rgba(185,198,255,.08)}.small{color:var(--muted)}</style>
<div class="wrap"><div class="panel">
  <h1>Import Stays (CSV)</h1>
  <form method="post" enctype="multipart/form-data">
    {% csrf_token %}
    <label for="file">CSV file</label>
    <input id="file" type="file" name="file" accept=".csv">
    <button type="submit">Import</button>
  </form>
  <p class="small" style="margin-top:14px">Headers accepted (case-insensitive): <code>Park, City, State, Check In, Leave, Nights, Rate/Nt, Price/Night, Paid?</code></p>
</div></div>
'@ | Set-Content -Path $importHtml -Encoding UTF8

Write-Host "`n✅ All endpoints & pages written (Export, Charts, Map, Import)."
Write-Host "Restart your server: python manage.py runserver"

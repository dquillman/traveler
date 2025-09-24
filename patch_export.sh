#!/usr/bin/env bash
set -euo pipefail

proj="$(pwd)"
views_py="$proj/stays/views.py"
urls_py="$proj/stays/urls.py"
stays_tpl="$proj/templates/stays"
export_html="$stays_tpl/export.html"

backup() {
  [ -f "$1" ] && cp "$1" "$1.bak.$(date +%Y%m%d_%H%M%S)"
}

[ -f "$views_py" ] || { echo "Missing $views_py"; exit 1; }
[ -f "$urls_py" ]  || { echo "Missing $urls_py";  exit 1; }
mkdir -p "$stays_tpl"

# 1) Patch views.py
backup "$views_py"
python3 - "$views_py" <<'PY'
import sys, io, re, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

imports = []
if "import csv" not in s: imports.append("import csv")
if "from django.http import HttpResponse" not in s: imports.append("from django.http import HttpResponse")
if "from django.shortcuts import render" not in s: imports.append("from django.shortcuts import render")
if "from django.utils import timezone" not in s: imports.append("from django.utils import timezone")
if "from .models import Stay" not in s: imports.append("from .models import Stay")

if imports:
    s = "\n".join(imports) + "\n" + s

if "def export_home(" not in s:
    s = s.rstrip() + """

def export_home(request):
    \"\"\"Renders the Export page with simple stats/links.\"\"\"
    total = Stay.objects.count()
    current_year = timezone.now().year
    this_year = Stay.objects.filter(check_in__year=current_year).count()
    return render(request, "stays/export.html", {
        "total": total,
        "current_year": current_year,
        "this_year": this_year,
    })

def export_stays_csv(request):
    \"\"\"
    Downloads stays as CSV.
    Optional filter: ?year=YYYY
    \"\"\"
    qs = Stay.objects.all().order_by("check_in", "city")
    year = request.GET.get("year")
    if year and year.isdigit():
        qs = qs.filter(check_in__year=int(year))

    response = HttpResponse(content_type="text/csv; charset=utf-8")
    fname = "stays_export.csv" if not year else f"stays_{year}.csv"
    response["Content-Disposition"] = f'attachment; filename="{fname}"'
    writer = csv.writer(response)
    writer.writerow(["Park","City","State","Check In","Leave","Nights","Rate/Nt","Price/Night","Paid?"])
    for s_ in qs:
        writer.writerow([
            s_.park or "",
            s_.city or "",
            s_.state or "",
            getattr(s_, "check_in", "") or "",
            getattr(s_, "leave", "") or "",
            getattr(s_, "nights", 0) or 0,
            getattr(s_, "rate_per_night", 0) or 0,
            getattr(s_, "price_per_night", 0) or 0,
            "Yes" if getattr(s_, "paid", False) else "No",
        ])
    return response
"""
p.write_text(s, encoding="utf-8")
PY

# 2) Patch urls.py
backup "$urls_py"
python3 - "$urls_py" <<'PY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

if "from . import views" not in s:
    s = re.sub(r"(from\s+django\.urls\s+import[^\n]+)",
               r"\1\nfrom . import views", s, count=1) or ("from django.urls import path\nfrom . import views\n" + s)

m = re.search(r"(?s)(urlpatterns\s*=\s*\[)(.*?)(\])", s)
if not m:
    raise SystemExit("Couldn't find urlpatterns list")
pre, mid, post = m.groups()
if "stays_export" not in mid:
    mid = mid.rstrip() + "\n    path('export/', views.export_home, name='stays_export'),\n    path('export/csv/', views.export_stays_csv, name='stays_export_csv'),\n"
s = pre + mid + post
p.write_text(s, encoding="utf-8")
PY

# 3) Write export.html
backup "$export_html"
cat > "$export_html" <<'HTML'
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
HTML

echo "✅ Export page and CSV endpoints patched."
echo "Open: http://127.0.0.1:8000/stays/export/"

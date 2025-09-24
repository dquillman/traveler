# fix_views_syntax.ps1
$ErrorActionPreference = "Stop"
$views = "stays\views.py"
if (!(Test-Path $views)) { throw "Missing $views" }
Copy-Item $views "$views.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force
$t = Get-Content $views -Raw

# 1) Ensure required imports (idempotent)
$imports = @()
if ($t -notmatch "(?m)^\s*from\s+django\.http\s+import\s+JsonResponse") { $imports += "from django.http import JsonResponse" }
if ($t -notmatch "(?m)^\s*from\s+django\.shortcuts\s+import\s+render")   { $imports += "from django.shortcuts import render" }
if ($t -notmatch "(?m)^\s*from\s+django\.utils\s+import\s+timezone")     { $imports += "from django.utils import timezone" }
if ($t -notmatch "(?m)^\s*from\s+django\.db\.models\s+import\s+Sum,\s*Count") { $imports += "from django.db.models import Sum, Count" }
if ($t -notmatch "(?m)^\s*from\s+\.\s+models\s+import\s+Stay")           { $imports += "from .models import Stay" }
if ($imports.Count -gt 0) { $t = ($imports -join "`r`n") + "`r`n" + $t }

# 2) Separate any glued functions like: ")def map_page(" or ")def stays_map_data("
$t = $t -replace "\)\s*def\s+", ")`r`n`r`ndef "

# 3) Replace/ensure a correct stays_map_data() implementation (accepts latitude/longitude or lat/lng/lon)
$staysMapData = @'
def stays_map_data(request):
    """
    Returns GeoJSON FeatureCollection of stays with coordinates.
    Accepts latitude/longitude or lat/lng or lat/lon field names.
    """
    def get_coord(obj):
        lat = getattr(obj, "latitude", None)
        lng = getattr(obj, "longitude", None)
        if lat is None:
            lat = getattr(obj, "lat", None)
        if lng is None:
            lng = getattr(obj, "lng", None)
        if lng is None:
            lng = getattr(obj, "lon", None)
        try:
            lat = float(lat) if lat is not None else None
        except Exception:
            lat = None
        try:
            lng = float(lng) if lng is not None else None
        except Exception:
            lng = None
        return lat, lng

    features = []
    for s in Stay.objects.all():
        lat, lng = get_coord(s)
        if lat is None or lng is None:
            continue
        props = {
            "park": getattr(s, "park", "") or "",
            "city": getattr(s, "city", "") or "",
            "state": getattr(s, "state", "") or "",
            "nights": getattr(s, "nights", 0) or 0,
            "id": s.id,
        }
        features.append({
            "type": "Feature",
            "properties": props,
            "geometry": {"type": "Point", "coordinates": [lng, lat]},
        })
    return JsonResponse({"type": "FeatureCollection", "features": features})
'@

if ($t -match "def\s+stays_map_data\s*\(") {
  # replace existing function body safely
  $t = [regex]::Replace($t,
    "def\s+stays_map_data\s*\([^\0]*?(?=^def\s|\Z)",
    $staysMapData, "Singleline, Multiline")
} else {
  # append it if missing
  $t = $t.TrimEnd() + "`r`n`r`n" + $staysMapData + "`r`n"
}

# 4) Ensure map_page exists and is a simple template render
if ($t -notmatch "def\s+map_page\s*\(") {
  $t += @'

def map_page(request):
    return render(request, "stays/map.html")
'
}

Set-Content -Path $views -Value $t -Encoding UTF8
Write-Host "✅ stays/views.py fixed (syntax + robust stays_map_data)."

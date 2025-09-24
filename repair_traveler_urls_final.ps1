param(
  [string]$ProjectRoot = $PSScriptRoot
)

function WriteUtf8([string]$p,[string]$t){
  [IO.File]::WriteAllText($p, $t, [Text.UTF8Encoding]::new($false))
}

$staysUrls = Join-Path $ProjectRoot "stays\urls.py"
$staysViews = Join-Path $ProjectRoot "stays\views.py"

if(!(Test-Path $staysUrls)){ throw "Not found: $staysUrls" }
if(!(Test-Path $staysViews)){ throw "Not found: $staysViews" }

# ---- stays/urls.py
$urls = Get-Content $staysUrls -Raw
$origUrls = $urls
if($urls -notmatch 'from\s+\.\s+import\s+views'){
  if($urls -match 'from\s+django\.urls\s+import\s+path'){
    $urls = $urls -replace '(from\s+django\.urls\s+import\s+path[^\n]*\n)', '$0' + "from . import views`r`n"
  } else {
    $urls = "from django.urls import path`r`nfrom . import views`r`n" + $urls
  }
}
if($urls -notmatch 'urlpatterns\s*='){
  $urls += "`r`nurlpatterns = []`r`n"
}
$want = @(
  'path("map-data/", views.stays_map_data, name="stays_map_data")',
  'path("charts/", views.stays_charts, name="stays_charts")',
  'path("import/", views.stays_import, name="stays_import")',
  'path("export/", views.stays_export, name="stays_export")'
)
$match = [regex]::Match($urls, 'urlpatterns\s*=\s*\[(.*?)\]', [Text.RegularExpressions.RegexOptions]::Singleline)
if($match.Success){
  $inside = $match.Groups[1].Value
  foreach($w in $want){
    if($inside -notmatch [regex]::Escape($w)){ $inside = $inside.TrimEnd() + "`r`n    $w," }
  }
  $urls = $urls.Substring(0,$match.Index) + "urlpatterns = [" + "`r`n" + $inside.TrimEnd() + "`r`n" + "]" + $urls.Substring($match.Index + $match.Length)
} else {
  foreach($w in $want){
    if($urls -notmatch [regex]::Escape($w)){ $urls += "`r`nurlpatterns += [ $w ]`r`n" }
  }
}
if($urls -ne $origUrls){
  Copy-Item $staysUrls "$staysUrls.bak.$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
  WriteUtf8 $staysUrls $urls
  Write-Host "Updated: $staysUrls"
} else {
  Write-Host "No changes needed: $staysUrls"
}

# ---- stays/views.py (ensure views exist)
$views = Get-Content $staysViews -Raw
$origViews = $views
if($views -notmatch 'from\s+django\.shortcuts\s+import\s+render'){
  $views = "from django.shortcuts import render`r`n" + $views
}
if($views -notmatch 'from\s+django\.http\s+import\s+JsonResponse'){
  $views = "from django.http import JsonResponse`r`n" + $views
}
if($views -notmatch 'from\s+django\.urls\s+import\s+reverse'){
  $views = "from django.urls import reverse`r`n" + $views
}
if($views -notmatch 'def\s+stays_map_data\s*\('){
$func = @'
def stays_map_data(request):
    from .models import Stay
    items = []
    for s in Stay.objects.all():
        items.append({
            "id": s.id,
            "label": s.label or "",
            "latitude": getattr(s, "latitude", None),
            "longitude": getattr(s, "longitude", None),
            "popup_html": f"<strong>{s.label or 'Stay'}</strong><br>{(s.city or '')}, {(s.state or '')}",
            "detail_url": reverse("stay_edit", args=[s.id]),
        })
    return JsonResponse({"stays": items})
'@
  $views = $views.TrimEnd() + "`r`n`r`n" + $func + "`r`n"
}
foreach($stub in @(
@'def stays_charts(request):  return render(request, "stays/charts.html", {})'@,
@'def stays_import(request):  return render(request, "stays/import.html", {})'@,
@'def stays_export(request):  return render(request, "stays/export.html", {})'@
)){
  $name = ($stub -split '\s+')[1]
  if($views -notmatch "def\s+$name\s*\("){
    $views = $views.TrimEnd() + "`r`n`r`n" + $stub + "`r`n"
  }
}
if($views -ne $origViews){
  Copy-Item $staysViews "$staysViews.bak.$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
  WriteUtf8 $staysViews $views
  Write-Host "Updated: $staysViews"
} else {
  Write-Host "No changes needed: $staysViews"
}

Write-Host "Done. Restart your server:  python manage.py runserver"

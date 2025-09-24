# restore_home_and_nav.ps1
$ErrorActionPreference = "Stop"

function Backup($p){ if(Test-Path $p){ Copy-Item $p "$p.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force } }

# 1) config/urls.py — remove root redirects that hijack the homepage
$cfg = "config\urls.py"
if(!(Test-Path $cfg)){ throw "Missing $cfg" }
Backup $cfg
$c = Get-Content $cfg -Raw

# Remove any path("", RedirectView...) and path("map/", RedirectView...) lines
$c = $c -replace "(?m)^\s*path\(\s*""""\s*,\s*RedirectView\.as_view\([^)]*\)\s*\),?\s*$", ""
$c = $c -replace "(?m)^\s*path\(\s*""map/""\s*,\s*RedirectView\.as_view\([^)]*\)\s*\),?\s*$", ""

# Ensure imports are still valid (keep include/admin lines intact)
Set-Content -Path $cfg -Value $c -Encoding UTF8

# 2) stays/urls.py — ensure the list is the index under /stays/
$su = "stays\urls.py"
if(!(Test-Path $su)){ throw "Missing $su" }
Backup $su
$s = Get-Content $su -Raw

# Required imports and namespace
if($s -notmatch "(?m)^\s*from\s+django\.urls\s+import\s+path"){ $s = "from django.urls import path`r`n" + $s }
if($s -notmatch "(?m)^\s*from\s+\.\s+import\s+views"){ $s = $s -replace "(?m)(from\s+django\.urls\s+import[^\n]+)", '$1' + "`r`nfrom . import views" }
if($s -notmatch "(?m)^\s*app_name\s*=\s*['""]stays['""]"){ $s = $s -replace "(?m)(from\s+\.\s+import\s+views\s*)", "$1`r`napp_name = 'stays'`r`n" }

# Ensure urlpatterns exists
if($s -notmatch "urlpatterns\s*=\s*\["){ $s += "`r`nurlpatterns = []`r`n" }

# Make sure index route exists
if($s -notmatch "name=['""]list['""]"){
  $s = [regex]::Replace($s, "(?s)(urlpatterns\s*=\s*\[)(.*?)(\])", {
    $pre=$args[0].Groups[1].Value; $mid=$args[0].Groups[2].Value; $post=$args[0].Groups[3].Value
    $pre + $mid.TrimEnd() + "`r`n    path('', views.stay_list, name='list'),`r`n" + $post
  })
}

Set-Content -Path $su -Value $s -Encoding UTF8

# 3) Add a tiny top nav to the standalone pages so you can navigate
$tpls = @(
  "templates\stays\map.html",
  "templates\stays\export.html",
  "templates\stays\charts.html",
  "templates\stays\import.html"
)
$nav = @'
<div style="position:sticky;top:0;background:#0f1220;border-bottom:1px solid #272b41;padding:10px 12px;z-index:9999">
  <a href="/stays/" style="margin-right:12px;color:#e8ebff;text-decoration:none">Stays</a>
  <a href="/stays/map/" style="margin-right:12px;color:#e8ebff;text-decoration:none">Map</a>
  <a href="/stays/charts/" style="margin-right:12px;color:#e8ebff;text-decoration:none">Charts</a>
  <a href="/stays/export/" style="margin-right:12px;color:#e8ebff;text-decoration:none">Export</a>
  <a href="/stays/import/" style="color:#e8ebff;text-decoration:none">Import</a>
</div>
'@

foreach($f in $tpls){
  if(Test-Path $f){
    Backup $f
    $t = Get-Content $f -Raw
    if($t -notmatch "Stays</a>"){  # simple check to avoid duplicating nav
      # Insert nav right after <body> (or at top if <body> missing)
      if($t -match "(?i)<body[^>]*>"){
        $t = $t -replace "(?i)(<body[^>]*>)", "`$1`r`n$nav"
      } else {
        $t = $nav + "`r`n" + $t
      }
      Set-Content -Path $f -Value $t -Encoding UTF8
    }
  }
}

Write-Host "✅ Root redirect removed, /stays/ set to list, and nav injected on map/export/charts/import pages."

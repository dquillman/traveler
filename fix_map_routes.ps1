# fix_map_routes.ps1
$ErrorActionPreference = "Stop"

# 1) stays/urls.py: ensure app_name and map routes
$su = "stays\urls.py"
if (!(Test-Path $su)) { throw "Missing $su" }
Copy-Item $su "$su.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$s = Get-Content $su -Raw

if ($s -notmatch "(?m)^\s*from\s+django\.urls\s+import\s+path") {
  $s = "from django.urls import path`r`n" + $s
}
if ($s -notmatch "(?m)^\s*from\s+\.\s+import\s+views") {
  $s = $s -replace "(?m)(from\s+django\.urls\s+import[^\n]+)", '$1' + "`r`nfrom . import views"
}
if ($s -notmatch "(?m)^\s*app_name\s*=\s*['""]stays['""]") {
  $s = $s -replace "(?m)(from\s+\.\s+import\s+views\s*)", "$1`r`napp_name = 'stays'`r`n"
}
if ($s -notmatch "name=['""]stays_map['""]") {
  # Insert both map routes into urlpatterns
  $block = @"
    path('map/', views.map_page, name='stays_map'),
    path('map/data/', views.stays_map_data, name='stays_map_data'),
"@
  $s = [regex]::Replace($s, "(?s)(urlpatterns\s*=\s*\[)(.*?)(\])", {
    $pre=$args[0].Groups[1].Value; $mid=$args[0].Groups[2].Value; $post=$args[0].Groups[3].Value
    $pre + $mid.TrimEnd() + "`r`n" + $block + $post
  })
}
Set-Content -Path $su -Value $s -Encoding UTF8

# 2) config/urls.py: add root /map/ alias using a hard URL
$cu = "config\urls.py"
if (!(Test-Path $cu)) { throw "Missing $cu" }
Copy-Item $cu "$cu.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$c = Get-Content $cu -Raw

if ($c -notmatch "(?m)^\s*from\s+django\.views\.generic\.base\s+import\s+RedirectView") {
  if ($c -match "(?m)^\s*from\s+django\.urls\s+import\s+path.*$") {
    $c = $c -replace "(?m)^\s*from\s+django\.urls\s+import\s+path.*$",
      "from django.urls import path, include`r`nfrom django.views.generic.base import RedirectView"
  } else {
    $c = "from django.urls import path, include`r`nfrom django.views.generic.base import RedirectView`r`n" + $c
  }
}

# Add/normalize the /map/ alias
if ($c -notmatch "(?m)path\('map/',") {
  $c = $c -replace "(?s)(urlpatterns\s*=\s*\[)", "`$1`r`n    path('map/', RedirectView.as_view(url='/stays/map/', permanent=False)),"
} else {
  # If there's already a map redirect, make sure it points to the hard URL
  $c = $c -replace "RedirectView\.as_view\([^)]*\)", "RedirectView.as_view(url='/stays/map/', permanent=False)"
}

Set-Content -Path $cu -Value $c -Encoding UTF8
Write-Host "✅ Map routes and root alias set. Restart Django."

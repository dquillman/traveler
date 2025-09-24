# fix_home_root.ps1
$ErrorActionPreference = "Stop"
$cfg = "config\urls.py"
Copy-Item $cfg "$cfg.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force
$c = Get-Content $cfg -Raw
if ($c -notmatch "from\s+django\.views\.generic\.base\s+import\s+RedirectView") {
  if ($c -match "from\s+django\.urls\s+import\s+path.*") {
    $c = $c -replace "from\s+django\.urls\s+import\s+path.*", "from django.urls import path, include`r`nfrom django.views.generic.base import RedirectView"
  } else {
    $c = "from django.urls import path, include`r`nfrom django.views.generic.base import RedirectView`r`n" + $c
  }
}
if ($c -notmatch "path\(''\s*,\s*RedirectView\.as_view") {
  $c = $c -replace "(?s)(urlpatterns\s*=\s*\[)", "`$1`r`n    path('', RedirectView.as_view(url='/stays/', permanent=False)),"
}
Set-Content -Path $cfg -Value $c -Encoding UTF8
Write-Host "✅ Homepage now redirects to /stays/"

# fix_stays_urls_header.ps1
$ErrorActionPreference = "Stop"
$u = "stays\urls.py"
if (!(Test-Path $u)) { throw "Missing $u" }
Copy-Item $u "$u.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"

$txt = Get-Content $u -Raw

# Ensure: from django.urls import path (at top)
if ($txt -notmatch "(?m)^\s*from\s+django\.urls\s+import\s+path\s*$") {
  $txt = "from django.urls import path`r`n" + $txt
}

# Ensure: from . import views (right after the path import)
if ($txt -notmatch "(?m)^\s*from\s+\.\s+import\s+views\s*$") {
  $txt = $txt -replace "(?m)^(from\s+django\.urls\s+import\s+path\s*$)", "`$1`r`nfrom . import views"
}

# Ensure: app_name = "stays" (before urlpatterns)
if ($txt -notmatch "(?m)^\s*app_name\s*=\s*['""]stays['""]\s*$") {
  if ($txt -match "(?s)from\s+\.\s+import\s+views\s*(\r?\n)+") {
    $txt = $txt -replace "(?s)(from\s+\.\s+import\s+views\s*(?:\r?\n)+)", "`$1app_name = 'stays'`r`n`r`n"
  } else {
    $txt = "app_name = 'stays'`r`n`r`n" + $txt
  }
}

Set-Content -Path $u -Value $txt -Encoding UTF8
Write-Host "✅ stays/urls.py header fixed."

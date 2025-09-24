# quick_fix_urls.ps1
$ErrorActionPreference = "Stop"
$urls = "stays\urls.py"
if (!(Test-Path $urls)) { throw "Missing $urls" }
Copy-Item $urls "$urls.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$t = Get-Content $urls -Raw
if ($t -notmatch "(?m)^\s*from\s+django\.urls\s+import\s+path") {
  $t = "from django.urls import path`r`n" + $t
}
if ($t -notmatch "(?m)^\s*from\s+\.\s+import\s+views") {
  $t = $t -replace "(?m)^\s*from\s+django\.urls\s+import\s+path\s*$", "$0`r`nfrom . import views"
}
Set-Content -Path $urls -Value $t -Encoding UTF8
Write-Host "✅ stays/urls.py imports are correct now."

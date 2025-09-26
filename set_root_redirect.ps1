# set_root_redirect.ps1
$ErrorActionPreference = "Stop"

# Find settings.py to locate the project folder (e.g., config/)
$projectRoot = Get-Location
$settingsFile = Get-ChildItem -Path $projectRoot -Recurse -Filter "settings.py" | Select-Object -First 1
if (-not $settingsFile) { Write-Error "Could not find settings.py under $projectRoot"; exit 1 }

$projectDir = Split-Path $settingsFile.FullName -Parent
$urlsFile   = Join-Path $projectDir "urls.py"

# Backup existing urls.py
if (Test-Path $urlsFile) {
    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    Copy-Item $urlsFile "$urlsFile.bak.$ts" -Force
    Write-Host "Backup: $urlsFile.bak.$ts"
}

# Write clean urls.py with root redirect
$urlsContent = @'
from django.contrib import admin
from django.urls import path, include
from django.views.generic import RedirectView

urlpatterns = [
    path("", RedirectView.as_view(url="/stays/", permanent=False)),
    path("admin/", admin.site.urls),
    path("stays/", include("stays.urls", namespace="stays")),
]
'@

Set-Content -Path $urlsFile -Value $urlsContent -Encoding UTF8
Write-Host "Wrote root-redirecting $urlsFile"

Write-Host "`nNext:"
Write-Host "  python manage.py runserver"
Write-Host "Then open: http://127.0.0.1:8000/ (it should jump to /stays/)"

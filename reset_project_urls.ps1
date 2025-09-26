# reset_project_urls.ps1
$ErrorActionPreference = "Stop"

# Look for settings.py under the project root
$projectRoot = Get-Location
$settingsFile = Get-ChildItem -Path $projectRoot -Recurse -Filter "settings.py" | Select-Object -First 1

if (-not $settingsFile) {
    Write-Error "Could not find settings.py under $projectRoot. Run this from your project root (where manage.py lives)."
    exit 1
}

$projectDir = Split-Path $settingsFile.FullName -Parent
$urlsFile   = Join-Path $projectDir "urls.py"

if (Test-Path $urlsFile) {
    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    Copy-Item $urlsFile "$urlsFile.bak.$ts" -Force
    Write-Host "Backup: $urlsFile.bak.$ts"
} else {
    Write-Host "urls.py not found, will create new one."
}

$urlsContent = @'
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path("admin/", admin.site.urls),
    path("stays/", include("stays.urls", namespace="stays")),
]
'@

Set-Content -Path $urlsFile -Value $urlsContent -Encoding UTF8
Write-Host "Wrote clean $urlsFile"

Write-Host "`nNow run: python manage.py runserver"

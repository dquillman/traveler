# add_missing_stubs.ps1
# Adds minimal stub views to stays/views.py for routes still referenced in config/urls.py

$ErrorActionPreference = "Stop"
$viewsPath = "stays\views.py"
if (-not (Test-Path $viewsPath)) { throw "stays\views.py not found." }

# Read file once
$views = Get-Content $viewsPath -Raw

# Ensure HttpResponse import present
if ($views -notmatch "from\s+django\.http\s+import\s+HttpResponse") {
    if ($views -match "from\s+django\.http\s+import\s+JsonResponse") {
        $views = $views -replace "from\s+django\.http\s+import\s+JsonResponse", "from django.http import JsonResponse, HttpResponse"
    } else {
        # Put the import near the top, before first def
        $views = "from django.http import HttpResponse`r`n" + $views
    }
}

# List of likely legacy views still referenced by urls/nav
$need = @(
    "appearance_view",
    "export_view",
    "import_view",
    "charts_view",
    "map_view"
)

# Build any missing stubs
$added = @()
foreach ($name in $need) {
    if ($views -notmatch "\bdef\s+$name\s*\(") {
        $stub = @"
def $name(request):
    return HttpResponse("$name page (stub).")
"@
        $views += "`r`n" + $stub + "`r`n"
        $added += $name
    }
}

# Write back only if we added anything
if ($added.Count -gt 0) {
    Set-Content -Path $viewsPath -Value $views -Encoding UTF8
    Write-Host ("Added stubs: " + ($added -join ", "))
} else {
    Write-Host "All stubs already present. No changes made."
}

Write-Host ""
Write-Host "Now run: python manage.py runserver"

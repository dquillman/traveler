# add_legacy_view_stubs.ps1
# Adds simple stub views (appearance_view, export_view, import_view, charts_view, map_view)
# to stays/views.py if they don't already exist.

$ErrorActionPreference = "Stop"
$viewsPath = "stays\views.py"
if (-not (Test-Path $viewsPath)) { throw "stays\views.py not found." }

# Read once
$content = Get-Content $viewsPath -Raw

# Ensure HttpResponse import is available
if ($content -notmatch "from\s+django\.http\s+import\s+HttpResponse") {
    if ($content -match "from\s+django\.http\s+import\s+JsonResponse") {
        $content = $content -replace "from\s+django\.http\s+import\s+JsonResponse",
                                   "from django.http import JsonResponse, HttpResponse"
    } else {
        # Place near top (before first def)
        $content = "from django.http import HttpResponse`r`n" + $content
    }
}

$stubs = @(
    "appearance_view",
    "export_view",
    "import_view",
    "charts_view",
    "map_view"
)

$added = @()
foreach ($name in $stubs) {
    if ($content -notmatch "\bdef\s+$name\s*\(") {
        $content += "`r`n`r`n" + @"
def $name(request):
    return HttpResponse("$name page (stub).")
"@
        $added += $name
    }
}

Set-Content $viewsPath $content -Encoding UTF8
if ($added.Count -gt 0) {
    Write-Host ("Added stubs: " + ($added -join ", "))
} else {
    Write-Host "All stubs already present; no changes made."
}

Write-Host "Done. Now run: python manage.py runserver"

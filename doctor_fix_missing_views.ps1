param(
  [string]$Repo = "G:\users\daveq\traveler"
)

# doctor_fix_missing_views.ps1
# Scans config/urls.py for references to stays_views.<func> and handler* strings
# and appends missing stubs to stays/views.py so Django can boot.

$ErrorActionPreference = "Stop"

# Paths
$configUrls = Join-Path $Repo "config\urls.py"
$viewsPath  = Join-Path $Repo "stays\views.py"

if (-not (Test-Path -LiteralPath $configUrls)) { throw "Not found: $configUrls" }
if (-not (Test-Path -LiteralPath $viewsPath))  { throw "Not found: $viewsPath"  }

# Read files
$config = Get-Content -Raw -LiteralPath $configUrls
$views  = Get-Content -Raw -LiteralPath $viewsPath

# Collect function names referenced as stays_views.FUNC
$funcPattern = [regex]'stays_views\.(\w+)\b'
$funcs = @()
foreach($m in $funcPattern.Matches($config)){
  $funcs += $m.Groups[1].Value
}

# Collect error handler names like 'stays.views.some_handler'
$handlerPattern = [regex]"handler(?:404|500|403|400)\s*=\s*['""]stays\.views\.(\w+)['""]"
foreach($m in $handlerPattern.Matches($config)){
  $funcs += $m.Groups[1].Value
}

$funcs = ($funcs | Sort-Object -Unique)

if (-not $funcs -or $funcs.Count -eq 0) {
  Write-Host "No stays views referenced in config/urls.py. Nothing to do."
  exit 0
}

Write-Host "Functions referenced in config/urls.py:"
$funcs | ForEach-Object { Write-Host "  - $_" }

# Check which exist in stays/views.py
$missing = @()
foreach($f in $funcs){
  if ($views -notmatch ("(?ms)^\s*def\s+" + [regex]::Escape($f) + "\s*\(")) {
    $missing += $f
  }
}

if ($missing.Count -eq 0) {
  Write-Host "All referenced views already exist in stays/views.py"
  exit 0
}

Write-Host "Missing functions to add:"
$missing | ForEach-Object { Write-Host "  - $_" }

# Ensure minimal imports exist
$needAdd = @()
if ($views -notmatch 'from\s+django\.http\s+import\s+HttpResponse') { $needAdd += "from django.http import HttpResponse" }
if ($views -notmatch 'from\s+django\.shortcuts\s+import\s+render')   { $needAdd += "from django.shortcuts import render" }
if ($needAdd.Count -gt 0) {
  $views = ($needAdd -join "`r`n") + "`r`n" + $views
}

# Build stubs
$stubBlocks = @()
foreach($name in $missing){
  switch ($name) {
    'map_view' {
      $stubBlocks += @"
def map_view(request):
    # Delegate to stay_list so the map page works immediately
    return stay_list(request)
"@
    }
    'appearance_view' {
      $stubBlocks += @"
def appearance_view(request):
    return HttpResponse("Appearance — placeholder")
"@
    }
    'export_view' {
      $stubBlocks += @"
def export_view(request):
    return HttpResponse("Export — placeholder")
"@
    }
    'import_view' {
      $stubBlocks += @"
def import_view(request):
    return HttpResponse("Import — placeholder")
"@
    }
    'charts_view' {
      $stubBlocks += @"
def charts_view(request):
    return HttpResponse("Charts — placeholder")
"@
    }
    'custom_404' {
      $stubBlocks += @"
def custom_404(request, exception):
    return HttpResponse("Not found", status=404)
"@
    }
    'custom_500' {
      $stubBlocks += @"
def custom_500(request):
    return HttpResponse("Server error", status=500)
"@
    }
    'custom_403' {
      $stubBlocks += @"
def custom_403(request, exception):
    return HttpResponse("Forbidden", status=403)
"@
    }
    'custom_400' {
      $stubBlocks += @"
def custom_400(request, exception):
    return HttpResponse("Bad request", status=400)
"@
    }
    Default {
      $stubBlocks += @"
def $name(request):
    return HttpResponse("$name — placeholder")
"@
    }
  }
}

$append = "`r`n`r`n# --- Auto-added stubs by doctor_fix_missing_views.ps1 ---`r`n" + ($stubBlocks -join "`r`n")

# Backup and write
$bak = "$viewsPath.bak"
Set-Content -NoNewline -LiteralPath $bak -Value $views
Set-Content -NoNewline -LiteralPath $viewsPath -Value ($views.TrimEnd() + $append + "`r`n")

Write-Host "Appended stubs to: $viewsPath  (backup at $bak)"
Write-Host "Now try: python manage.py runserver"

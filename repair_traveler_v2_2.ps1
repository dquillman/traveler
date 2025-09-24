<# =====================================================================
  Traveler Repair v2.2
  Makes header menu links functional by adding routes, views, templates:
    - /stays/charts/
    - /stays/import/
    - /stays/export/
    - /appearance/  (root-level)
  Also normalizes UTF-8 and keeps your header intact.
===================================================================== #>

param([string]$ProjectRoot = (Get-Location).Path)

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Backup-File([string]$path){
  if(Test-Path $path){
    $bak = "$path.bak.$stamp"
    Copy-Item $path $bak -Force
    Write-Host "Backup: $bak"
  }
}
function Ensure-Dir([string]$p){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }
function Write-UTF8([string]$path, [string]$text){
  $bytes = $utf8NoBom.GetBytes($text)
  [System.IO.File]::WriteAllBytes($path, $bytes)
}

# ----- Paths
$templatesDir = Join-Path $ProjectRoot "templates"
$staysTemplatesDir = Join-Path $templatesDir "stays"
$stayListFile = Join-Path $staysTemplatesDir "stay_list.html"
$staysAppUrls = Join-Path $ProjectRoot "stays\urls.py"
$staysAppViews = Join-Path $ProjectRoot "stays\views.py"

# Try to locate project (root) urls.py (the one that includes settings.py sibling)
# Heuristic: find a folder containing settings.py with a urls.py beside it
$projectUrls = $null
$settingsCandidates = Get-ChildItem $ProjectRoot -Recurse -Filter settings.py -ErrorAction SilentlyContinue
foreach($s in $settingsCandidates){
  $projFolder = Split-Path $s.FullName -Parent
  $urlsCandidate = Join-Path $projFolder "urls.py"
  if(Test-Path $urlsCandidate){
    $projectUrls = $urlsCandidate
    break
  }
}

# ----- Ensure dirs
Ensure-Dir $templatesDir
Ensure-Dir $staysTemplatesDir

# ----- Minimal shared header snippet (keeps your look)
$headerHTML = @'
  <header>
    <div class="brand">Traveler</div>
    <nav>
      <a href="/stays/">Stays</a>
      <a href="/stays/add/">Add</a>
      <a href="/stays/#map">Map</a>
      <a href="/stays/charts/">Charts</a>
      <a href="/stays/import/">Import</a>
      <a href="/stays/export/">Export</a>
      <a href="/appearance/">Appearance</a>
    </nav>
  </header>
'@

# ----- Base page generator (style matches your Stays page)
function New-Page([string]$title, [string]$bodyHtml){
  @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Traveler • $title</title>
  <link rel="icon" href="/static/favicon.ico" sizes="any">
  <style>
    :root { --bg:#0f1220; --card:#161a2b; --ink:#e8ebff; --muted:#9aa4d2; --line:#272b41; --accent:#b9c6ff; }
    *{box-sizing:border-box}
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Arial; margin:0; background:var(--bg); color:var(--ink); }
    header { padding:14px 18px; background:#101425; color:#fff; display:flex; align-items:center; gap:16px; }
    header .brand { font-weight:700; }
    header nav a { color:var(--accent); text-decoration:none; margin-right:14px; }
    .wrap { max-width:1200px; margin:0 auto; padding:16px; }
    .panel { background:var(--card); border:1px solid var(--line); border-radius:14px; box-shadow:0 8px 24px rgba(0,0,0,.25); padding:16px; }
    .muted { color: var(--muted); }
    .button { display:inline-block; margin-top:8px; padding:8px 12px; border-radius:10px; border:1px solid var(--line); color:var(--ink); text-decoration:none; background:#1c2040; }
    pre { white-space:pre-wrap; }
  </style>
</head>
<body>
$headerHTML
  <div class="wrap">
    <div class="panel">
      $bodyHtml
    </div>
  </div>
</body>
</html>
"@
}

# ----- Create stub templates if missing
$chartsTpl = Join-Path $staysTemplatesDir "charts.html"
$importTpl = Join-Path $staysTemplatesDir "import.html"
$exportTpl = Join-Path $staysTemplatesDir "export.html"
$appearanceTpl = Join-Path $templatesDir "appearance.html"  # root-level page

if(-not (Test-Path $chartsTpl)){
  $html = New-Page "Charts" "<h1>Charts</h1><p class='muted'>Your charts page is ready. Plug charts here.</p>"
  Write-UTF8 $chartsTpl $html
  Write-Host "Created: $chartsTpl"
}
if(-not (Test-Path $importTpl)){
  $html = New-Page "Import" "<h1>Import</h1><p class='muted'>Upload a CSV here (wire form & view logic later).</p>"
  Write-UTF8 $importTpl $html
  Write-Host "Created: $importTpl"
}
if(-not (Test-Path $exportTpl)){
  $html = New-Page "Export" "<h1>Export</h1><p class='muted'>Download CSV/JSON from here (wire logic later).</p>"
  Write-UTF8 $exportTpl $html
  Write-Host "Created: $exportTpl"
}
if(-not (Test-Path $appearanceTpl)){
  $html = New-Page "Appearance" "<h1>Appearance</h1><p class='muted'>Theme & UI settings go here.</p>"
  Write-UTF8 $appearanceTpl $html
  Write-Host "Created: $appearanceTpl"
}

# ----- Patch stays/views.py with new views
if(Test-Path $staysAppViews){
  $views = Get-Content $staysAppViews -Raw
  $orig = $views
  if($views -notmatch 'from\s+django\.shortcuts\s+import\s+render'){
    $views = "from django.shortcuts import render`r`n" + $views
  }
  $blocks = @(
@'
def stays_charts(request):
    return render(request, "stays/charts.html", {})
'@,
@'
def stays_import(request):
    return render(request, "stays/import.html", {})
'@,
@'
def stays_export(request):
    return render(request, "stays/export.html", {})
'@
  )
  foreach($b in $blocks){
    if($views -notmatch [regex]::Escape(($b -split "`r?`n")[0])){
      $views = $views.TrimEnd() + "`r`n`r`n" + $b + "`r`n"
    }
  }
  if($views -ne $orig){
    Backup-File $staysAppViews
    Write-UTF8 $staysAppViews $views
    Write-Host "Updated views: $staysAppViews"
  }
} else {
  Write-Warning "Missing: $staysAppViews"
}

# ----- Patch stays/urls.py to include the new routes
if(Test-Path $staysAppUrls){
  $urls = Get-Content $staysAppUrls -Raw
  $orig = $urls
  if($urls -notmatch 'from\s+\.\s+import\s+views'){ $urls = $urls -replace '(^\s*from\s+django\.urls\s+import\s+path[^\n]*$)', '$1' + "`r`nfrom . import views" }
  if($urls -notmatch 'urlpatterns\s*='){ $urls += "`r`nurlpatterns = []`r`n" }
  # ensure entries
  $wanted = @(
    'path("charts/", views.stays_charts, name="stays_charts")',
    'path("import/", views.stays_import, name="stays_import")',
    'path("export/", views.stays_export, name="stays_export")'
  )
  foreach($w in $wanted){
    if($urls -notmatch [regex]::Escape($w)){
      $urls = $urls -replace 'urlpatterns\s*=\s*\[', "urlpatterns = [" + "`r`n    $w,"
    }
  }
  if($urls -ne $orig){
    Backup-File $staysAppUrls
    Write-UTF8 $staysAppUrls $urls
    Write-Host "Updated URLs: $staysAppUrls"
  }
} else {
  Write-Warning "Missing: $staysAppUrls"
}

# ----- Add /appearance/ at project root urls.py -> points to a lightweight view we’ll inject into stays.views
if($projectUrls){
  # Ensure appearance view exists (simple render of templates/appearance.html)
  if(Test-Path $staysAppViews){
    $views = Get-Content $staysAppViews -Raw
    if($views -notmatch 'def\s+appearance\s*\('){
      $views += @'

def appearance(request):
    return render(request, "appearance.html", {})
'@
      Backup-File $staysAppViews
      Write-UTF8 $staysAppViews $views
      Write-Host "Added appearance view to: $staysAppViews"
    }
  }

  $purls = Get-Content $projectUrls -Raw
  $orig = $purls
  if($purls -notmatch 'from\s+stays\s+import\s+views\s+as\s+stays_views'){
    if($purls -match 'from\s+django\.urls\s+import\s+path(?:,\s*include)?'){
      $purls = $purls -replace '(from\s+django\.urls\s+import\s+path(?:,\s*include)?[^\n]*\n)', '$0from stays import views as stays_views' + "`r`n"
    } else {
      $purls = "from django.urls import path, include`r`nfrom stays import views as stays_views`r`n" + $purls
    }
  }
  if($purls -notmatch 'urlpatterns\s*='){
    $purls += "`r`nurlpatterns = [ path(""appearance/"", stays_views.appearance, name=""appearance"") ]`r`n"
  } else {
    # Insert appearance path if missing
    if($purls -notmatch 'appearance.*stays_views\.appearance'){
      $purls = $purls -replace 'urlpatterns\s*=\s*\[', 'urlpatterns = [' + "`r`n    path(""appearance/"", stays_views.appearance, name=""appearance""),"
    }
  }
  if($purls -ne $orig){
    Backup-File $projectUrls
    Write-UTF8 $projectUrls $purls
    Write-Host "Root URL wired: $projectUrls (appearance)"
  }
} else {
  Write-Warning "Could not locate project urls.py (root). If /appearance/ 404s, tell me your project urls path."
}

Write-Host ""
Write-Host "==============================================================="
Write-Host "Menus are now wired:"
Write-Host "  /stays/charts/   -> stays.charts.html"
Write-Host "  /stays/import/   -> stays.import.html"
Write-Host "  /stays/export/   -> stays.export.html"
Write-Host "  /appearance/     -> appearance.html"
Write-Host "Restart server and open /stays/ (use Ctrl+F5)."
Write-Host "==============================================================="

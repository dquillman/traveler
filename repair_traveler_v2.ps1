<# =====================================================================
  Traveler Repair (UTF-8, Banner/Menus, /stays/map-data/)
  Filename: repair_traveler_v2.ps1
  Run from project root (same folder as manage.py)
===================================================================== #>

param(
  [string]$ProjectRoot = (Get-Location).Path
)

# ---------- Helpers ----------
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Backup-File([string]$path){
  if(Test-Path $path){
    $bak = "$path.bak.$stamp"
    Copy-Item $path $bak -Force
    Write-Host "Backup: $bak"
  }
}

function Ensure-Dir([string]$path){
  if(-not (Test-Path $path)){ New-Item -ItemType Directory -Path $path | Out-Null }
}

function Convert-1252-To-UTF8([string]$file){
  try{
    $bytes = [System.IO.File]::ReadAllBytes($file)
    # Try decode as UTF-8 first; if OK, skip
    try{
      [void][System.Text.Encoding]::UTF8.GetString($bytes)
      # If decode succeeded and file already UTF-8, do nothing
      return
    } catch {
      # Fall through and try 1252
    }
    $win1252 = [System.Text.Encoding]::GetEncoding(1252)
    $text = $win1252.GetString($bytes)
    [System.IO.File]::WriteAllText($file, $text, $utf8NoBom)
    Write-Host "Converted to UTF-8: $file"
  } catch {
    Write-Warning "Encoding convert failed: $file ($($_.Exception.Message))"
  }
}

function Replace-Header-With-FullMenu([string]$file){
  if(-not (Test-Path $file)){ return }
  $html = Get-Content $file -Raw
  $newHeader = @'
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

  if($html -match '<header>.*?</header>'s){
    $patched = [System.Text.RegularExpressions.Regex]::Replace(
      $html, '<header>.*?</header>', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newHeader }, 
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
  } else {
    # no header found; insert after <body>
    $patched = $html -replace '(<body[^>]*>)', "`$1`r`n$newHeader"
  }

  if($patched -ne $html){
    Backup-File $file
    Set-Content -Path $file -Value $patched -Encoding UTF8
    Write-Host "Header/menu restored in: $file"
  }
}

function Ensure-TitleBullet([string]$file){
  if(-not (Test-Path $file)){ return }
  $html = Get-Content $file -Raw
  $patched = $html -replace '<title>\s*Traveler\s*[•&bull;]\s*Stays\s*</title>', '<title>Traveler &bull; Stays</title>'
  $patched = $patched -replace '<title>\s*Traveler\s*[^<]*Stays\s*</title>', '<title>Traveler &bull; Stays</title>'
  if($patched -ne $html){
    Backup-File $file
    Set-Content -Path $file -Value $patched -Encoding UTF8
    Write-Host "Title normalized in: $file"
  }
}

function Ensure-MapData-Url([string]$urlsFile){
  if(-not (Test-Path $urlsFile)){ return }
  $text = Get-Content $urlsFile -Raw

  if($text -notmatch 'stays_map_data'){
    $importsFixed = $text
    if($importsFixed -notmatch 'from\s+\.\s+import\s+views'){
      $importsFixed = $importsFixed -replace '(from\s+django\.urls\s+import\s+path[^\n]*\n)', "`$1from . import views`r`n"
    }
    $pattern = 'urlpatterns\s*=\s*\[(.*?)\]'
    if($importsFixed -match $pattern){
      $inside = $Matches[1]
      if($inside -notmatch 'map-data/'){
        $newInside = ($inside.TrimEnd() + ",`r`n    path(\"map-data/\", views.stays_map_data, name=\"stays_map_data\"),")
        $importsFixed = $importsFixed -replace $pattern, "urlpatterns = [`r`n$newInside`r`n]"
      }
    } else {
      # create urlpatterns if missing
      $importsFixed += "`r`nfrom . import views`r`nurlpatterns = [ path(\"map-data/\", views.stays_map_data, name=\"stays_map_data\"), ]`r`n"
    }
    Backup-File $urlsFile
    Set-Content -Path $urlsFile -Value $importsFixed -Encoding UTF8
    Write-Host "Added /stays/map-data/ route in: $urlsFile"
  }
}

function Ensure-MapData-View([string]$viewsFile){
  if(-not (Test-Path $viewsFile)){ return }
  $text = Get-Content $viewsFile -Raw
  $needsWrite = $false

  if($text -notmatch 'def\s+stays_map_data\s*\('){
    $needsWrite = $true
    if($text -notmatch 'from\s+django\.http\s+import\s+JsonResponse'){
      $text = "from django.http import JsonResponse`r`n" + $text
    }
    if($text -notmatch 'from\s+django\.urls\s+import\s+reverse'){
      $text = "from django.urls import reverse`r`n" + $text
    }
    if($text -notmatch 'from\s+\.\s*models\s+import\s+Stay'){
      # Try a best-effort import
      if($text -match 'from\s+\.\s*models\s+import\s+(.+)'){
        # already imports something; add Stay if missing
        $text = $text -replace '(from\s+\.\s*models\s+import\s+)([^\n]+)', {
          param($m)
          $list = $m.Groups[2].Value
          if($list -notmatch '(^|,\s*)Stay(\s*,|$)'){ $list += ', Stay' }
          $m.Groups[1].Value + $list
        }
      } else {
        $text = "from .models import Stay`r`n" + $text
      }
    }

    $func = @'
def stays_map_data(request):
    qs = Stay.objects.all()
    items = []
    for s in qs:
        items.append({
            "id": s.id,
            "label": (s.label or ""),
            "latitude": getattr(s, "latitude", None),
            "longitude": getattr(s, "longitude", None),
            "popup_html": f"<strong>{(s.label or 'Stay')}</strong><br>{(s.city or '')}, {(s.state or '')}",
            "detail_url": reverse("stay_edit", args=[s.id]) if "stay_edit" else None,
        })
    return JsonResponse({"stays": items})
'@
    $text = $text.TrimEnd() + "`r`n`r`n" + $func + "`r`n"
  }

  if($needsWrite){
    Backup-File $viewsFile
    Set-Content -Path $viewsFile -Value $text -Encoding UTF8
    Write-Host "Added stays_map_data view in: $viewsFile"
  }
}

# ---------- Paths ----------
$templatesDir = Join-Path $ProjectRoot "templates"
$staysTemplatesDir = Join-Path $templatesDir "stays"
$stayListFile = Join-Path $staysTemplatesDir "stay_list.html"
$baseFile = Join-Path $templatesDir "base.html"
$staysUrls = Join-Path $ProjectRoot "stays\urls.py"
$staysViews = Join-Path $ProjectRoot "stays\views.py"

Write-Host "Project: $ProjectRoot"
Ensure-Dir $templatesDir
Ensure-Dir $staysTemplatesDir

# ---------- 1) Encoding: convert likely Windows-1252 -> UTF-8 ----------
$scan = @()
if(Test-Path $templatesDir){ $scan += Get-ChildItem $templatesDir -Recurse -Include *.html,*.css,*.txt -File -ErrorAction SilentlyContinue }
foreach($f in $scan){
  try { Backup-File $f.FullName; Convert-1252-To-UTF8 $f.FullName } catch {}
}

# ---------- 2) Restore full banner/menus in stay_list.html ----------
if(Test-Path $stayListFile){
  Replace-Header-With-FullMenu $stayListFile
  Ensure-TitleBullet $stayListFile
} else {
  Write-Warning "Missing: $stayListFile (cannot patch header)."
}

# Also ensure base title if present
if(Test-Path $baseFile){ Ensure-TitleBullet $baseFile }

# ---------- 3) Ensure /stays/map-data/ route and view ----------
if(Test-Path $staysUrls){ Ensure-MapData-Url $staysUrls } else { Write-Warning "Missing: $staysUrls" }
if(Test-Path $staysViews){ Ensure-MapData-View $staysViews } else { Write-Warning "Missing: $staysViews" }

# ---------- 4) Done / next steps ----------
Write-Host ""
Write-Host "==============================================================="
Write-Host "Repairs complete."
Write-Host "Now do:"
Write-Host "  1) Stop and restart your dev server (Ctrl+C, then):"
Write-Host "       (.venv) PS> python manage.py runserver"
Write-Host "  2) Hard refresh your browser (Ctrl+F5)"
Write-Host "  3) Open: http://127.0.0.1:8000/stays/"
Write-Host "     - Banner should show full menus"
Write-Host "     - Dashes/bullets should render correctly"
Write-Host "     - Map should load pins from /stays/map-data/"
Write-Host "==============================================================="

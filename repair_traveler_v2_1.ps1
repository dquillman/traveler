<# =====================================================================
  Traveler Repair v2.1 (UTF-8, Banner/Menus, /stays/map-data/)
  - Fixes mojibake by converting templates to UTF-8 (no BOM)
  - Restores full header/menus on stays page
  - Ensures /stays/map-data/ route + view exist
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

    # If it already decodes as UTF-8, skip
    try {
      [void][System.Text.Encoding]::UTF8.GetString($bytes)
      return
    } catch {}

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

  $pattern = '<header>.*?</header>'
  $hasHeader = [regex]::IsMatch($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  if($hasHeader){
    $patched = [regex]::Replace(
      $html, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newHeader },
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
  } else {
    # Insert after <body ...>
    $patched = [regex]::Replace(
      $html, '(<body[^>]*>)', '`$1' + "`r`n" + $newHeader
    )
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
  $patched = $html
  # Normalize any Traveler ... Stays title to Traveler &bull; Stays
  $patched = [regex]::Replace($patched, '<title>\s*Traveler\s*[^<]*?\s*Stays\s*</title>', '<title>Traveler &bull; Stays</title>')
  if($patched -ne $html){
    Backup-File $file
    Set-Content -Path $file -Value $patched -Encoding UTF8
    Write-Host "Title normalized in: $file"
  }
}

function Ensure-MapData-Url([string]$urlsFile){
  if(-not (Test-Path $urlsFile)){ return }
  $text = Get-Content $urlsFile -Raw
  $orig = $text

  if($text -notmatch 'from\s+\.\s+import\s+views'){
    if($text -match 'from\s+django\.urls\s+import\s+path[^\n]*\n'){
      $text = $text -replace '(from\s+django\.urls\s+import\s+path[^\n]*\n)', '$0from . import views' + "`r`n"
    } else {
      $text = "from django.urls import path`r`nfrom . import views`r`n" + $text
    }
  }

  if($text -notmatch 'urlpatterns\s*='){
    $text += "`r`nurlpatterns = [ path(""map-data/"", views.stays_map_data, name=""stays_map_data""), ]`r`n"
  } else {
    # Insert the line before the closing ]
    $pattern = 'urlpatterns\s*=\s*\[(.*?)\]'
    if([regex]::IsMatch($text, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline)){
      $m = [regex]::Match($text, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline)
      $inside = $m.Groups[1].Value
      if($inside -notmatch 'stays_map_data'){
        $newInside = ($inside.TrimEnd() + ",`r`n    path(""map-data/"", views.stays_map_data, name=""stays_map_data"")")
        $text = $text.Substring(0, $m.Index) + "urlpatterns = [" + "`r`n" + $newInside + "`r`n" + "]" + $text.Substring($m.Index + $m.Length)
      }
    } else {
      # Fallback: append a fresh urlpatterns line
      $text += "`r`n# fallback append`r`nurlpatterns += [ path(""map-data/"", views.stays_map_data, name=""stays_map_data"") ]`r`n"
    }
  }

  if($text -ne $orig){
    Backup-File $urlsFile
    Set-Content -Path $urlsFile -Value $text -Encoding UTF8
    Write-Host "Ensured /stays/map-data/ route in: $urlsFile"
  }
}

function Ensure-MapData-View([string]$viewsFile){
  if(-not (Test-Path $viewsFile)){ return }
  $text = Get-Content $viewsFile -Raw
  $orig = $text
  if($text -notmatch 'from\s+django\.http\s+import\s+JsonResponse'){
    $text = "from django.http import JsonResponse`r`n" + $text
  }
  if($text -notmatch 'from\s+django\.urls\s+import\s+reverse'){
    $text = "from django.urls import reverse`r`n" + $text
  }
  if($text -notmatch 'from\s+\.\s*models\s+import\s+Stay'){
    if($text -match 'from\s+\.\s*models\s+import\s+([^\n]+)'){
      $list = $Matches[1]
      if($list -notmatch '(^|,\s*)Stay(\s*,|$)'){
        $text = $text -replace '(from\s+\.\s*models\s+import\s+)([^\n]+)', '$1$2, Stay'
      }
    } else {
      $text = "from .models import Stay`r`n" + $text
    }
  }
  if($text -notmatch 'def\s+stays_map_data\s*\('){
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
            "detail_url": reverse("stay_edit", args=[s.id]) if True else None,
        })
    return JsonResponse({"stays": items})
'@
    $text = $text.TrimEnd() + "`r`n`r`n" + $func + "`r`n"
  }

  if($text -ne $orig){
    Backup-File $viewsFile
    Set-Content -Path $viewsFile -Value $text -Encoding UTF8
    Write-Host "Ensured stays_map_data view in: $viewsFile"
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
Write-Host "  1) Restart dev server:"
Write-Host "       (.venv) PS> python manage.py runserver"
Write-Host "  2) Hard refresh (Ctrl+F5) → http://127.0.0.1:8000/stays/"
Write-Host "     - Banner has full menus"
Write-Host "     - Dashes/bullets correct"
Write-Host "     - Map loads pins from /stays/map-data/"
Write-Host "==============================================================="

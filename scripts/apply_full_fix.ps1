param([string]$RepoRoot = ".")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Backup-File([string]$Path){ if(Test-Path $Path){ $ts=Get-Date -Format "yyyyMMdd_HHmmss"; Copy-Item $Path "$Path.bak.$ts" -Force } }
function Ensure-Dir([string]$Path){ if(-not(Test-Path $Path)){ New-Item -ItemType Directory -Force -Path $Path | Out-Null } }

function Patch-Settings([string]$SettingsPath){
  Backup-File $SettingsPath
  $t = Get-Content -Raw $SettingsPath
  if($t -notmatch 'from pathlib import Path'){ $t = "from pathlib import Path`r`n" + $t }
  if($t -notmatch '(?m)^BASE_DIR\s*='){ $t = $t -replace '(?m)^(from pathlib import Path.*\n)', "`$1BASE_DIR = Path(__file__).resolve().parent.parent`r`n" }
  if($t -notmatch '(?m)^\s*MEDIA_URL\s*='){ $t += "`r`nMEDIA_URL = '/media/'`r`n" } else { $t = $t -replace '(?m)^\s*MEDIA_URL\s*=.*$', "MEDIA_URL = ''/media/''" -replace "''", "'" }
  if($t -notmatch '(?m)^\s*MEDIA_ROOT\s*='){ $t += "MEDIA_ROOT = BASE_DIR / 'media'`r`n" } else { $t = $t -replace '(?m)^\s*MEDIA_ROOT\s*=.*$', "MEDIA_ROOT = BASE_DIR / 'media'" }
  Set-Content $SettingsPath $t -Encoding UTF8
}

function Patch-Urls([string]$UrlsPath){
  Backup-File $UrlsPath
  $t = Get-Content -Raw $UrlsPath
  if($t -notmatch 'from django\.conf import settings'){ $t = "from django.conf import settings`r`n" + $t }
  if($t -notmatch 'from django\.conf\.urls\.static import static'){ $t = "from django.conf.urls.static import static`r`n" + $t }
  if($t -notmatch 'urlpatterns\s*\+\=\s*static'){ $t += "`r`nif settings.DEBUG:`r`n    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)`r`n" }
  Set-Content $UrlsPath $t -Encoding UTF8
}

function Insert-Navbar([string]$BasePath){
  if(-not(Test-Path $BasePath)){ return $false }
  Backup-File $BasePath
  $t = Get-Content -Raw $BasePath

  # Ensure {% load static %} exists
  if($t -notmatch '{% *load +static *%}'){ $t = "{% load static %}`r`n" + $t }

  # Ensure dark CSS link present
  if($t -notmatch 'css/site_dark_theme\.css'){
    if($t -match '</head>'){
      $t = $t -replace '</head>', "  <link rel=""stylesheet"" href=""{% static 'css/site_dark_theme.css' %}"">`r`n</head>"
    } else {
      $t = '<link rel="stylesheet" href="{% static ''css/site_dark_theme.css'' %}">' + "`r`n" + $t
    }
  }

  # Insert navbar include after <body>, or prepend if no <body>
  if($t -match '<body[^>]*>'){
    if($t -notmatch '{% *include +"_includes/navbar\.html" *%}'){
      $t = $t -replace '(<body[^>]*>)', "`$1`r`n{% include ""_includes/navbar.html"" %}"
    }
  } else {
    if($t -notmatch '{% *include +"_includes/navbar\.html" *%}'){
      $t = '{% include "_includes/navbar.html" %}' + "`r`n" + $t
    }
  }

  Set-Content $BasePath $t -Encoding UTF8
  return $true
}

Set-Location $RepoRoot

$patched = $false
$baseCandidates = @("templates/base.html","templates/_base.html","templates/layouts/base.html")
foreach($b in $baseCandidates){ if(Test-Path $b){ if(Insert-Navbar $b){ $patched = $true } } }
if(-not $patched){ Write-Host "Warning: no base template found to patch." -ForegroundColor Yellow }

Ensure-Dir "media/stays_photos"

$settingsCandidates = @("config/settings.py","project/settings.py","core/settings.py")
$urlsCandidates     = @("config/urls.py","project/urls.py","core/urls.py")

$settings = $null; foreach($p in $settingsCandidates){ if(Test-Path $p){ $settings = $p; break } }
$urls     = $null; foreach($p in $urlsCandidates){     if(Test-Path $p){ $urls     = $p; break } }

if($settings){ Patch-Settings $settings } else { Write-Host "settings.py not found to patch" -ForegroundColor Yellow }
if($urls){     Patch-Urls     $urls     } else { Write-Host "urls.py not found to patch"     -ForegroundColor Yellow }

Write-Host "apply_full_fix.ps1 finished." -ForegroundColor Green

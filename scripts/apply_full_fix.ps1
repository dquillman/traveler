
param(
  [string]$RepoRoot = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Backup-File {
  param([string]$Path)
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $bak = "$Path.bak.$stamp"
    Copy-Item $Path $bak -Force
    Write-Host "Backup: $Path -> $bak" -ForegroundColor Yellow
  }
}

function Ensure-Dir {
  param([string]$Path)
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

function Ensure-Text {
  param([string]$Path, [string]$Content)
  Ensure-Dir (Split-Path -Parent $Path)
  Set-Content -Path $Path -Value $Content -Encoding UTF8
  Write-Host "Wrote: $Path"
}

function Patch-Settings {
  param([string]$SettingsPath)
  if (-not (Test-Path $SettingsPath)) { throw "settings.py not found at $SettingsPath" }

  Backup-File $SettingsPath
  $text = Get-Content -Raw -Path $SettingsPath

  # Ensure BASE_DIR import (Pathlib) exists
  if ($text -notmatch 'BASE_DIR\s*=\s*Path') {
    if ($text -notmatch 'from pathlib import Path') {
      $text = "from pathlib import Path`r`n" + $text
    }
    $text = $text -replace '(?m)^(#.*)?$', "`$0"
    if ($text -notmatch '(?m)^BASE_DIR\s*=') {
      # Insert near top
      $text = $text -replace '(?m)^(from pathlib import Path.*\n)', "`$1BASE_DIR = Path(__file__).resolve().parent.parent`r`n"
    }
  }

  # Add/patch MEDIA_URL and MEDIA_ROOT
  if ($text -notmatch '(?m)^\s*MEDIA_URL\s*=') {
    $text += "`r`nMEDIA_URL = '/media/'`r`n"
  } else {
    $text = $text -replace "(?m)^\s*MEDIA_URL\s*=.*$", "MEDIA_URL = '/media/'"
  }
  if ($text -notmatch '(?m)^\s*MEDIA_ROOT\s*=') {
    $text += "MEDIA_ROOT = BASE_DIR / 'media'`r`n"
  } else {
    $text = $text -replace "(?m)^\s*MEDIA_ROOT\s*=.*$", "MEDIA_ROOT = BASE_DIR / 'media'"
  }

  Set-Content -Path $SettingsPath -Value $text -Encoding UTF8
  Write-Host "Patched: $SettingsPath"
}

function Patch-Urls {
  param([string]$UrlsPath)
  if (-not (Test-Path $UrlsPath)) { throw "urls.py not found at $UrlsPath" }

  Backup-File $UrlsPath
  $text = Get-Content -Raw -Path $UrlsPath

  # Ensure imports
  if ($text -notmatch 'from django\.conf import settings') {
    $text = "from django.conf import settings`r`n" + $text
  }
  if ($text -notmatch 'from django\.conf\.urls\.static import static') {
    $text = "from django.conf.urls.static import static`r`n" + $text
  }

  # Append static block if missing
  if ($text -notmatch 'urlpatterns\s*\+\=\s*static') {
    $text += "`r`n# DEV ONLY: serve uploaded media at /media/`r`nif settings.DEBUG:`r`n    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)`r`n"
  }

  Set-Content -Path $UrlsPath -Value $text -Encoding UTF8
  Write-Host "Patched: $UrlsPath"
}

function Insert-Navbar-Include {
  param([string]$BasePath)
  if (-not (Test-Path $BasePath)) { return $false }

  Backup-File $BasePath
  $text = Get-Content -Raw -Path $BasePath

  # Ensure {% load static %}
  if ($text -notmatch '{% *load +static *%}') {
    $text = "{% load static %}`r`n" + $text
  }

  # Ensure dark CSS link
  if ($text -notmatch 'css/site_dark_theme\.css') {
    if ($text -match '</head>') {
      $link = '<link rel="stylesheet" href="{% static ''css/site_dark_theme.css'' %}">'
      $text = $text -replace '</head>', ("  " + $link + "`r`n</head>")
    } else {
      $text = '<link rel="stylesheet" href="{% static ''css/site_dark_theme.css'' %}">' + "`r`n" + $text
    }
  }

  # Insert navbar include right after <body>
  if ($text -match '<body[^>]*>') {
    if ($text -notmatch '{% *include +"_includes/navbar\.html" *%}') {
      $text = $text -replace '(<body[^>]*>)', "`$1`r`n{% include ""_includes/navbar.html"" %}"
    }
  } else {
    # Fallback: prepend include at top if no body tag
    if ($text -notmatch '{% *include +"_includes/navbar\.html" *%}') {
      $text = '{% include "_includes/navbar.html" %}' + "`r`n" + $text
    }
  }

  Set-Content -Path $BasePath -Value $text -Encoding UTF8
  Write-Host "Patched navbar include in: $BasePath"
  return $true
}

# ---- main ----
Set-Location $RepoRoot

# 0) Guess project root "config" module (based on earlier messages)
$urlsCandidates = @(
  "config/urls.py",
  "project/urls.py",
  "core/urls.py"
)
$settingsCandidates = @(
  "config/settings.py",
  "project/settings.py",
  "core/settings.py"
)

$urlsPath = $null
foreach ($p in $urlsCandidates) { if (Test-Path $p) { $urlsPath = $p; break } }
if (-not $urlsPath) { throw "Could not find project urls.py (tried: $($urlsCandidates -join ', '))" }

$settingsPath = $null
foreach ($p in $settingsCandidates) { if (Test-Path $p) { $settingsPath = $p; break } }
if (-not $settingsPath) { throw "Could not find project settings.py (tried: $($settingsCandidates -join ', '))" }

# 1) Ensure media directories
New-Item -ItemType Directory -Force -Path "media\stays_photos" | Out-Null

# 2) Write navbar include (non-destructive; referenced from base.html)
$navbar = @'
<div class="nav-hotfix" style="background:#111827;border-bottom:1px solid #1f2937;position:sticky;top:0;z-index:1000;">
  <div class="container" style="max-width:1100px;margin:0 auto;display:flex;align-items:center;gap:16px;padding:10px 16px;">
    <strong style="color:#e6e6e6;">Traveler</strong>
    <a href="{% url 'stays:list' %}" class="button" style="text-decoration:none;padding:6px 10px;border-radius:8px;background:#3b82f6;color:#0b0f19;">Stays</a>
    <a href="{% url 'stays:add' %}" class="button" style="text-decoration:none;padding:6px 10px;border-radius:8px;background:#22d3ee;color:#0b0f19;">Add Stay</a>
  </div>
</div>
'@
Ensure-Text "templates/_includes/navbar.html" $navbar

# 3) Dark theme CSS (idempotent)
$darkCss = Get-Content -Raw -Path "static/css/site_dark_theme.css" -ErrorAction SilentlyContinue
if (-not $darkCss) {
  $darkCss = @'
/* Global dark theme */
:root{
  --bg:#0e1117;
  --panel:#111827;
  --muted:#94a3b8;
  --text:#e6e6e6;
  --accent:#3b82f6;
  --accent-2:#22d3ee;
  --border:#1f2937;
  --table-strip:#0b1220;
}
* { box-sizing: border-box; }
html, body { background: var(--bg); color: var(--text); margin: 0;
  font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji"; }
.container { max-width: 1100px; margin: 0 auto; }
.navbar, header, footer { background: var(--panel) !important; color: var(--text) !important; border-bottom: 1px solid var(--border); }
.footer { border-top: 1px solid var(--border); }
.card, .panel, .content, .box { background: var(--panel); color: var(--text); border: 1px solid var(--border); border-radius: 10px; }
a { color: var(--accent); text-decoration: none; } a:hover { color: var(--accent-2); }
.button, button, input[type=submit] { background: var(--accent); color: #0b0f19; border: 0; padding: 8px 14px; border-radius: 8px; cursor: pointer;}
.button:hover, button:hover, input[type=submit]:hover { filter: brightness(1.1); }
input, select, textarea { background: #0b1220 !important; color: var(--text) !important; border: 1px solid var(--border) !important; border-radius: 8px; padding: 8px; }
input::placeholder, textarea::placeholder { color: var(--muted); }
table { width: 100%; border-collapse: collapse; background: var(--panel); color: var(--text); }
th, td { border-bottom: 1px solid var(--border); padding: 8px 10px; }
thead th { text-align: left; font-weight: 600; }
tbody tr:nth-child(odd){ background: var(--table-strip); }
#map { border: 1px solid var(--border); border-radius: 10px; }
'@
  Ensure-Text "static/css/site_dark_theme.css" $darkCss
}

# 4) Patch base template to include navbar + dark css
$baseCandidates = @(
  "templates/base.html",
  "templates/_base.html",
  "templates/layouts/base.html"
)
$patchedAny = $false
foreach ($b in $baseCandidates) {
  if (Test-Path $b) {
    if (Insert-Navbar-Include $b) { $patchedAny = $true }
  }
}
if (-not $patchedAny) {
  Write-Host "Warning: No base template found to patch. Include the navbar manually where desired." -ForegroundColor Yellow
}

# 5) Patch settings/urls for media
Patch-Settings $settingsPath
Patch-Urls $urlsPath

Write-Host "All patches applied successfully." -ForegroundColor Green

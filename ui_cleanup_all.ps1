# ui_cleanup_all.ps1
# Purpose: Finish UI cleanup across the site.
# - Create/append static/css/style.css with tables + forms styling
# - Ensure base.html loads the stylesheet, includes top_nav once, and has {% block content %}
# - Rewrite templates/stays/stay_form.html to extend base.html (banner + styles)
# Backups: any touched file gets .bak.<timestamp>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

function BackupWrite($path, $content) {
  if (Test-Path $path) { Copy-Item $path "$path.bak.$ts" -Force }
  $dir = Split-Path $path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  Set-Content -Path $path -Value $content -Encoding UTF8
}

function SafeSetContent($path, $content) {
  Copy-Item $path "$path.bak.$ts" -Force
  Set-Content -Path $path -Value $content -Encoding UTF8
}

# ---------- 1) Ensure global stylesheet with tables + forms ----------
$cssDir = ".\static\css"
$cssPath = Join-Path $cssDir "style.css"
if (-not (Test-Path $cssDir)) { New-Item -ItemType Directory -Path $cssDir | Out-Null }

$baseCss = @'
:root { --bg:#0f1220; --card:#161a2b; --ink:#e8ebff; --muted:#9aa4d2; --line:#272b41; --accent:#b9c6ff; }
*{box-sizing:border-box}
body { margin:0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Arial; background:var(--bg); color:var(--ink); }
.wrap { max-width: 1200px; margin: 0 auto; padding: 16px; }

/* Tables */
table { width:100%; border-collapse: collapse; background: var(--card); border-radius: 14px; overflow: hidden; border:1px solid var(--line); margin-top:16px; }
th, td { padding:10px 12px; border-bottom:1px solid var(--line); }
th { text-align:left; color:var(--muted); font-weight:600; background:#12162a; position: sticky; top: 52px; z-index:1; } /* keeps header visible below nav */
tbody tr:nth-child(even){ background: #171b2e; }
td.num { text-align:right; }
td img { max-height:60px; width:auto; border-radius:8px; display:block; }
a { color: var(--accent); text-decoration: none; }

/* Forms (Add/Edit Stay) */
form { background: var(--card); border:1px solid var(--line); border-radius: 14px; padding:16px; margin-top:16px; }
form p { margin: 10px 0; }
input[type="text"], input[type="date"], input[type="number"], select, textarea {
  width: 100%; max-width: 520px; padding: 10px 12px; border-radius: 10px; border:1px solid var(--line); background:#0f1324; color:var(--ink);
}
input[type="checkbox"] { transform: scale(1.1); margin-right: 8px; }
button, .btn {
  display:inline-block; padding:10px 14px; border-radius:10px; border:1px solid #2b3355; background:#1a2040; color:#e8ebff; cursor:pointer;
}
button:hover, .btn:hover { background:#222858; }
.actions { margin-top:12px; display:flex; gap:10px; }
'@

if (-not (Test-Path $cssPath)) {
  BackupWrite $cssPath $baseCss
  Write-Host "Created static/css/style.css" -ForegroundColor Green
} else {
  $existing = Get-Content $cssPath -Raw
  if ($existing -notmatch 'Forms \(Add/Edit Stay\)') {
    SafeSetContent $cssPath ($existing.TrimEnd() + "`r`n`r`n" + $baseCss)
    Write-Host "Appended forms/table styles to static/css/style.css" -ForegroundColor Green
  } else {
    Write-Host "static/css/style.css already contains required styles" -ForegroundColor DarkGray
  }
}

# ---------- 2) Ensure base.html loads the stylesheet + has nav include + block ----------
$basePath = ".\templates\base.html"
if (-not (Test-Path $basePath)) {
  $minimalBase = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Traveler</title>
  {% load static %}
  <link rel="stylesheet" href="{% static 'css/style.css' %}">
  <style>.bt-nav ~ header, .bt-nav ~ nav { display:none !important; }</style>
</head>
<body>
  {% include 'partials/top_nav.html' %}
  {% block content %}{% endblock %}
</body>
</html>
'@
  BackupWrite $basePath $minimalBase
  Write-Host "Created minimal templates/base.html" -ForegroundColor Yellow
} else {
  $b = Get-Content $basePath -Raw

  # Ensure {% load static %} in <head>
  if ($b -notmatch '{%\s*load\s+static\s*%}') {
    $b = [regex]::Replace($b, '(?is)(<head[^>]*>)', "`$1`r`n{% load static %}", 1)
  }
  # Ensure link to static/css/style.css
  if ($b -notmatch 'href="\{\%\s*static\s*''css/style\.css''\s*\%\}"') {
    $b = [regex]::Replace($b, '(?is)</head>', '  <link rel="stylesheet" href="{% static ''css/style.css'' %}">' + "`r`n</head>", 1)
  }
  # Small guard to hide any stray legacy header/nav after the sticky bar
  if ($b -notmatch '\.bt-nav\s*~\s*(header|nav)') {
    $b = [regex]::Replace($b, '(?is)</head>', "<style>.bt-nav ~ header, .bt-nav ~ nav { display:none !important; }</style>`r`n</head>", 1)
  }
  # Ensure top nav include immediately after <body>
  if ($b -match '(?is)<body[^>]*>') {
    if ($b -notmatch "partials/top_nav\.html") {
      $b = [regex]::Replace($b, '(?is)(<body[^>]*>)', "`$1`r`n{% include 'partials/top_nav.html' %}`r`n", 1)
    } else {
      # normalize position (move to top of body)
      $b = [regex]::Replace($b, '(?is)(<body[^>]*>)(.*?){%\s*include\s*["'']partials/top_nav\.html["'']\s*%}\s*', "`$1`r`n{% include 'partials/top_nav.html' %}`r`n", 1)
    }
  }
  # Ensure {% block content %}{% endblock %} exists
  if ($b -notmatch '{%\s*block\s+content\s*%}') {
    $b = [regex]::Replace($b, '(?is)(</body>)', "{% block content %}{% endblock %}`r`n`$1", 1)
  }

  SafeSetContent $basePath $b
  Write-Host "Patched templates/base.html (static/css + nav include + content block)" -ForegroundColor Green
}

# ---------- 3) Rewrite stays/stay_form.html to extend base ----------
$stayFormPath = ".\templates\stays\stay_form.html"
$stayFormTpl = @'
{% extends "base.html" %}

{% block content %}
<div class="wrap">
  <h1>{% if form.instance.pk %}Edit Stay{% else %}Add Stay{% endif %}</h1>
  <form method="post" enctype="multipart/form-data">
    {% csrf_token %}
    {{ form.as_p }}
    <div class="actions">
      <button type="submit">Save</button>
      <a class="btn" href="/stays/">Cancel</a>
    </div>
  </form>
</div>
{% endblock %}
'@

if (Test-Path $stayFormPath) {
  SafeSetContent $stayFormPath $stayFormTpl
  Write-Host "Rewrote templates/stays/stay_form.html to extend base.html" -ForegroundColor Green
} else {
  BackupWrite $stayFormPath $stayFormTpl
  Write-Host "Created templates/stays/stay_form.html extending base.html" -ForegroundColor Green
}

Write-Host "`nDone. Hard-refresh the site (Ctrl+F5). If styles don't load, run: python manage.py collectstatic (in production)." -ForegroundColor Cyan

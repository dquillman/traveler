# fix_stays_banner.ps1
# Makes /stays/ inherit the global sticky banner by:
# - Ensuring base.html includes the banner and exposes {% block content %}
# - Writing partials/top_nav.html
# - Rewriting stays/stay_list.html to extend base.html
# All touched files get a timestamped .bak copy.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Get-Location).Path
$tpl  = Join-Path $root 'templates'
if (-not (Test-Path $tpl)) { Write-Host "Templates folder not found at $tpl" -ForegroundColor Red; exit 1 }
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

function BackupWrite($path, $content) {
  if (Test-Path $path) { Copy-Item $path "$path.bak.$ts" -Force }
  $dir = Split-Path $path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  Set-Content -Path $path -Value $content -Encoding UTF8
}

# 1) Write/refresh the shared sticky banner partial
$partialDir = Join-Path $tpl 'partials'
$topNav = Join-Path $partialDir 'top_nav.html'
$topNavHtml = @'
<style>
  .bt-nav { position: sticky; top: 0; z-index: 9999; background: #0f1220; border-bottom: 1px solid #272b41; padding: 10px 14px; }
  .bt-nav .wrap { max-width: 1200px; margin: 0 auto; display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
  .bt-nav a { color: #e8ebff; text-decoration: none; padding: 8px 10px; border-radius: 10px; border: 1px solid transparent; }
  .bt-nav a:hover { background: rgba(185,198,255,.08); border-color: #2b3355; }
  .bt-nav a.active { background: rgba(185,198,255,.15); border-color: #b9c6ff; }
  .bt-nav .spacer { flex: 1; }
  .bt-brand { font-weight: 700; letter-spacing: .3px; margin-right: 6px; }
</style>

<div class="bt-nav">
  <div class="wrap">
    <span class="bt-brand"><a href="/stays/" class="{% if request.path|slice:0:7 == '/stays/' %}active{% endif %}">Traveler</a></span>

    <a href="/stays/" class="{% if request.path == '/stays/' %}active{% endif %}">Stays</a>
    <a href="/stays/map/" class="{% if request.path == '/stays/map/' %}active{% endif %}">Map</a>
    <a href="/stays/charts/" class="{% if request.path == '/stays/charts/' %}active{% endif %}">Charts</a>
    <a href="/stays/export/" class="{% if request.path == '/stays/export/' %}active{% endif %}">Export</a>
    <a href="/stays/import/" class="{% if request.path == '/stays/import/' %}active{% endif %}">Import</a>
    <a href="/stays/appearance/" class="{% if request.path == '/stays/appearance/' %}active{% endif %}">Appearance</a>

    <span class="spacer"></span>
  </div>
</div>
'@
BackupWrite $topNav $topNavHtml
Write-Host "OK: templates/partials/top_nav.html" -ForegroundColor Green

# 2) Ensure base.html includes banner right after <body> and has {% block content %}
$base = Join-Path $tpl 'base.html'
if (-not (Test-Path $base)) {
  # Create a minimal base if missing
  $baseHtml = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Traveler</title>
  <style>.bt-nav ~ header, .bt-nav ~ nav { display:none !important; }</style>
</head>
<body>
  {% include 'partials/top_nav.html' %}
  {% block content %}{% endblock %}
</body>
</html>
'@
  BackupWrite $base $baseHtml
  Write-Host "Created minimal templates/base.html" -ForegroundColor Yellow
} else {
  $b = Get-Content $base -Raw

  # Remove any legacy <header>…</header> in base
  $b = [regex]::Replace($b, '(?is)<header\b.*?</header>\s*', '')
  # Remove any inline .bt-nav duplicates in base
  $b = [regex]::Replace($b, '(?is)<div\s+class=["''][^"'']*\bbt-nav\b[^"'']*["''][^>]*>.*?</div>\s*', '')

  # Add CSS guard (once)
  if ($b -notmatch '\.bt-nav\s*~\s*(header|nav)') {
    $b = [regex]::Replace($b, '(?is)</head>', "<style>.bt-nav ~ header, .bt-nav ~ nav { display:none !important; }</style>`r`n</head>", 1)
  }

  # Ensure include sits immediately after <body>
  if ($b -match '(?is)<body[^>]*>') {
    if ($b -notmatch "partials/top_nav\.html") {
      $b = [regex]::Replace($b, '(?is)(<body[^>]*>)', "`$1`r`n{% include 'partials/top_nav.html' %}`r`n", 1)
    } else {
      # Normalize position: move include to top of body
      $b = [regex]::Replace($b, '(?is)(<body[^>]*>)(.*?){%\s*include\s*["'']partials/top_nav\.html["'']\s*%}\s*', "`$1`r`n{% include 'partials/top_nav.html' %}`r`n", 1)
    }
  }

  # Ensure {% block content %} exists (basic heuristic)
  if ($b -notmatch '{%\s*block\s+content\s*%}') {
    $b = [regex]::Replace($b, '(?is)(</body>)', "{% block content %}{% endblock %}`r`n`$1", 1)
  }

  BackupWrite $base $b
  Write-Host "OK: patched templates/base.html" -ForegroundColor Green
}

# 3) Rewrite stays/stay_list.html to extend base.html (no full <html>…)
$staysTpl = Join-Path $tpl 'stays\stay_list.html'
$staysBlock = @'
{% extends "base.html" %}

{% block content %}
<div class="wrap">
  <h1>Stays</h1>
  <table>
    <thead>
      <tr>
        <th>Park</th>
        <th>City</th>
        <th>State</th>
        <th>Rating</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      {% for stay in stays %}
      <tr>
        <td>{{ stay.park }}</td>
        <td>{{ stay.city }}</td>
        <td>{{ stay.state }}</td>
        <td>{{ stay.rating|default:"None" }}</td>
        <td>
          <a href="{% url 'stay_detail' stay.id %}">View</a> |
          <a href="{% url 'stay_edit' stay.id %}">Edit</a>
        </td>
      </tr>
      {% empty %}
      <tr><td colspan="5">No stays yet.</td></tr>
      {% endfor %}
    </tbody>
  </table>
</div>
{% endblock %}
'@
BackupWrite $staysTpl $staysBlock
Write-Host "OK: rewrote templates/stays/stay_list.html to extend base.html" -ForegroundColor Green

Write-Host "`nDone. Restart Django and hard-refresh /stays/ (Ctrl+F5)." -ForegroundColor Cyan

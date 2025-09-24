# add_sitewide_nav.ps1
$ErrorActionPreference = "Stop"

function Backup($p){ if (Test-Path $p) { Copy-Item $p "$p.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force } }

# Ensure templates/partials dir
$partialsDir = "templates\partials"
if (!(Test-Path $partialsDir)) { New-Item -ItemType Directory -Force -Path $partialsDir | Out-Null }

# 1) Create/overwrite nav partial (inline styles, active link highlight)
$navPath = Join-Path $partialsDir "nav.html"
Backup $navPath
@'
{# Site-wide top nav. Inline styles so it works immediately without static files. #}
{# Requires "django.template.context_processors.request" enabled (usually default). #}
<style>
  .bt-nav { position: sticky; top: 0; z-index: 9999; background: #0f1220; border-bottom: 1px solid #272b41; padding: 10px 14px; }
  .bt-nav .wrap { max-width: 1200px; margin: 0 auto; display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
  .bt-nav a { color: #e8ebff; text-decoration: none; padding: 8px 10px; border-radius: 10px; border: 1px solid transparent; }
  .bt-nav a:hover { background: rgba(185,198,255,.08); border-color: #2b3355; }
  .bt-nav a.active { background: rgba(185,198,255,.15); border-color: #b9c6ff; }
  .bt-nav .spacer { flex: 1; }
  .bt-brand { font-weight: 700; letter-spacing: .3px; margin-right: 6px; }
</style>
{% with name=request.resolver_match.url_name %}
<div class="bt-nav">
  <div class="wrap">
    <span class="bt-brand"><a href="{% url 'stays:list' %}" class="{% if name == 'list' %}active{% endif %}">Traveler</a></span>

    <a href="{% url 'stays:list' %}" class="{% if name == 'list' %}active{% endif %}">Stays</a>
    <a href="{% url 'stays:stays_map' %}" class="{% if name == 'stays_map' %}active{% endif %}">Map</a>
    <a href="{% url 'stays:stays_charts' %}" class="{% if name == 'stays_charts' %}active{% endif %}">Charts</a>
    <a href="{% url 'stays:stays_export' %}" class="{% if name == 'stays_export' %}active{% endif %}">Export</a>
    <a href="{% url 'stays:stays_import' %}" class="{% if name == 'stays_import' %}active{% endif %}">Import</a>
    <a href="{% url 'stays:stays_appearance' %}" class="{% if name == 'stays_appearance' %}active{% endif %}">Appearance</a>

    <span class="spacer"></span>
    {# room for login/profile later #}
  </div>
</div>
{% endwith %}
'@ | Set-Content -Path $navPath -Encoding UTF8

Write-Host "✅ Created templates/partials/nav.html"

# 2) Helper: insert the nav include after <body> if present; else at top
function Insert-Nav($filePath) {
  if (!(Test-Path $filePath)) { return }
  $t = Get-Content $filePath -Raw
  if ($t -match "{%\s*include\s+['""]partials/nav\.html['""]\s*%}") { return } # already has nav
  Backup $filePath
  $include = "{% include 'partials/nav.html' %}"
  # If file has <body>, inject right after it; else prepend
  if ($t -match "(?i)<body[^>]*>") {
    $t = $t -replace "(?i)(<body[^>]*>)", "`$1`r`n$include`r`n"
  } else {
    $t = $include + "`r`n" + $t
  }
  Set-Content -Path $filePath -Value $t -Encoding UTF8
  Write-Host "• Injected nav into $filePath"
}

# 3) Inject nav into known pages
$targets = @(
  "templates\stays\map.html",
  "templates\stays\charts.html",
  "templates\stays\export.html",
  "templates\stays\import.html",
  "templates\stays\appearance.html",
  # try common filenames for the main list page:
  "templates\stays\stay_list.html",
  "templates\stays\list.html",
  "templates\stays\index.html"
)

foreach ($f in $targets) { Insert-Nav $f }

# 4) Ensure settings include the request context processor so nav can see request
$settings = "config\settings.py"
if (Test-Path $settings) {
  $s = Get-Content $settings -Raw
  if ($s -match "TEMPLATES") {
    if ($s -notmatch "django\.template\.context_processors\.request") {
      Backup $settings
      $s = $s -replace "(?s)('OPTIONS'\s*:\s*\{\s*'context_processors'\s*:\s*\[)",
                       "`$1`r`n            'django.template.context_processors.request',"
      Set-Content -Path $settings -Value $s -Encoding UTF8
      Write-Host "✅ Added request context processor to config/settings.py"
    }
  }
}

Write-Host "`nAll set. Restart the server to see the banner on every page."

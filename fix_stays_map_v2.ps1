param(
  [string]$Root = $PSScriptRoot
)

# fix_stays_map_v2.ps1
# ----------------------------------------------------------------------
# Purpose:
# - Patch templates\stays\stay_list.html to use a single, valid reverse:
#       var mapDataUrl = "{% url 'stays:stays_map_data' %}";
# - Normalize any non-namespaced {% url 'stays_map_data' %} and {{ map_url }}
# - Ensure stays\urls.py has:
#       app_name = "stays"
#       path("map-data/", views.stays_map_data, name="stays_map_data")
# - Back up changed files with .bak alongside originals.
# ----------------------------------------------------------------------

$ErrorActionPreference = "Stop"

function Backup-And-Write([string]$Path, [string]$Content) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "File not found: $Path"
  }
  $orig = Get-Content -Raw -LiteralPath $Path
  if ($orig -ne $Content) {
    $bak = "$Path.bak"
    Set-Content -NoNewline -LiteralPath $bak -Value $orig
    Set-Content -NoNewline -LiteralPath $Path -Value $Content
    Write-Host "Patched: $Path  (backup at $bak)"
  } else {
    Write-Host "No changes needed: $Path"
  }
}

# ---------- 1) Patch the map script in stay_list.html ----------
$templatePath = Join-Path $Root "templates\stays\stay_list.html"
if (Test-Path -LiteralPath $templatePath) {
  $tpl = Get-Content -Raw -LiteralPath $templatePath

  # Replace the namespace-agnostic IIFE block with a single assignment
  $patternIife = @"
var\s+mapDataUrl\s*=\s*\(function\(\)\s*\)\s*\{\s*.*?\s*\}\s*\(\s*\)\s*;
"@
  $regexIife = New-Object System.Text.RegularExpressions.Regex($patternIife, [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $tpl = $regexIife.Replace($tpl, 'var mapDataUrl = "{% url ''stays:stays_map_data'' %}";')

  # Normalize any remaining non-namespaced url tags and {{ map_url }}
  $tpl = $tpl -replace "\{\%\s*url\s+'stays_map_data'\s*\%\}", "{% url 'stays:stays_map_data' %}"
  $tpl = $tpl -replace '\{\%\s*url\s+"stays_map_data"\s*\%\}', "{% url 'stays:stays_map_data' %}"
  $tpl = $tpl -replace "\{\{\s*map_url\s*\}\}", "{% url 'stays:stays_map_data' %}"

  Backup-And-Write -Path $templatePath -Content $tpl
} else {
  Write-Warning "Template not found: $templatePath (skipping template patch)"
}

# ---------- 2) Ensure stays/urls.py has correct entries ----------
$urlsPath = Join-Path $Root "stays\urls.py"
if (Test-Path -LiteralPath $urlsPath) {
  $urls = Get-Content -Raw -LiteralPath $urlsPath

  # Ensure imports
  if ($urls -notmatch 'from\s+django\.urls\s+import\s+path') {
    $urls = "from django.urls import path`r`n" + $urls
  }
  if ($urls -notmatch 'from\s+\.\s+import\s+views') {
    $urls = $urls -replace '(from\s+django\.urls\s+import\s+path\s*)', "`$1`r`nfrom . import views`r`n"
    if ($urls -notmatch 'from\s+\.\s+import\s+views') {
      $urls = $urls + "`r`nfrom . import views`r`n"
    }
  }

  # Ensure app_name = "stays"
  if ($urls -match 'app_name\s*=\s*["''][^"'']+["'']') {
    $urls = [regex]::Replace($urls, 'app_name\s*=\s*["''][^"'']+["'']', 'app_name = "stays"')
  } elseif ($urls -match 'urlpatterns\s*=\s*\[') {
    $urls = $urls -replace 'urlpatterns\s*=\s*\[', "app_name = `"stays`"`r`n`r`nurlpatterns = ["
  } else {
    $urls = $urls + "`r`napp_name = `"stays`"`r`n"
  }

  # Ensure urlpatterns exists
  if ($urls -notmatch 'urlpatterns\s*=\s*\[') {
    $urls += @"

urlpatterns = [
]
"@
  }

  # Ensure the map-data route is present exactly once
  if ($urls -notmatch 'name\s*=\s*["'']stays_map_data["'']') {
    $urls = [regex]::Replace(
      $urls,
      'urlpatterns\s*=\s*\[(.*?)\]',
      {
        param($m)
        $inside = $m.Groups[1].Value.Trim()
        $line = '    path("map-data/", views.stays_map_data, name="stays_map_data"),'
        if ($inside -ne '') {
          "urlpatterns = [" + "`r`n" + $inside + "`r`n" + $line + "`r`n]"
        } else {
          "urlpatterns = [" + "`r`n" + $line + "`r`n]"
        }
      },
      'Singleline'
    )
  }

  Backup-And-Write -Path $urlsPath -Content $urls
} else {
  Write-Warning "URLs file not found: $urlsPath (skipping urls.py patch)"
}

Write-Host ""
Write-Host "Next steps:"
Write-Host '  python manage.py shell -c "from django.urls import reverse; print(reverse(''stays:stays_map_data''))"'
Write-Host "  # Expect: /stays/map-data/"
Write-Host "  python manage.py runserver"

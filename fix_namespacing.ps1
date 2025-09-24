# fix_namespacing.ps1
# Usage (run from your repo root):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\fix_namespacing.ps1
# Notes:
# - Adds the 'stays:' namespace to {% url %} tags for stays_map_data
# - Also replaces any {{ map_url }} usage with the inlined namespaced URL
# - Creates a .bak alongside each modified file before writing changes

$ErrorActionPreference = "Stop"

# Detect repo root as the directory that contains this script by default
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# Allow overriding search folder with -Path argument if desired
param(
  [string]$Path = $root
)

Write-Host "Scanning *.html under: $Path"

$templates = Get-ChildItem -Recurse -Include *.html -Path $Path

$patternUrl = @'
\{\%\s*url\s*''stays_map_data''(\s+as\s+map_url)?\s*\%\}
'@

$replUrl = '{% url ''stays:stays_map_data''$1 %}'

$patternMapVar = @'
\{\{\s*map_url\s*\}\}
'@

$replMapVar = '{% url ''stays:stays_map_data'' %}'

[int]$changed = 0
foreach ($f in $templates) {
  $orig = Get-Content -Raw -LiteralPath $f.FullName
  $new  = $orig

  $new = [regex]::Replace($new, $patternUrl, $replUrl, 'IgnoreCase, Multiline')
  $new = [regex]::Replace($new, $patternMapVar, $replMapVar, 'IgnoreCase, Multiline')

  if ($new -ne $orig) {
    # Backup
    $bak = "$($f.FullName).bak"
    Set-Content -NoNewline -LiteralPath $bak -Value $orig

    # Write
    Set-Content -NoNewline -LiteralPath $f.FullName -Value $new
    Write-Host ("Patched: {0}" -f $f.FullName)
    $changed++
  }
}

Write-Host ("Done. Files changed: {0}" -f $changed)
Write-Host 'Sanity check (optional):'
Write-Host '  python manage.py shell -c "from django.urls import reverse; print(reverse(''stays:stays_map_data''))"'
Write-Host 'Restart server:  python manage.py runserver'

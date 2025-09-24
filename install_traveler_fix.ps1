param(
  [string]$Repo = "G:\users\daveq\traveler"
)

$ErrorActionPreference = "Stop"

function Backup-And-Write([string]$Path, [string]$Content){
  if (Test-Path -LiteralPath $Path) {
    $orig = Get-Content -Raw -LiteralPath $Path
    if ($orig -ne $Content) {
      $bak = "$Path.bak"
      Set-Content -NoNewline -LiteralPath $bak -Value $orig
      Set-Content -NoNewline -LiteralPath $Path -Value $Content
      Write-Host "Patched: $Path  (backup at $bak)"
    } else {
      Write-Host "No changes needed: $Path"
    }
  } else {
    # ensure folder exists
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -NoNewline -LiteralPath $Path -Value $Content
    Write-Host "Created: $Path"
  }
}

# Load the packaged files (sibling to this installer)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tplContent = Get-Content -Raw -LiteralPath (Join-Path $here "templates_stays_stay_list.html")
$viewContent = Get-Content -Raw -LiteralPath (Join-Path $here "stays_views_stays_map_data.py")

# Targets inside the repo
$tplTarget = Join-Path $Repo "templates\stays\stay_list.html"
$viewsTarget = Join-Path $Repo "stays\views.py"

# 1) Patch template
Backup-And-Write -Path $tplTarget -Content $tplContent

# 2) Patch the view function surgically (replace stays_map_data inside views.py)
if (Test-Path -LiteralPath $viewsTarget) {
  $views = Get-Content -Raw -LiteralPath $viewsTarget

  # Remove existing stays_map_data definition (heuristic: def stays_map_data ... until next def or EOF)
  $pattern = [regex]@"
(?s)def\s+stays_map_data\s*\([^)]*\)\s*:[\s\S]*?(?=^\s*def\s+|\Z)
"@
  $viewsNew = $pattern.Replace($views, "")

  # Append the good implementation at the end
  $viewsNew = $viewsNew.TrimEnd() + "`r`n`r`n" + $viewContent + "`r`n"

  Backup-And-Write -Path $viewsTarget -Content $viewsNew
} else {
  # If views.py doesn't exist, create one with just the function
  Backup-And-Write -Path $viewsTarget -Content $viewContent
}

Write-Host ""
Write-Host "Done. Sanity checks:"
Write-Host '  python manage.py shell -c "from django.urls import reverse; print(reverse(''stays:stays_map_data''))"'
Write-Host "  # Expect: /stays/map-data/"
Write-Host "  python manage.py runserver"

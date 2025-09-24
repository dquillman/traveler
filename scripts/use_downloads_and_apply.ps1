param(
  [string]$ZipName = "traveler_full_fix_bundle.zip",
  [string]$DownloadsRoot = "E:\Downloads",
  [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
$zipPath = Join-Path $DownloadsRoot $ZipName

if (-not (Test-Path $zipPath)) {
  Write-Host "Zip not found at: $zipPath" -ForegroundColor Red
  Write-Host "Tip: Put the file in E:\Downloads or pass -DownloadsRoot <path> or -ZipName <file.zip>" -ForegroundColor Yellow
  exit 1
}

Write-Host "Expanding: $zipPath -> $RepoRoot" -ForegroundColor Cyan
Expand-Archive -Path $zipPath -DestinationPath $RepoRoot -Force

$apply = Join-Path $RepoRoot "scripts\apply_full_fix.ps1"
if (-not (Test-Path $apply)) {
  Write-Host "Cannot find $apply after extraction." -ForegroundColor Red
  exit 1
}

Write-Host "Running patch script..." -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File $apply -RepoRoot $RepoRoot

Write-Host "Done. Now run migrations and start the server:" -ForegroundColor Green
Write-Host '  python manage.py makemigrations stays'
Write-Host '  python manage.py migrate'
Write-Host '  python manage.py runserver'

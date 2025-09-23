param(
  [Parameter(Mandatory=$true)][string]$Tag,
  [string]$NewBranch = ""
)
$ErrorActionPreference = "Stop"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "git not found" -ForegroundColor Red; exit 1 }
if (-not (Test-Path ".git")) { Write-Host "Not a git repo" -ForegroundColor Red; exit 1 }

Write-Host "Fetching tags from origin..." -ForegroundColor Cyan
git fetch --tags | Out-Null

if (-not $NewBranch) { $NewBranch = "restore-$Tag" }
Write-Host "Checking out tag '$Tag' into new branch '$NewBranch'..." -ForegroundColor Cyan
git checkout -b $NewBranch $Tag

Write-Host "Done. You're now on branch '$NewBranch' at snapshot '$Tag'." -ForegroundColor Green

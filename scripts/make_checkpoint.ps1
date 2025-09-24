param(
  [string]$TagPrefix = "checkpoint",
  [string]$CommitMessage = "",
  [switch]$NoPush,
  [switch]$NoZip,
  [string]$BackupDir = "",
  [string]$RepoRoot = "."
)
$ErrorActionPreference = "Stop"

function Write-Info($msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-Good($msg){ Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg){ Write-Host $msg -ForegroundColor Yellow }
function Write-Bad($msg){  Write-Host $msg -ForegroundColor Red }

Set-Location $RepoRoot

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Bad "git not found on PATH"; exit 1 }
if (-not (Test-Path ".git")) { Write-Bad "Not a git repo (no .git here)"; exit 1 }

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -eq "HEAD") { $branch = "detached" }
$TagName = "$TagPrefix-$ts"

Write-Info "Staging all changes..."
git add -A | Out-Null
$pending = (git status --porcelain)
if ($pending) {
  if (-not $CommitMessage) { $CommitMessage = "checkpoint: $ts" }
  Write-Info "Creating commit on '$branch'..."
  git commit -m $CommitMessage | Out-Null
} else {
  Write-Warn "No changes to commit; tagging current commit."
}

Write-Info "Creating tag '$TagName'..."
git tag $TagName

if (-not $NoPush) {
  Write-Info "Pushing branch '$branch' (best effort) and tags to origin..."
  try { git push origin $branch | Out-Null } catch { Write-Warn "Could not push branch '$branch' (continuing)" }
  git push origin --tags | Out-Null
} else {
  Write-Warn "Skipping push (--NoPush)."
}

if (-not $NoZip) {
  if (-not $BackupDir) {
    $dl1 = Join-Path $env:USERPROFILE "Downloads"
    $dl2 = "E:\Downloads"
    if (Test-Path $dl2) { $BackupDir = $dl2 }
    elseif (Test-Path $dl1) { $BackupDir = $dl1 }
    else { $BackupDir = (Get-Location).Path }
  }
  if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }

  $zipName = "traveler_$TagName.zip"
  $zipPath = Join-Path $BackupDir $zipName
  Write-Info "Creating ZIP at $zipPath (excluding .git, .venv, __pycache__, *.pyc)..."

  $tmp = Join-Path $env:TEMP ("traveler_backup_" + $ts)
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null

  $robolog = Join-Path $env:TEMP ("robocopy_" + $ts + ".log")
  & robocopy . $tmp /MIR /NFL /NDL /NJH /NJS /XD .git .venv node_modules media\cache __pycache__ .mypy_cache .pytest_cache /XF *.pyc *.pyo *.log *.tmp /R:1 /W:1 /LOG:$robolog | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Warn "Robocopy code $LASTEXITCODE (see $robolog). Proceeding to zip anyway." }

  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zipPath -CompressionLevel Optimal
  Remove-Item -Recurse -Force $tmp
  Write-Good "ZIP saved: $zipPath"
} else {
  Write-Warn "Skipping ZIP (--NoZip)."
}

Write-Good "Checkpoint complete."
Write-Host ("Tag: " + $TagName)
Write-Host ("Branch: " + $branch)

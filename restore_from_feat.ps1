<# restore_from_feat.ps1
   Use a good feat/* branch to restore main safely via PR.
#>

param(
  [Parameter(Mandatory=$true)][string]$RepoPath,
  [Parameter(Mandatory=$true)][string]$FeatureBranch,
  [string]$BaseBranch = "main",
  [switch]$NoBackup,
  [switch]$RebaseInsteadOfMerge
)

$ErrorActionPreference = "Stop"

function Run($cmd) {
  Write-Host ("> " + $cmd)
  & cmd /c $cmd
  if ($LASTEXITCODE -ne 0) { throw "Command failed: $cmd" }
}

if (-not (Test-Path $RepoPath)) {
  Write-Host "ERROR: RepoPath not found: $RepoPath"
  exit 1
}
Set-Location $RepoPath

# 0) Optional backup
if (-not $NoBackup) {
  $ts = Get-Date -Format "yyyyMMdd_HHmmss"
  $zip = Join-Path (Split-Path $RepoPath -Parent) ("traveler_backup_" + $ts + ".zip")
  Write-Host ("Backing up to " + $zip + " ...")
  Compress-Archive -Path (Join-Path $RepoPath "*") -DestinationPath $zip -Force
  Write-Host "Backup complete."
}

# 1) Verify git repo & fetch
Run "git rev-parse --is-inside-work-tree"
Write-Host "Fetching origin..."
Run "git fetch origin --prune"

# 2) Check out local feature branch (create if missing)
$featureExists = $true
try { Run "git rev-parse --verify $FeatureBranch >NUL 2>&1" } catch { $featureExists = $false }
if (-not $featureExists) {
  Write-Host "Creating local branch tracking origin/$FeatureBranch"
  Run "git switch -c $FeatureBranch origin/$FeatureBranch"
} else {
  Run "git switch $FeatureBranch"
  try { Run "git pull --ff-only" } catch { Write-Host "No upstream set yet (continuing)." }
}

# 3) Update feature with latest main
if ($RebaseInsteadOfMerge) {
  Write-Host "Rebasing feature onto origin/$BaseBranch ..."
  Run "git rebase origin/$BaseBranch"
} else {
  Write-Host "Merging origin/$BaseBranch into feature ..."
  Run "git merge --no-edit origin/$BaseBranch"
}

# 4) Push feature to origin (set upstream if needed)
Write-Host "Pushing feature branch ..."
try {
  Run "git push -u origin $FeatureBranch"
} catch {
  Write-Host "Non-fast-forward or no upstream. Trying rebase against origin/$FeatureBranch ..."
  try {
    Run "git fetch origin $FeatureBranch"
    Run "git rebase origin/$FeatureBranch"
    Run "git push -u origin $FeatureBranch"
  } catch {
    Write-Host "If this still fails and your local should win, run:"
    Write-Host ("  git push --force-with-lease origin " + $FeatureBranch)
    throw
  }
}

# 5) Ensure local base is current
$baseExists = $true
try { Run "git rev-parse --verify $BaseBranch >NUL 2>&1" } catch { $baseExists = $false }
if (-not $baseExists) {
  Run "git switch -c $BaseBranch origin/$BaseBranch"
} else {
  Run "git switch $BaseBranch"
  Run "git pull --ff-only"
}

# 6) Create PR (if gh exists) or print compare URL
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
  Write-Host "Creating Pull Request (feature -> base) ..."
  Run "git switch $FeatureBranch"
  $title = "Restore: Use " + $FeatureBranch + " (good state) to update " + $BaseBranch
  $body  = "Bring " + $BaseBranch + " back to known-good state from " + $FeatureBranch + "`nUpdated feature with latest " + $BaseBranch + " first."
  $tmp = New-TemporaryFile
  Set-Content -Path $tmp -Value $body -Encoding UTF8
  Run ("gh pr create --base " + $BaseBranch + " --head " + $FeatureBranch + " --title """ + $title + """ --body-file """ + $tmp + """")
  Remove-Item $tmp -Force
  Write-Host "Pull Request created. Review and Merge in GitHub."
} else {
  $remoteUrl = (& git remote get-url origin).Trim()
  if ($remoteUrl -match "git@github.com:(.+)\.git") {
    $slug = $Matches[1]
    $web = "https://github.com/" + $slug + "/compare/" + $BaseBranch + "..." + $FeatureBranch
  } elseif ($remoteUrl -match "https://github.com/(.+)\.git") {
    $slug = $Matches[1]
    $web = "https://github.com/" + $slug + "/compare/" + $BaseBranch + "..." + $FeatureBranch
  } else {
    $web = $remoteUrl
  }
  Write-Host "Open this URL to create the PR:"
  Write-Host $web
}

Write-Host ""
Write-Host "NEXT:"
Write-Host "  1) Open the PR, click 'Update branch' if shown, resolve conflicts if any, then Merge."
Write-Host "  2) After merge: git switch " $BaseBranch " ; git pull"
Write-Host "Done."

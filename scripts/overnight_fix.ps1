# ================= Been There: Overnight Fix (Unattended + Git Push) =================
# Run from your Django project root (same folder as manage.py)
# Usage (with venv active):  .\scripts\overnight_fix.ps1
$ErrorActionPreference = "Stop"

function Write-Step($msg){ Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Append-Report($text){ Add-Content -Path $Global:ReportPath -Value $text }

# -------------------- CONFIG (edit if you want) --------------------
$RemoteName = "origin"                             # your git remote name
$CreateBranch = $true                              # create and push a new branch for the report
$BranchPrefix = "auto/overnight-fix"               # branch name prefix
$AlsoOpenGithubIssue = $true                       # requires GitHub CLI `gh` logged in
$GithubIssueTitle = "Overnight Fix Report (Automated)"
# ------------------------------------------------------------------

# 0) Sanity checks
if (-not (Test-Path ".\manage.py")) { throw "Run this from the Django project root (where manage.py is)." }

# 0.1) Git repo checks
Write-Step "Checking Git repository"
$repoRoot = ""
try {
  $repoRoot = (git rev-parse --show-toplevel).Trim()
} catch {
  Write-Host "This folder is not a Git repository. Skipping push." -ForegroundColor Yellow
}
$IsGitRepo = $repoRoot -ne "" -and (Test-Path $repoRoot)

# 1) Prepare reports folder and report file
Write-Step "Preparing report file"
$reports = Join-Path (Get-Location) "reports"
if (-not (Test-Path $reports)) { New-Item -ItemType Directory -Path $reports | Out-Null }
$Global:ReportPath = Join-Path $reports ("overnight_report_{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
Append-Report "Been There â€" Overnight Fix Report"
Append-Report ("Timestamp: {0}" -f (Get-Date))
Append-Report "================================================================"

# Helper: run a command and tee output to report
function Run-And-Log($label, $scriptBlock){
  Write-Step $label
  try {
    & $scriptBlock 2>&1 | Tee-Object -FilePath $Global:ReportPath -Append
  } catch {
    Append-Report ("[ERROR] " + $label + ": " + $_.Exception.Message)
  }
}

# 2) Verify basic deps
Run-And-Log "Verifying/installing core dependencies" {
  pip show Django | Out-Null
# Ensure Django is available in the venv (PowerShell-safe)
\ = Join-Path \G:\users\daveq\traveler\.venv 'Scripts\pip.exe'
if (-not (Test-Path \)) { \ = '.\.venv\Scripts\pip.exe' }

if (\1 -ne 0 -or -not (Get-Command django-admin -ErrorAction SilentlyContinue)) {
  if (Test-Path \) {
    & \ install 'Django>=4.2,<6.0' | Out-Null
  } else {
    Write-Host "pip not found in venv; trying python -m pip..." -ForegroundColor Yellow
    & python -m pip install 'Django>=4.2,<6.0' | Out-Null
  }
}
  pip show pillow | Out-Null
  if ($LASTEXITCODE -ne 0) { pip install pillow | Out-Null }
}

# 3) Placeholder patch (idempotent)
Run-And-Log "Applying placeholder patch" {
  $patch = ".\patch-placeholder.ps1"
  if (-not (Test-Path $patch)) {
    Copy-Item ".\scripts\patch-placeholder.ps1" $patch -Force
  }
  powershell -ExecutionPolicy Bypass -File $patch
}

# 4) Django checks
Run-And-Log "Running Django checks" { python manage.py check }

# 5) Static collection
Run-And-Log "Collecting static (dev-safe)" { python manage.py collectstatic --noinput }

# 6) Probe routes with Django test client
Run-And-Log "Probing routes with Django test client" { python .\scripts\probe_site.py }

# 7) Optional: add fallback dark CSS if missing
Run-And-Log "Ensuring optional dark CSS (only if css/style.css missing)" {
  $staticDir = Join-Path (Get-Location) "static\css"
  $targetCss = Join-Path $staticDir "style.css"
  if (-not (Test-Path $targetCss)) {
    if (-not (Test-Path $staticDir)) { New-Item -ItemType Directory -Path $staticDir | Out-Null }
    Copy-Item ".\scripts\site_dark_theme.css" $targetCss -Force
    Append-Report "Injected fallback dark theme at static\css\style.css"
  } else {
    Append-Report "Existing static\css\style.css detected; no fallback injected."
  }
}

# 8) Push report to repo (and optionally open GitHub issue) so I can see it
if ($IsGitRepo) {
  Run-And-Log "Committing report to Git repository" {
    # Ensure reports/ is within the repo; if running in a subdir, move file into repo root reports/
    $repoReports = Join-Path $repoRoot "reports"
    if (-not (Test-Path $repoReports)) { New-Item -ItemType Directory -Path $repoReports | Out-Null }
    $finalReportPath = Join-Path $repoReports ([System.IO.Path]::GetFileName($Global:ReportPath))
    if ($Global:ReportPath -ne $finalReportPath) {
      Copy-Item $Global:ReportPath $finalReportPath -Force
      $Global:ReportPath = $finalReportPath
    }

    # Create branch if configured
    if ($CreateBranch) {
      $stamp = Get-Date -Format "yyyyMMdd-HHmm"
      $branch = "$BranchPrefix-$stamp"
      git checkout -b $branch
    }

    git add $Global:ReportPath
    git commit -m "chore: add overnight fix report $(Split-Path -Leaf $Global:ReportPath)"

    # Push
    git push -u $RemoteName HEAD

    Append-Report "Report committed and pushed to $RemoteName on branch: $(git rev-parse --abbrev-ref HEAD)"
  }

  if ($AlsoOpenGithubIssue) {
    Run-And-Log "Opening/Updating GitHub issue (requires gh)" {
      $ghVersion = (gh --version 2>$null)
      if ($LASTEXITCODE -eq 0) {
        $issueBody = Get-Content $Global:ReportPath -Raw
        gh issue create --title $GithubIssueTitle --body $issueBody | Tee-Object -FilePath $Global:ReportPath -Append
        Append-Report "Created GitHub issue with report body."
      } else {
        Append-Report "GitHub CLI (gh) not found or not logged in; skipped issue creation."
      }
    }
  }
} else {
Write-Host "(No remote repo detected - report saved locally only.)" -ForegroundColor Yellow
}

Write-Step "Done. Report at: $Global:ReportPath"
Write-Host 'If you pushed to GitHub, share the branch or issue link with me.'
# ===========================================================================





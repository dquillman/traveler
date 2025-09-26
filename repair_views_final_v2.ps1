# repair_views_final_v2.ps1
# Final, safe text edits for stays\views.py (no AddRange / no fancy quoting)

$ErrorActionPreference = "Stop"

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host "Backup: $Path.bak.$stamp"
  }
}

function Get-Indent([string]$s) { return ([regex]::Match($s,'^\s*').Value) }
function IsBlank([string]$s) { return $s -match '^\s*$' }

$views = "stays\views.py"
if (-not (Test-Path $views)) {
  Write-Host "!! $views not found." -ForegroundColor Yellow
  exit 1
}

Write-Host "[1/5] Backup"
Backup-File $views

# Work with lines for structural surgery
$lines = Get-Content $views
$N = $lines.Count

# ---------- A) Ensure closing ')' after `price = float(... or 0` ----------
Write-Host "[2/5] Fix price = float(...) missing ')'" -ForegroundColor Cyan
$didClose = $false
for ($i=0; $i -lt $N; $i++) {
  if ($lines[$i] -match '^\s*price\s*=\s*float\(\s*$') {
    # Found the opening line. Look for 'or 0' and see if a ')' follows soon after.
    $or0Idx = $null
    $alreadyClosed = $false
    for ($j=$i+1; $j -lt $N; $j++) {
      if ($lines[$j] -match '^\s*\)\s*$') { $alreadyClosed = $true; break }
      if ($lines[$j] -match '^\s*or\s+0\s*$') { $or0Idx = $j }
      # Stop scanning if we reach an 'except'—that'd mean we never closed it
      if ($lines[$j] -match '^\s*except\b') { break }
    }
    if (-not $alreadyClosed -and $or0Idx -ne $null) {
      # Insert a ')' one indent level shallower than the 'or 0' line
      $inner = Get-Indent $lines[$or0Idx]
      $base  = if ($inner.Length -ge 4) { $inner.Substring(0, $inner.Length-4) } else { "" }
      $before = @()
      if ($or0Idx -ge 0) { $before = $lines[0..$or0Idx] }
      $after = @()
      if ($or0Idx + 1 -le $N - 1) { $after = $lines[($or0Idx+1)..($N-1)] }
      $lines = @($before + @("$base)") + $after)
      $N = $lines.Count
      $didClose = $true
      Write-Host "  - Inserted missing ')' after 'or 0'"
      break
    }
  }
}
if (-not $didClose) { Write-Host "  = No missing closing ')' found (or already correct)" }

# ---------- B) Rebuild messages.success(...) + return redirect("stay_list") ----------
Write-Host "[3/5] Rebuild success + redirect block" -ForegroundColor Cyan
# Find the LAST messages.success(
$msIdx = $null
for ($i=0; $i -lt $N; $i++) {
  if ($lines[$i] -match '^\s*messages\.success\(') { $msIdx = $i }
}

if ($msIdx -ne $null) {
  $base = Get-Indent $lines[$msIdx]
  $i1   = $base + (' ' * 4)

  # Determine how far to replace: go forward until we hit a return/def/class or end
  $end = $msIdx
  for ($j=$msIdx+1; $j -lt $N; $j++) {
    if ($lines[$j] -match '^\s*def\s+\w+\(' -or $lines[$j] -match '^\s*class\s+\w+\:' ) { break }
    if ($lines[$j] -match '^\s*return\b' ) { $end = $j; break }
    $end = $j
  }

  # Create replacement lines
  $replacement = @(
    "$base" + "messages.success(",
    "$i1"   + "request,",
    "$i1"   + 'f"Import complete. Created {created}, updated {updated}, skipped {skipped}.",',
    "$base" + ")",
    "$base" + 'return redirect("stay_list")'
  )

  $pre  = @()
  if ($msIdx -gt 0) { $pre = $lines[0..($msIdx-1)] }
  $post = @()
  if ($end -lt ($N-1)) { $post = $lines[($end+1)..($N-1)] }
  $lines = @($pre + $replacement + $post)
  $N = $lines.Count
  Write-Host "  - Replaced success+redirect block"
} else {
  Write-Host "  = messages.success(...) not found; skipping"
}

# ---------- C) Remove concatenated junk and wrap the GET 'state' ternary ----------
Write-Host "[4/5] Cleanup extras (appearance render, ternary state wrap)" -ForegroundColor Cyan
for ($i=0; $i -lt $N; $i++) {
  # Replace "return redirect(...) ... return render(...appearance.html)" with a single return redirect
  if ($lines[$i] -match 'return\s+redirect\("stay_list"\).+return\s+render\([^\)]*appearance\.html[^\)]*\)') {
    $indent = Get-Indent $lines[$i]
    $lines[$i] = $indent + 'return redirect("stay_list")'
  }
  # Kill any separate "return render(...appearance.html)" lines
  if ($lines[$i] -match '^\s*return\s+render\([^\)]*appearance\.html[^\)]*\)\s*$') {
    $lines[$i] = ''
  }
}

# Wrap the raw list/ternary at top of file if present (line ~33 in your error)
$raw = [string]::Join("`r`n", $lines)
$raw2 = [regex]::Replace(
  $raw,
  '\[request\.GET\.get\("state"\)\]\s+if\s+request\.GET\.get\("state"\)\s+else\s+\[\]',
  '([request.GET.get("state")] if request.GET.get("state") else [])'
)
if ($raw2 -ne $raw) {
  Write-Host "  - Wrapped GET('state') ternary with parentheses"
}
Set-Content -Path $views -Value $raw2 -NoNewline

# ---------- D) Verify & format ----------
Write-Host "[5/5] Verify & format" -ForegroundColor Cyan
python -m py_compile stays\views.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! Python compile error still present in stays\views.py" -ForegroundColor Red
  # Show helpful context around the last messages.success for quick inspection
  $all = Get-Content stays\views.py
  $idx = 0
  for ($i=0; $i -lt $all.Count; $i++) { if ($all[$i] -match '^\s*messages\.success\(') { $idx = $i } }
  $start = [Math]::Max(0, $idx - 10)
  $end   = [Math]::Min($all.Count-1, $idx + 20)
  for ($i=$start; $i -le $end; $i++) { Write-Host ("{0,4}: {1}" -f $i, $all[$i]) }
  exit 1
}

try { ruff --version | Out-Null; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Done. Try running the server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

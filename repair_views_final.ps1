# repair_views_final.ps1
# Final surgical repairs for stays\views.py

$ErrorActionPreference = "Stop"

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host "Backup: $Path.bak.$stamp"
  }
}

function Get-Indent($s) { return ([regex]::Match($s,'^\s*').Value) }

$views = "stays\views.py"
if (-not (Test-Path $views)) {
  Write-Host "!! $views not found." -ForegroundColor Yellow
  exit 1
}

Write-Host "[1/5] Backup"
Backup-File $views

# Work on lines for structure-sensitive edits
$lines = Get-Content $views
$N = $lines.Count

# [A] Close the missing ')' for price = float( ... or 0
Write-Host "[2/5] Fix price= float(...) closing paren if missing" -ForegroundColor Cyan
$fixedA = $false
for ($i=0; $i -lt $N; $i++) {
  if ($lines[$i] -match '^\s*price\s*=\s*float\(\s*$') {
    # scan forward for 'or 0' and check next meaningful line for ')'
    $start = $i
    $or0Idx = $null
    for ($j=$i+1; $j -lt $N; $j++) {
      if ($lines[$j] -match '^\s*or\s+0\s*$') { $or0Idx = $j; break }
      if ($lines[$j] -match '^\s*\)\s*$') { $or0Idx = $null; break } # already closed
    }
    if ($or0Idx -ne $null) {
      # If next non-blank after or0 is not ')', insert one
      $k = $or0Idx + 1
      while ($k -lt $N -and $lines[$k] -match '^\s*$') { $k++ }
      if ($k -ge $N -or ($lines[$k] -notmatch '^\s*\)\s*$')) {
        # indent for ')' should be one level (4 spaces) less than the inner lines
        $innerIndent = Get-Indent $lines[$or0Idx]
        $baseIndent  = if ($innerIndent.Length -ge 4) { $innerIndent.Substring(0, $innerIndent.Length-4) } else { "" }
        $new = New-Object System.Collections.Generic.List[string]
        $new.AddRange($lines[0..$or0Idx])
        $new.Add($baseIndent + ")")
        if ($or0Idx + 1 -le $N - 1) { $new.AddRange($lines[($or0Idx+1)..($N-1)]) }
        $lines = $new
        $N = $lines.Count
        $fixedA = $true
        Write-Host "  - Inserted missing ')' after 'or 0'"
        break
      }
    }
  }
}
if (-not $fixedA) { Write-Host "  = No missing price-closing paren found (or already correct)" }

# [B] Rebuild the messages.success(...) + return redirect("stay_list") block
Write-Host "[3/5] Rebuild success+redirect block" -ForegroundColor Cyan
# Find the last messages.success( occurrence
$msIdx = $null
for ($i=0; $i -lt $N; $i++) {
  if ($lines[$i] -match '^\s*messages\.success\(') { $msIdx = $i }
}
if ($msIdx -ne $null) {
  $baseIndent = Get-Indent $lines[$msIdx]
  $i1 = $baseIndent + (' ' * 4)

  # Find end boundary to replace up to (next def/class or return line after block or end of file)
  $end = $msIdx
  for ($j=$msIdx+1; $j -lt $N; $j++) {
    if ($lines[$j] -match '^\s*def\s+\w+\(' -or $lines[$j] -match '^\s*class\s+\w+\:' ) { break }
    if ($lines[$j] -match '^\s*return\b' ) { $end = $j; break }
    $end = $j
  }

  # Replacement block
  $replace = @(
    $baseIndent + "messages.success(",
    $i1        + "request,",
    $i1        + 'f"Import complete. Created {created}, updated {updated}, skipped {skipped}.",',
    $baseIndent + ")",
    $baseIndent + 'return redirect("stay_list")'
  )

  $pre  = if ($msIdx -gt 0) { $lines[0..($msIdx-1)] } else { @() }
  $post = if ($end -lt ($N-1)) { $lines[($end+1)..($N-1)] } else { @() }
  $lines = @($pre + $replace + $post)
  $N = $lines.Count
  Write-Host "  - Replaced messages.success block"
} else {
  Write-Host "  = messages.success(...) not found; skipping rebuild"
}

# [C] Remove concatenated junk like 'return redirect(...)    return render(...appearance...)'
Write-Host "[4/5] Remove concatenated junk & wrap ternary" -ForegroundColor Cyan
for ($i=0; $i -lt $N; $i++) {
  # Kill inline concatenation of two returns on same line
  if ($lines[$i] -match 'return\s+redirect\("stay_list"\).*return\s+render\([^\)]*appearance\.html[^\)]*\)') {
    $indent = Get-Indent $lines[$i]
    $lines[$i] = $indent + 'return redirect("stay_list")'
  }
  # Remove any plain return render(...appearance...) lines entirely (leftovers)
  if ($lines[$i] -match '^\s*return\s+render\([^\)]*appearance\.html[^\)]*\)\s*$') {
    $lines[$i] = '' # blank it
  }
}

# Wrap the list-ternary from error at line ~33 with parentheses
$raw = [string]::Join("`r`n", $lines)
$raw2 = [regex]::Replace(
  $raw,
  '\[request\.GET\.get\("state"\)\]\s+if\s+request\.GET\.get\("state"\)\s+else\s+\[\]',
  '([request.GET.get("state")] if request.GET.get("state") else [])'
)
if ($raw2 -ne $raw) {
  Write-Host "  - Wrapped state ternary with parentheses"
}
Set-Content -Path $views -Value $raw2 -NoNewline

# Verify + format
Write-Host "[5/5] Verify & format" -ForegroundColor Cyan
python -m py_compile stays\views.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! Python compile error still present in stays\views.py" -ForegroundColor Red
  Write-Host "    Showing context around the messages.success area:"
  $all = Get-Content stays\views.py
  # locate messages.success again for context
  $msLine = 0
  for ($i=0; $i -lt $all.Count; $i++) { if ($all[$i] -match '^\s*messages\.success\(') { $msLine = $i } }
  $start = [Math]::Max(0, $msLine - 10)
  $end   = [Math]::Min($all.Count-1, $msLine + 20)
  for ($i=$start; $i -le $end; $i++) { Write-Host ("{0,4}: {1}" -f $i, $all[$i]) }
  exit 1
}

try { ruff --version | Out-Null; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Done. Start server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

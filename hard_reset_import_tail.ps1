# hard_reset_import_tail.ps1
# Force-reset the malformed tail of the CSV import view in stays\views.py.

$ErrorActionPreference = "Stop"

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host "Backup: $Path.bak.$stamp"
  }
}

function Show-Context($Path, $startLine, $endLine) {
  $all = Get-Content $Path
  $n = $all.Count
  $s = [Math]::Max(0, [Math]::Min($startLine, $n-1))
  $e = [Math]::Min($n-1, [Math]::Max($endLine, 0))
  Write-Host "----- Context $s..$e ($Path) -----" -ForegroundColor DarkCyan
  for ($i=$s; $i -le $e; $i++) { Write-Host ("{0,4}: {1}" -f $i, $all[$i]) }
  Write-Host "-----------------------------------" -ForegroundColor DarkCyan
}

$views = "stays\views.py"
if (-not (Test-Path $views)) {
  Write-Host "!! $views not found." -ForegroundColor Yellow
  exit 1
}

Write-Host "[1/5] Backup" -ForegroundColor Cyan
Backup-File $views

Write-Host "[2/5] Show current trouble zone (lines 480..560)" -ForegroundColor Cyan
Show-Context $views 480 560

Write-Host "[3/5] Force-reset the import tail block" -ForegroundColor Cyan
$raw = Get-Content -Raw $views

# Normalize tabs -> spaces to stabilize matching
$raw = $raw -replace "`t", "    "

# Find the LAST messages.success( ... ) in the file (we'll assume that's the import result toast)
$match = [regex]::Matches($raw, '(?m)^\s*messages\.success\(')
if ($match.Count -eq 0) {
  Write-Host "!! No messages.success(...) found. Aborting to avoid damaging unrelated code." -ForegroundColor Yellow
  exit 1
}
$msIndex = $match[$match.Count-1].Index

# Determine base indentation at that messages.success line
$lineStart = $raw.LastIndexOf("`n", $msIndex)
if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart += 1 }
$lineEnd = $raw.IndexOf("`n", $msIndex)
if ($lineEnd -lt 0) { $lineEnd = $raw.Length }
$lineText = $raw.Substring($lineStart, $lineEnd - $lineStart)
$baseIndent = ([regex]::Match($lineText, '^\s*').Value)
$i1 = $baseIndent + (' ' * 4)

# Build clean replacement (two lines)
$clean = @()
$clean += ($baseIndent + 'messages.success(')
$clean += ($i1 + 'request,')
$clean += ($i1 + 'f"Import complete. Created {created}, updated {updated}, skipped {skipped}.",')
$clean += ($baseIndent + ')')
$clean += ($baseIndent + 'return redirect("stay_list")')
$cleanText = [string]::Join("`r`n", $clean)

# Replace from the messages.success line to:
#  - the next blank line followed by a dedent, or
#  - the next "else:" at same or less indent, or
#  - the next "return " line, or
#  - the next function/class def
# We’ll greedily eat odd constructs and reset them.
$pattern = '(?ms)' +
           '(^\s*messages\.success\([^\n]*\n(?:.+\n)*?)' +  # from this messages.success line...
           '(?=(^\s*$)|(^\s*else:\s*$)|(^\s*return\b)|(^\s*def\s+\w+\()|(^\s*class\s+\w+\:)|\Z)'  # ...until a boundary
$fixed = [regex]::Replace($raw, $pattern, $cleanText, 'Singleline')

# Extra cleanups nearby: remove lone ')', replace bare redirect with return, kill dangling "else:"
$fixed = [regex]::Replace($fixed, '(?m)^\s*\)\s*$', '')
$fixed = [regex]::Replace($fixed, '(?m)^\s*redirect\("stay_list"\)\s*$', 'return redirect("stay_list")')
# Drop "else:" if it immediately follows our return at the same indent level
$fixed = [regex]::Replace($fixed,
  '(?ms)(^' + [regex]::Escape($baseIndent) + 'return\s+redirect\("stay_list"\)\s*\r?\n)' + [regex]::Escape($baseIndent) + 'else:\s*\r?\n',
  '$1'
)

if ($fixed -ne $raw) {
  Set-Content -Path $views -Value $fixed -NoNewline
  Write-Host "  - Import tail replaced & cleaned." -ForegroundColor Green
} else {
  Write-Host "  = No changes made (pattern not found)."
}

Write-Host "[4/5] Verify & format" -ForegroundColor Cyan
python -m py_compile stays\views.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! Python compile error still present in stays\views.py" -ForegroundColor Red
  Write-Host "    Showing fresh context (480..560):" -ForegroundColor Red
  Show-Context $views 480 560
  exit 1
} else {
  Write-Host "  - Python compile check passed."
}

try { ruff --version | Out-Null; ruff check stays\views.py --fix } catch { Write-Host "  ! Ruff missing: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null; black stays\views.py } catch { Write-Host "  ! Black missing: python -m pip install black" -ForegroundColor Yellow }

Write-Host "[5/5] Done. Start server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

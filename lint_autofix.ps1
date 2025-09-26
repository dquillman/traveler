# lint_autofix.ps1
# Backs up touched files and applies safe autofixes for common Ruff findings.
# - Fix escaped quotes in auto_doctor_stays.py
# - Drop unused `before = txt`
# - Split semicolon one-liners
# - Expand colon one-line if-statements

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

function Backup($path) {
  if (Test-Path $path) { Copy-Item $path "$path.bak.$ts" -Force }
}

function ReadText($path) { Get-Content $path -Raw -ErrorAction Stop }
function WriteText($path, $text) {
  $dir = Split-Path $path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  Set-Content $path $text -Encoding UTF8
}

# ---------- 1) Fix escaped quotes in auto_doctor_stays.py ----------
$autoDoctor = ".\auto_doctor_stays.py"
if (Test-Path $autoDoctor) {
  $txt = ReadText $autoDoctor
  $orig = $txt
  # Turn print(\"...\", e) into print("...", e)
  $txt = $txt -replace 'print\\\(\\"', 'print("'
  $txt = $txt -replace '\\"\)', '")'
  # Also handle generic \" -> "
  $txt = $txt -replace '\\"', '"'
  if ($txt -ne $orig) {
    Backup $autoDoctor
    WriteText $autoDoctor $txt
    Write-Host "Fixed quotes in $autoDoctor" -ForegroundColor Green
  } else {
    Write-Host "No quote fixes needed in $autoDoctor" -ForegroundColor DarkGray
  }
} else {
  Write-Host "Skip: $autoDoctor not found" -ForegroundColor Yellow
}

# ---------- 2) Remove unused 'before = txt' ----------
$beforeTargets = @(
  ".\auto_doctor_stays_v2.py",
  ".\auto_doctor_stays_v2 - Copy.py"
) | Where-Object { Test-Path $_ }

foreach ($f in $beforeTargets) {
  $txt = ReadText $f
  $orig = $txt
  $txt = $txt -replace '(?m)^\s*before\s*=\s*txt\s*\r?\n', ''
  if ($txt -ne $orig) {
    Backup $f
    WriteText $f $txt
    Write-Host "Removed unused 'before = txt' in $f" -ForegroundColor Green
  } else {
    Write-Host "No 'before = txt' to remove in $f" -ForegroundColor DarkGray
  }
}

# ---------- 3) Split semicolon one-liners ----------
# NOTE: scoped to specific files you listed to avoid touching strings in random files.
$semicolonTargets = @(
  ".\autofix_stays.py",
  ".\patch_apply_map_charts.py",
  ".\patch_namespace_fix.py",
  ".\scripts\auto_static_doctor.py"
) | Where-Object { Test-Path $_ }

foreach ($f in $semicolonTargets) {
  $txt = ReadText $f
  $orig = $txt
  # Replace ; that separate statements with newlines, preserving indentation.
  # Heuristic: ; followed by space and a letter/underscore/quote/print/return.
  $txt = $txt -replace '(?m);\s+(?=(?:[A-Za-z_\(\'"]) )','`n'
  # More general safe pass: any ; followed by optional space then a word char
  $txt = $txt -replace '(?m);\s+(?=\w)', "`n"
  if ($txt -ne $orig) {
    Backup $f
    WriteText $f $txt
    Write-Host "Split semicolon one-liners in $f" -ForegroundColor Green
  } else {
    Write-Host "No semicolon one-liners in $f" -ForegroundColor DarkGray
  }
}

# ---------- 4) Expand colon one-line if-statements ----------
$colonTargets = @(
  ".\patch_add_route_fix.py",
  ".\scripts\verify_ui.py"
) | Where-Object { Test-Path $_ }

foreach ($f in $colonTargets) {
  $txt = ReadText $f
  $orig = $txt
  # Pattern: <indent>if <cond>: <stmt>
  $pattern = '^(?<indent>\s*)if\s+(?<cond>[^:]+):\s+(?<stmt>.+)$'
  $txt = [System.Text.RegularExpressions.Regex]::Replace(
    $txt, $pattern,
    { param($m)
      $indent = $m.Groups['indent'].Value
      $cond   = $m.Groups['cond'].Value.Trim()
      $stmt   = $m.Groups['stmt'].Value.Trim()
      # If the statement already looks like a block header, skip.
      if ($stmt -match '^(if|for|while|try|with)\b') { return $m.Value }
      # Expand into a proper block
      return "$indent" + "if $cond:`r`n$indent    $stmt"
    },
    [System.Text.RegularExpressions.RegexOptions]::Multiline
  )
  if ($txt -ne $orig) {
    Backup $f
    WriteText $f $txt
    Write-Host "Expanded colon one-liners in $f" -ForegroundColor Green
  } else {
    Write-Host "No colon one-liners matched in $f" -ForegroundColor DarkGray
  }
}

Write-Host "`nAutofix complete. Now run:" -ForegroundColor Cyan
Write-Host "  ruff check . --fix" -ForegroundColor Cyan
Write-Host "  black ." -ForegroundColor Cyan

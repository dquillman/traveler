# fix_brace_cleanup.ps1 — remove stray braces/dicts breaking syntax
$ErrorActionPreference = "Stop"
$file = "stays\views.py"
if (-not (Test-Path $file)) { Write-Error "Missing stays\views.py"; exit 1 }

# Backup
$ts  = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

$lines = Get-Content -Encoding UTF8 $file

# Comment out any suspicious lone "{" or "}" between lines 30–60
for ($i=29; $i -le 59 -and $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln.Trim() -eq "{" -or $ln.Trim() -eq "}" -or $ln.Trim() -eq "[") {
        $lines[$i] = "# FIXED stray brace: " + $ln
        Write-Host "Commented out stray brace on line $($i+1)"
    }
}

# Write back
Set-Content -Path $file -Value $lines -Encoding UTF8
Write-Host "Stray braces commented."

# Show the repaired region
Write-Host "`n--- Lines 30–60 after cleanup ---"
$lines[29..([Math]::Min(59,$lines.Count-1))] | ForEach-Object { Write-Host $_ }
Write-Host "--- End snippet ---`n"

Write-Host "Now run: python -m py_compile stays\views.py"

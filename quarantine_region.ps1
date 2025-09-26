# quarantine_region.ps1 — comment out stray top-level code in lines 30–70
$ErrorActionPreference = 'Stop'
$file = 'stays\views.py'
if (-not (Test-Path $file)) { Write-Error 'Missing stays\views.py'; exit 1 }

# Backup
$ts  = (Get-Date).ToString('yyyyMMdd_HHmmss')
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

$lines = Get-Content -Encoding UTF8 $file

# Comment out lines 30–70 unless they start with def/class/import/from/@/# or are blank
$start = 29
$end   = [Math]::Min(69, $lines.Count - 1)
for ($i = $start; $i -le $end; $i++) {
    $t = $lines[$i].TrimStart()
    if ($t -eq '') { continue }
    if ($t -match '^(def|class|from |import |@|#)') { continue }
    # If line already commented by earlier scripts, skip
    if ($t -match '^#') { continue }
    $lines[$i] = '# QUARANTINED: ' + $lines[$i]
}

Set-Content -Path $file -Value $lines -Encoding UTF8
Write-Host 'Quarantined lines 30–70.'

# Show the cleaned region for sanity
Write-Host "`n--- Lines 30–70 after quarantine ---"
for ($i = $start; $i -le $end; $i++) { "{0,4}: {1}" -f ($i+1), $lines[$i] | Write-Host }
Write-Host '--- End snippet ---'

# Quick compile check
try {
    & python -m py_compile $file
    Write-Host 'Python compile OK.'
} catch {
    Write-Warning 'Python reported an error. Paste the new file/line/caret.'
}

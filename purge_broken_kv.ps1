# purge_broken_kv.ps1 — comment out stray key/value lines near the top
$ErrorActionPreference = 'Stop'
$file = 'stays\views.py'
if (-not (Test-Path $file)) { Write-Error 'Missing stays\views.py'; exit 1 }

# Backup
$ts  = (Get-Date).ToString('yyyyMMdd_HHmmss')
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

$lines = Get-Content -Encoding UTF8 $file

# Look for lines in 30–60 range starting with a string key pattern
for ($i=29; $i -le 59 -and $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln.Trim() -match '^"\w+' -and $ln -match ':') {
        $lines[$i] = '# FIXED stray kv: ' + $ln
        Write-Host ("Commented out stray key/value on line {0}" -f ($i+1))
    }
}

# Write file back
Set-Content -Path $file -Value $lines -Encoding UTF8
Write-Host 'Wrote updated: stays\views.py'

# Compile check
try {
    & python -m py_compile $file
    Write-Host 'Python compile OK.'
} catch {
    Write-Warning 'Python still errors. Paste the file/line/caret so I can fix next culprit.'
}

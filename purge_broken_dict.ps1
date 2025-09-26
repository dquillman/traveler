# purge_broken_dict.ps1 — comments out a stray top-level { ... } block near the top
$ErrorActionPreference = 'Stop'
$file = 'stays\views.py'
if (-not (Test-Path $file)) { Write-Error 'Missing stays\views.py'; exit 1 }

# Backup
$ts  = (Get-Date).ToString('yyyyMMdd_HHmmss')
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

$lines = Get-Content -Encoding UTF8 $file

# Find a top-level { ... } block between lines 30–60 and comment it out
$startIdx = $null
$endIdx   = $null
for ($i = 29; $i -lt [Math]::Min(60, $lines.Count); $i++) {
    if ($null -eq $startIdx -and $lines[$i].Trim() -eq '{') {
        $startIdx = $i
        continue
    }
    if ($null -ne $startIdx) {
        if ($lines[$i].Trim() -eq '}') {
            $endIdx = $i
            break
        }
    }
}

if ($null -ne $startIdx -and $null -ne $endIdx) {
    for ($j = $startIdx; $j -le $endIdx; $j++) {
        $lines[$j] = '# FIXED broken top-level dict: ' + $lines[$j]
    }
    Write-Host "Commented broken dict block lines $($startIdx+1)–$($endIdx+1)."
} else {
    Write-Host "No obvious top-level { ... } block found in lines 30–60. Skipping dict purge."
}

# Write file back
Set-Content -Path $file -Value $lines -Encoding UTF8
Write-Host 'Wrote updated: stays\views.py'

# Compile check
try {
    & python -m py_compile $file
    Write-Host 'Python compile OK.'
} catch {
    Write-Warning 'Python reported an error. Please paste the new file/line/caret.'
}

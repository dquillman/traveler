# nuke_region.ps1 — comment out lines 30–70 in stays\views.py
$ErrorActionPreference = 'Stop'
$file = 'stays\views.py'
if (-not (Test-Path $file)) { Write-Error 'Missing stays\views.py'; exit 1 }

# Backup
$ts  = (Get-Date).ToString('yyyyMMdd_HHmmss')
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

$lines = Get-Content -Encoding UTF8 $file

$start = 29
$end   = [Math]::Min(69, $lines.Count - 1)
for ($i = $start; $i -le $end; $i++) {
    if ($lines[$i] -notmatch '^#') {
        $lines[$i] = '# NUKED: ' + $lines[$i]
    }
}

Set-Content -Path $file -Value $lines -Encoding UTF8
Write-Host "Commented out lines 30–70."

Write-Host "Now run: python -m py_compile stays\views.py"

# fix_views_cleanup.ps1 — remove escaped junk lines from stays\views.py
$ErrorActionPreference = "Stop"
$file = "stays\views.py"
if (-not (Test-Path $file)) { Write-Error "Missing stays\views.py"; exit 1 }

# Backup
$ts  = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

# Read all lines
$lines = Get-Content -Encoding UTF8 $file

# Drop any lines that look like our earlier escaped replacement (contain \r\n or def\ etc.)
$clean = foreach ($ln in $lines) {
    if ($ln -match '\\r\\n' -or                      # literal \r\n sequences
        $ln -match 'def\\\s' -or                     # "def\ "
        $ln -match '\\\('  -or                       # "\("
        $ln -match '\\\)'  -or                       # "\)"
        $ln -match 'messages\\\.success' -or         # "messages\.success" with escapes
        $ln -match 'return\\\s' -or                  # "return\ "
        $ln -match 'redirect\\\('                    # "redirect\("
       ) {
        # skip this mangled line
        continue
    }
    $ln
}

# Write cleaned file
Set-Content -Path $file -Value $clean -Encoding UTF8
Write-Host "Removed escaped junk lines."

# Optional: compile check
try {
    & python -m py_compile $file
    Write-Host "python compile OK."
} catch {
    Write-Warning "python reported an error. Open the mentioned line and paste it here."
}

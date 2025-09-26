# force_map_fix.ps1 — nuke broken stays_map_data and append a clean one at EOF
$ErrorActionPreference = "Stop"
$file = "stays\views.py"
if (-not (Test-Path $file)) { Write-Error "Missing stays\views.py"; exit 1 }

# Backup
$ts  = (Get-Date).ToString("yyyyMMdd_HHmmss")
$bak = "$file.bak.$ts"
Copy-Item $file $bak -Force
Write-Host "Backup: $bak"

# Read lines
$lines = Get-Content -Encoding UTF8 $file

# Remove any existing stays_map_data defs
$pattern = '^\s*def\s+stays_map_data\s*\('
$cleaned = @()
$skip = $false
foreach ($ln in $lines) {
    if ($ln -match $pattern) {
        $skip = $true
        continue
    }
    if ($skip) {
        if ($ln -match '^\s*def\s+' -or $ln -match '^\s*class\s+' -or $ln.Trim() -eq "") {
            $skip = $false
        } else {
            continue
        }
    }
    $cleaned += $ln
}

# Append clean version at EOF
$block = @'
def stays_map_data(request):
    qs = Stay.objects.exclude(latitude__isnull=True).exclude(longitude__isnull=True)
    stays = list(qs.values("id", "city", "state", "latitude", "longitude"))
    return JsonResponse({"stays": stays})
'@

$cleaned += ""
$cleaned += $block

# Write back
Set-Content -Path $file -Value $cleaned -Encoding UTF8
Write-Host "Appended clean stays_map_data at EOF."

Write-Host "Now run: python -m py_compile stays\views.py"

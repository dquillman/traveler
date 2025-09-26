# purge_price_per_night_admin.ps1
$ErrorActionPreference = "Stop"
$admin = "stays\admin.py"
if (-not (Test-Path $admin)) {
  Write-Host "No stays\admin.py found — nothing to do."
  exit 0
}

# Backup
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
Copy-Item $admin "$admin.bak.$ts" -Force
Write-Host "Backup: $admin.bak.$ts"

# Load text
$text = Get-Content -Raw -Encoding UTF8 $admin

# Remove common token patterns in tuples/lists/dicts (both quote styles)
$patterns = @(
  "'price_per_night',",   # 'price_per_night',
  ",\s*'price_per_night'",# , 'price_per_night'
  '"price_per_night",',   # "price_per_night",
  ',\s*"price_per_night"' # , "price_per_night"
)

foreach ($p in $patterns) {
  $text = $text -replace [regex]::Escape($p), ''
}

# Fallback: bare token
$text = $text -replace "\bprice_per_night\b", ""

# Tidy accidental double-commas and bracket spacing
$text = $text -replace ",\s*,", ","
$text = $text -replace "\[\s*,", "["
$text = $text -replace ",\s*\]", "]"
$text = $text -replace "\(\s*,", "("
$text = $text -replace ",\s*\)", ")"

# Write back
Set-Content -Path $admin -Value $text -Encoding UTF8
Write-Host "Cleaned stays\admin.py"

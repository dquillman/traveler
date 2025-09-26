# restore_stay_fields.ps1
param(
  [string]$Root = "G:\users\daveq\traveler"
)
$ErrorActionPreference = "Stop"
Set-Location $Root

$modelsPath = Join-Path $Root "stays\models.py"
if (-not (Test-Path $modelsPath)) {
  Write-Host "❌ stays\models.py not found at $modelsPath" -ForegroundColor Red
  exit 1
}

$orig = Get-Content $modelsPath -Raw -Encoding UTF8
$backup = "$modelsPath.bak.$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
Copy-Item $modelsPath $backup
Write-Host "✅ Backup: $backup" -ForegroundColor Yellow

# Locate Stay model class block naive but robustly
$classStart = [regex]::Match($orig, "(?ms)^\s*class\s+Stay\s*\(\s*models\.Model\s*\)\s*:\s*$")
if (-not $classStart.Success) {
  Write-Host "❌ Could not find 'class Stay(models.Model):' in stays\models.py" -ForegroundColor Red
  exit 1
}

$startIndex = $classStart.Index + $classStart.Length
# Find end of class by searching for the next top-level 'class ' after start
$after = $orig.Substring($startIndex)
$nextClass = [regex]::Match($after, "(?ms)^\s*class\s+\w+\s*\(")
if ($nextClass.Success) {
  $classEndIndex = $startIndex + $nextClass.Index
} else {
  $classEndIndex = $orig.Length
}

$beforeClass = $orig.Substring(0, $startIndex)
$classBody   = $orig.Substring($startIndex, $classEndIndex - $startIndex)
$afterClass  = $orig.Substring($classEndIndex)

# Prepare missing fields (simple string check)
function Ensure-Field {
  param([string]$body, [string]$name, [string]$definition)
  if ($body -notmatch "(?m)^\s*$name\s*=") {
    return $body + "`n    # ADDED by restore_stay_fields.ps1`n    $definition`n"
  }
  return $body
}

$classBody = Ensure-Field $classBody "photo"           "photo = models.ImageField(upload_to='stays_photos/', null=True, blank=True)"
$classBody = Ensure-Field $classBody "rate_per_night"  "rate_per_night = models.DecimalField(max_digits=10, decimal_places=2, default=0)"
$classBody = Ensure-Field $classBody "total"           "total = models.DecimalField(max_digits=10, decimal_places=2, default=0)"
$classBody = Ensure-Field $classBody "fees"            "fees = models.DecimalField(max_digits=10, decimal_places=2, default=0)"
$classBody = Ensure-Field $classBody "site"            "site = models.CharField(max_length=20, blank=True)"

$newModels = $beforeClass + $classBody + $afterClass
Set-Content -Path $modelsPath -Value $newModels -Encoding UTF8
Write-Host "✅ stays\models.py updated." -ForegroundColor Green

# Run migrations
Write-Host "📦 Making migrations..." -ForegroundColor Cyan
python manage.py makemigrations stays
Write-Host "🚀 Applying migrations..." -ForegroundColor Cyan
python manage.py migrate

Write-Host "Done. If server is running, restart it." -ForegroundColor Green

# quick_fix_admin_and_unused.ps1
$ErrorActionPreference = "Stop"

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host "Backup: $Path.bak.$stamp"
  }
}

# 1) Fix stays/admin.py by overwriting with a clean version
$admin = "stays\admin.py"
if (Test-Path $admin) {
  Write-Host "[1/3] Repairing $admin"
  Backup-File $admin
} else {
  Write-Host "[1/3] Creating $admin"
  New-Item -ItemType File -Path $admin -Force | Out-Null
}
$adminContent = @'
from django.contrib import admin
from .models import Stay

@admin.register(Stay)
class StayAdmin(admin.ModelAdmin):
    list_display = ("park", "city", "state", "check_in", "nights", "price_per_night", "elect_extra", "paid")
'@
Set-Content -Path $admin -Value $adminContent -Encoding UTF8 -NoNewline
Write-Host "  - admin.py written"

# 2) Remove the unused variable line from patch_detail_edit_fix.py
$patch = "patch_detail_edit_fix.py"
if (Test-Path $patch) {
  Write-Host "[2/3] Cleaning $patch"
  Backup-File $patch
  $raw = Get-Content -Raw $patch
  $new = [regex]::Replace($raw, '^\s*changed\s*=\s*False\s*\r?\n', '', 'Multiline')
  if ($new -ne $raw) {
    Set-Content -Path $patch -Value $new -Encoding UTF8 -NoNewline
    Write-Host "  - removed 'changed = False'"
  } else {
    Write-Host "  - nothing to change"
  }
} else {
  Write-Host "[2/3] $patch not found (skipping)"
}

# 3) Migrate + Ruff + Black
Write-Host "[3/3] Migrations + Ruff + Black"
try { python manage.py makemigrations ; python manage.py migrate } catch { Write-Host "  ! migration error: $($_.Exception.Message)" -ForegroundColor Yellow }
try { ruff --version | Out-Null ; ruff check . --fix } catch { Write-Host "  ! install Ruff: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null ; black . } catch { Write-Host "  ! install Black: python -m pip install black" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Run the server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green

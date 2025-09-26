# fix_missing_column.ps1 — make and apply migrations for stays app
$ErrorActionPreference = "Stop"

# Stop any running server before running this script.

# 1) Backup SQLite DB if present
$db = "db.sqlite3"
if (Test-Path $db) {
    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    Copy-Item $db "$db.bak.$ts" -Force
    Write-Host "Backup DB created: $db.bak.$ts"
} else {
    Write-Host "No db.sqlite3 found — Django will create a new one if needed."
}

# 2) Pick the right Python
$py = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }

# 3) Run makemigrations and migrate
& $py manage.py makemigrations stays
& $py manage.py migrate

Write-Host "Migrations complete. Now run: python manage.py runserver"

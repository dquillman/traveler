Param()
$ErrorActionPreference = "Stop"
Write-Host "Running Traveler namespace & template fix..." -ForegroundColor Cyan
$python = ".\venv\Scripts\python.exe"
if (!(Test-Path $python)) {
    Write-Host "Python venv not found at .\venv\Scripts\python.exe. Trying 'python' on PATH..." -ForegroundColor Yellow
    $python = "python"
}
& $python ".\patch_namespace_fix.py"
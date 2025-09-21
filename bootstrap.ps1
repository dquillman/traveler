# Windows bootstrap
$ErrorActionPreference='Stop'
$scriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir
if (-not (Test-Path '.\venv')) { python -m venv venv }
. .\venv\Scripts\Activate.ps1
pip install --upgrade pip
pip install -r requirements.txt
python manage.py makemigrations
python manage.py migrate
python manage.py runserver

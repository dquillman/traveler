# doctor_stay_model.ps1
    # Prints model fields (name, editable) and DB columns to help align form & model.
    param(
      [string]$Root = "G:\users\daveq\traveler"
    )
    Set-Location $Root
    $py = @'
from django import setup
setup()
from django.db import connection
from stays.models import Stay
from pprint import pprint

print("=== Model fields (name, editable) ===")
for f in Stay._meta.get_fields():
    if getattr(f, "concrete", False) and not getattr(f, "auto_created", False):
        print(f" - {f.name} (editable={getattr(f, 'editable', True)})")

print("\\n=== DB columns on table stays_stay ===")
with connection.cursor() as cursor:
    desc = connection.introspection.get_table_description(cursor, "stays_stay")
    for c in desc:
        print(f" - {c.name}")
'@

    $tmp = Join-Path $env:TEMP ("doctor_stay_model_" + (Get-Date).ToString("yyyyMMdd_HHmmss") + ".py")
    Set-Content -Path $tmp -Value $py -Encoding UTF8

    Write-Host "Running doctor..." -ForegroundColor Cyan
    python manage.py shell < $tmp

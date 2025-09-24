# fix_doctor_bom.ps1
# Patches stays_doctor.ps1 so the probe file is written without BOM

$ErrorActionPreference = "Stop"

$target = "stays_doctor.ps1"
if (-not (Test-Path $target)) {
    throw "Could not find $target in current directory."
}

$content = Get-Content $target -Raw -Encoding UTF8

# Replace the section that writes the probe with a BOM-free version
$patch = @'
# 1) Write probe code to a temp file (ASCII to avoid BOM)
$probePath = Join-Path $PWD "_doctor_probe.py"
$probeContent = @"
import json, importlib
from django.apps import apps
from django.urls import get_resolver

data = {}

try:
    Stay = apps.get_model("stays","Stay")
    fields = [f.name for f in Stay._meta.get_fields() if getattr(f,"concrete",False)]
except Exception:
    fields = []
data["stay_fields"] = fields

def collect(patterns, acc):
    for p in patterns:
        if hasattr(p, "url_patterns"):
            collect(p.url_patterns, acc)
        else:
            n = getattr(p, "name", None)
            if n:
                acc.append(n)

resolver = get_resolver()
acc = []
collect(resolver.url_patterns, acc)
data["url_names"] = sorted(set([n for n in acc if n]))

try:
    views = importlib.import_module("stays.views")
    members = [a for a in dir(views) if not a.startswith("_")]
except Exception:
    members = []
data["stays_views"] = members

print(json.dumps(data))
"@

# Write with NO BOM
[System.IO.File]::WriteAllText($probePath, $probeContent, [System.Text.Encoding]::ASCII)
'@

if ($content -match "_doctor_probe\.py") {
    # Replace everything from the original probe writer up to first Run message
    $content = $content -replace "(?s)# 1\).*?Write-Host ""Running Django doctor...""", "$patch`r`n`r`nWrite-Host `"Running Django doctor...`""
    Set-Content $target $content -Encoding UTF8
    Write-Host "Patched $target to write probe in ASCII (no BOM)."
} else {
    Write-Host "Could not locate probe writer section in $target. No changes made." -ForegroundColor Yellow
}

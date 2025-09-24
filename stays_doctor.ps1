# stays_doctor.ps1  — clean, non-interactive, JSON-safe
param([switch]$Fix)

$ErrorActionPreference = "Stop"

if (-not (Test-Path "manage.py")) { throw "Run from your Django project root (manage.py not found)." }

# Detect DJANGO_SETTINGS_MODULE from manage.py (fallback to config.settings)
$manage = Get-Content "manage.py" -Raw -Encoding UTF8
$settingsModule = "config.settings"
$rx = [regex]"os\.environ\.setdefault\(\s*['""]DJANGO_SETTINGS_MODULE['""],\s*['""]([^'""]+)['""]\s*\)"
$m = $rx.Match($manage)
if ($m.Success) { $settingsModule = $m.Groups[1].Value }

# --- write a standalone Python probe (UTF-8 NO BOM) ---
$probePath = Join-Path $PWD "_doctor_probe_run.py"
$probeContent = @'
import os, json, importlib
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "__SETTINGS__")
import django
django.setup()
from django.apps import apps
from django.urls import get_resolver

data = {}

# Stay model fields (concrete only)
try:
    Stay = apps.get_model("stays","Stay")
    fields = [f.name for f in Stay._meta.get_fields() if getattr(f,"concrete",False)]
except Exception:
    fields = []
data["stay_fields"] = fields

# URL names (walk nested patterns)
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
data["url_names"] = sorted(set(n for n in acc if n))

# stays.views attributes
try:
    views = importlib.import_module("stays.views")
    members = [a for a in dir(views) if not a.startswith("_")]
except Exception:
    members = []
data["stays_views"] = members

print(json.dumps(data))
'@
$probeContent = $probeContent.Replace("__SETTINGS__", $settingsModule)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($probePath, $probeContent, $utf8NoBom)

Write-Host "Running Django doctor (non-interactive)..."

# --- run the probe ---
$out = & python $probePath 2>&1
if ($LASTEXITCODE -ne 0 -or -not $out) {
  Write-Host "Probe failed. Output:"
  Write-Host $out
  throw "Probe failed"
}

try { $info = $out | ConvertFrom-Json }
catch {
  Write-Host "JSON parse failed. Raw output:"
  Write-Host $out
  throw
}
Remove-Item $probePath -ErrorAction SilentlyContinue

$stayFields = @($info.stay_fields)
$urlNames   = @($info.url_names)
$viewsAttrs = @($info.stays_views)

Write-Host ""
Write-Host "Stay fields:";        $stayFields | ForEach-Object { Write-Host " - $_" }
Write-Host ""
Write-Host "URL names:";          $urlNames   | ForEach-Object { Write-Host " - $_" }
Write-Host ""
Write-Host "stays.views attrs:";  $viewsAttrs | ForEach-Object { Write-Host " - $_" }

# --- scan primary template ---
$templatePath = "templates\stays\stay_list.html"
$unknownStayFields = @()
$unknownUrlNames   = @()

if (Test-Path $templatePath) {
  $tpl = Get-Content $templatePath -Raw
  $fieldMatches = [regex]::Matches($tpl, 'stay\.(\w+)')
  $referenced = @()
  foreach ($m2 in $fieldMatches) { $referenced += $m2.Groups[1].Value }
  $referenced = $referenced | Sort-Object -Unique
  foreach ($r in $referenced) { if ($stayFields -notcontains $r) { $unknownStayFields += $r } }

  $urlMatches = [regex]::Matches($tpl, "{%\s*url\s+'([^']+)'\s*[^%]*%}")
  $urlRefs = @()
  foreach ($m3 in $urlMatches) { $urlRefs += $m3.Groups[1].Value }
  $urlRefs = $urlRefs | Sort-Object -Unique
  foreach ($n in $urlRefs) { if ($urlNames -notcontains $n) { $unknownUrlNames += $n } }

  Write-Host ""
  Write-Host "Template scan: $templatePath"
  if ($referenced.Count -gt 0) { Write-Host ("Referenced stay.<field>: " + ($referenced -join ", ")) } else { Write-Host "No stay.<field> refs" }
  if ($unknownStayFields.Count -gt 0) { Write-Host ("Unknown fields in template: " + ($unknownStayFields -join ", ")) } else { Write-Host "Template fields OK." }
  if ($unknownUrlNames.Count -gt 0)   { Write-Host ("Missing URL names in template: " + ($unknownUrlNames -join ", ")) } else { Write-Host "Template URL tags OK." }
} else {
  Write-Host ""
  Write-Host "Template not found: $templatePath"
}

# --- optional fixes ---
$fixesApplied = @()

# alias 'list' -> stay_list if missing (for reverse('list'))
if ($urlNames -notcontains "list") {
  if ($Fix) {
    $urlsPath = "stays\urls.py"
    if (Test-Path $urlsPath) {
      $u = Get-Content $urlsPath -Raw
      if ($u -notmatch "name='list'") {
        if ($u -match "urlpatterns\s*=\s*\[") {
          $u = $u -replace "urlpatterns\s*=\s*\[", "urlpatterns = [`r`n    path('stays/', views.stay_list, name='list'),"
          Set-Content $urlsPath $u -Encoding UTF8
          $fixesApplied += "Added alias route name='list' in stays/urls.py"
        }
      }
    }
  } else {
    Write-Host ""
    Write-Host "Suggestion: add alias route path('stays/', views.stay_list, name='list') in stays/urls.py"
  }
}

# stub legacy views if your config/urls.py still references them
$likelyLegacy = @("appearance_view","export_view","import_view","charts_view","map_view")
$needStubs = @()
foreach ($n in $likelyLegacy) { if ($viewsAttrs -notcontains $n) { $needStubs += $n } }

if ($needStubs.Count -gt 0 -and $Fix) {
  $viewsPath = "stays\views.py"
  if (Test-Path $viewsPath) {
    $v = Get-Content $viewsPath -Raw
    if ($v -notmatch "from\s+django\.http\s+import\s+HttpResponse") {
      if ($v -match "from\s+django\.http\s+import\s+JsonResponse") {
        $v = $v -replace "from\s+django\.http\s+import\s+JsonResponse", "from django.http import JsonResponse, HttpResponse"
      } else {
        $v = "from django.http import HttpResponse`r`n" + $v
      }
    }
    foreach ($stub in $needStubs) {
      if ($v -notmatch "\bdef\s+$stub\s*\(") {
        $v += "`r`n`r`n" + "def $stub(request):`r`n    return HttpResponse('$stub page (stub).')`r`n"
        $fixesApplied += "Added stub view $stub in stays/views.py"
      }
    }
    Set-Content $viewsPath $v -Encoding UTF8
  }
} elseif ($needStubs.Count -gt 0) {
  Write-Host ""
  Write-Host ("Missing stays.views: " + ($needStubs -join ", ") + " (run with -Fix to add stubs)")
}

# --- summary ---
Write-Host ""
Write-Host "--- Doctor Summary ---"
if ($unknownStayFields.Count -gt 0) { Write-Host ("Template unknown fields: " + ($unknownStayFields -join ", ")) } else { Write-Host "Template fields OK." }
if ($unknownUrlNames.Count   -gt 0) { Write-Host ("Template missing URL names: " + ($unknownUrlNames -join ", ")) } else { Write-Host "Template URL tags OK." }
if ($Fix -and $fixesApplied.Count -gt 0) { Write-Host ("Fixes applied: " + ($fixesApplied -join " | ")) } else { Write-Host "No fixes applied." }

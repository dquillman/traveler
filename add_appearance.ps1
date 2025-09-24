# add_appearance.ps1
$ErrorActionPreference = "Stop"

function Backup($p){ if(Test-Path $p){ Copy-Item $p "$p.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force } }

$views = "stays\views.py"
$urls  = "stays\urls.py"
$cfg   = "config\urls.py"
$tpl   = "templates\stays\appearance.html"

if(!(Test-Path $views)){ throw "Missing $views" }
if(!(Test-Path $urls)){ throw "Missing $urls" }
if(!(Test-Path "templates\stays")){ New-Item -ItemType Directory -Force -Path "templates\stays" | Out-Null }

# 1) stays/views.py: add appearance_page view
Backup $views
$v = Get-Content $views -Raw
if ($v -notmatch "from django.shortcuts import render") {
  $v = "from django.shortcuts import render`r`n" + $v
}
if ($v -notmatch "def\s+appearance_page\(") {
  $v = $v.TrimEnd() + @"

def appearance_page(request):
    # keep it simple; renders a template that includes a top nav
    return render(request, 'stays/appearance.html')
"@
}
Set-Content -Path $views -Value $v -Encoding UTF8

# 2) stays/urls.py: add /stays/appearance/ route (namespaced)
Backup $urls
$u = Get-Content $urls -Raw
if ($u -notmatch "(?m)^\s*from\s+django\.urls\s+import\s+path") {
  $u = "from django.urls import path`r`n" + $u
}
if ($u -notmatch "(?m)^\s*from\s+\.\s+import\s+views") {
  $u = $u -replace "(?m)(from\s+django\.urls\s+import[^\n]+)", '$1' + "`r`nfrom . import views"
}
if ($u -notmatch "(?m)^\s*app_name\s*=\s*['""]stays['""]") {
  $u = $u -replace "(?m)(from\s+\.\s+import\s+views\s*)", "$1`r`napp_name = 'stays'`r`n"
}
if ($u -notmatch "name=['""]stays_appearance['""]") {
  $u = [regex]::Replace($u, "(?s)(urlpatterns\s*=\s*\[)(.*?)(\])", {
    $pre=$args[0].Groups[1].Value; $mid=$args[0].Groups[2].Value; $post=$args[0].Groups[3].Value
    $pre + $mid.TrimEnd() + "`r`n    path('appearance/', views.appearance_page, name='stays_appearance'),`r`n" + $post
  })
}
Set-Content -Path $urls -Value $u -Encoding UTF8

# 3) config/urls.py: add root alias /appearance/ -> /stays/appearance/
Backup $cfg
$c = Get-Content $cfg -Raw
if ($c -notmatch "from\s+django\.views\.generic\.base\s+import\s+RedirectView") {
  if ($c -match "from\s+django\.urls\s+import\s+path.*") {
    $c = $c -replace "from\s+django\.urls\s+import\s+path.*", "from django.urls import path, include`r`nfrom django.views.generic.base import RedirectView"
  } else {
    $c = "from django.urls import path, include`r`nfrom django.views.generic.base import RedirectView`r`n" + $c
  }
}
if ($c -notmatch "(?m)path\('appearance/',") {
  $c = $c -replace "(?s)(urlpatterns\s*=\s*\[)", "`$1`r`n    path('appearance/', RedirectView.as_view(url='/stays/appearance/', permanent=False)),"
}
Set-Content -Path $cfg -Value $c -Encoding UTF8

# 4) Template: simple page with the same quick nav you have elsewhere
if (!(Test-Path $tpl)) {
@'
<!doctype html><meta charset="utf-8"><title>Traveler • Appearance</title>
<style>:root{--bg:#0f1220;--card:#161a2b;--ink:#e8ebff;--muted:#9aa4d2;--line:#272b41}
body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto}
.wrap{max-width:900px;margin:0 auto;padding:16px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);padding:16px}
.nav{position:sticky;top:0;background:#0f1220;border-bottom:1px solid var(--line);padding:10px 12px;z-index:9}
.nav a{margin-right:12px;color:#e8ebff;text-decoration:none}
label{display:block;margin:12px 0 6px}
select,input[type=color]{padding:8px;border-radius:10px;border:1px solid var(--line);background:#0e1330;color:var(--ink)}
</style>
<div class="nav">
  <a href="/stays/">Stays</a>
  <a href="/stays/map/">Map</a>
  <a href="/stays/charts/">Charts</a>
  <a href="/stays/export/">Export</a>
  <a href="/stays/import/">Import</a>
  <a href="/stays/appearance/">Appearance</a>
</div>
<div class="wrap"><div class="panel">
  <h1>Appearance</h1>
  <p class="muted">(placeholder) Tweak theme options here.</p>
  <label for="theme">Theme</label>
  <select id="theme">
    <option>Dark</option>
    <option>Light</option>
  </select>
  <label for="accent">Accent color</label>
  <input id="accent" type="color" value="#b9c6ff">
</div></div>
'@ | Set-Content -Path $tpl -Encoding UTF8
}
Write-Host "✅ Appearance wired: /stays/appearance/ and /appearance/ alias."

# repair_traveler_site.ps1
# Quoting-safe, ASCII-only patcher for Traveler.

$ErrorActionPreference = "Stop"

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp"
    Write-Host "Backup: $Path.bak.$stamp"
  }
}

function Ensure-ImportLine {
  param(
    [string]$Path,
    [string]$Line
  )
  $raw = Get-Content -Raw $Path
  if ($raw -notmatch [regex]::Escape($Line)) {
    $raw = $Line + "`r`n" + $raw
    Set-Content -Path $Path -Value $raw -NoNewline
    Write-Host "  + import added: $Line"
    return $true
  }
  return $false
}

function Replace-Regex {
  param(
    [string]$Path,
    [string]$Pattern,
    [string]$Replacement,
    [switch]$SingleLine
  )
  $raw = Get-Content -Raw $Path
  $opts = 'Multiline'
  if ($SingleLine) { $opts = 'Singleline' }
  $new = [regex]::Replace($raw, $Pattern, $Replacement, $opts)
  if ($new -ne $raw) {
    Set-Content -Path $Path -Value $new -NoNewline
    return $true
  }
  return $false
}

Write-Host "=== Traveler Repair (steps 6-11) ==="

# 1) stays/urls.py: ensure stays_map_data route exists
$urls = "stays\urls.py"
if (Test-Path $urls) {
  Write-Host "[1/7] Patching $urls"
  Backup-File $urls
  Ensure-ImportLine -Path $urls -Line "from django.urls import path" | Out-Null
  Ensure-ImportLine -Path $urls -Line "from . import views" | Out-Null

  $raw = Get-Content -Raw $urls
  if ($raw -notmatch "name=['""]stays_map_data['""]") {
    # Try to inject inside urlpatterns list
    $pattern = "urlpatterns\s*=\s*\[(.*?)\]"
    if ($raw -match $pattern) {
      $existing = $Matches[1]
      if ($existing -notmatch "stays_map_data") {
        $injection = "    path('map-data/', views.stays_map_data, name='stays_map_data'),"
        # Ensure trailing comma then add our line before closing ]
        $newBlock = $existing.TrimEnd()
        if ($newBlock.Length -gt 0 -and $newBlock.TrimEnd()[-1] -ne ',') { $newBlock += "," }
        $newBlock += "`r`n$injection"
        $raw = [regex]::Replace($raw, $pattern, "urlpatterns = [`r`n$newBlock`r`n]", 'Singleline')
        Set-Content -Path $urls -Value $raw -NoNewline
        Write-Host "  + added stays_map_data route"
      }
    } else {
@'
from django.urls import path
from . import views

urlpatterns = [
    path("", views.stay_list, name="stay_list"),
    path("map/", views.stay_map, name="stay_map"),
    path("map-data/", views.stays_map_data, name="stays_map_data"),
    path("add/", views.stay_create, name="stay_create"),
]
'@ | Add-Content -Path $urls
      Write-Host "  + created urlpatterns incl. stays_map_data"
    }
  } else {
    Write-Host "  = route already present"
  }
} else {
  Write-Host "  ! $urls not found (skipping)" -ForegroundColor Yellow
}

# 2) stays/views.py: ensure JsonResponse import, stays_map_data view, extend CSV import
$views = "stays\views.py"
if (Test-Path $views) {
  Write-Host "[2/7] Patching $views"
  Backup-File $views
  Ensure-ImportLine -Path $views -Line "from django.http import JsonResponse" | Out-Null

  $raw = Get-Content -Raw $views
  if ($raw -notmatch "\bdef\s+stays_map_data\s*\(") {
@'
def stays_map_data(request):
    qs = Stay.objects.all().values(
        "id", "park", "city", "state", "latitude", "longitude", "check_in", "check_out", "nights"
    )
    items = []
    for r in qs:
        if r["latitude"] is None or r["longitude"] is None:
            continue
        items.append({
            "id": r["id"],
            "park": r["park"],
            "city": r["city"],
            "state": r["state"],
            "lat": float(r["latitude"]),
            "lng": float(r["longitude"]),
            "check_in": r["check_in"],
            "check_out": r["check_out"],
            "nights": r["nights"],
            "edit_url": f"/stays/{r['id']}/edit/",
        })
    return JsonResponse({"stays": items})
'@ | Add-Content -Path $views
    Write-Host "  + added stays_map_data view"
  } else {
    Write-Host "  = stays_map_data already present"
  }

  # Extend CSV import: add elect_extra parse and include fields in defaults
  $raw2 = Get-Content -Raw $views
  $changed = $false

  if ($raw2 -notmatch "\belect_extra\b") {
    # After a price = float(...) block, insert elect_extra parse (first occurrence only)
    $raw2 = [regex]::Replace(
      $raw2,
      "price\s*=\s*float\((?:.|\r?\n)*?\)\s*(?:\r?\n)+",
      { param($m)
@"
$($m.Value)                elect_extra = (row.get("elect extra") or row.get("elect_extra") or "").strip().lower() in {"yes","true","1","y","on","checked"}
"@
      },
      'Singleline'
    )
    $changed = $true
  }

  if ($raw2 -notmatch '"price_per_night"\s*:\s*price' -or $raw2 -notmatch '"elect_extra"\s*:\s*elect_extra') {
    $raw2 = [regex]::Replace(
      $raw2,
      "(defaults\s*=\s*\{)(.*?)(\})",
      { param($m)
        $pre = $m.Groups[1].Value
        $mid = $m.Groups[2].Value
        $post = $m.Groups[3].Value
        if ($mid -notmatch "price_per_night") { $mid += "`r`n                        ""price_per_night"": price," }
        if ($mid -notmatch "elect_extra")     { $mid += "`r`n                        ""elect_extra"": elect_extra," }
        return $pre + $mid + $post
      },
      'Singleline'
    )
    $changed = $true
  }

  if ($changed) {
    Set-Content -Path $views -Value $raw2 -NoNewline
    Write-Host "  + extended CSV import for price_per_night and elect_extra"
  } else {
    Write-Host "  = CSV import already handles new fields"
  }
} else {
  Write-Host "  ! $views not found (skipping)" -ForegroundColor Yellow
}

# 3) stays/models.py: add price_per_night (Decimal) and elect_extra (Boolean) to Stay
$models = "stays\models.py"
if (Test-Path $models) {
  Write-Host "[3/7] Patching $models"
  Backup-File $models
  $raw = Get-Content -Raw $models
  if ($raw -match "class\s+Stay\(") {
    $needPrice = $raw -notmatch "\bprice_per_night\s*="
    $needElect = $raw -notmatch "\belect_extra\s*="
    if ($needPrice -or $needElect) {
      $raw = [regex]::Replace(
        $raw,
        "(class\s+Stay\([^\)]*\)\s*:\s*)(.*?)(\r?\n\s*def\s+|\r?\nclass\s+|$)",
        { param($m)
          $head = $m.Groups[1].Value
          $body = $m.Groups[2].Value
          $tail = $m.Groups[3].Value
          if ($needPrice) { $body += "`r`n    price_per_night = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)" }
          if ($needElect) { $body += "`r`n    elect_extra = models.BooleanField(default=False)" }
          return $head + $body + $tail
        },
        'Singleline'
      )
      Set-Content -Path $models -Value $raw -NoNewline
      Write-Host "  + added fields to Stay model"
    } else {
      Write-Host "  = fields already present"
    }
  } else {
    Write-Host "  ! Stay model not found" -ForegroundColor Yellow
  }
} else {
  Write-Host "  ! $models not found (skipping)" -ForegroundColor Yellow
}

# 4) stays/forms.py: ensure fields included (or create basic form)
$forms = "stays\forms.py"
if (Test-Path $forms) {
  Write-Host "[4/7] Patching $forms"
  Backup-File $forms
  $raw = Get-Content -Raw $forms
  if ($raw -notmatch "class\s+StayForm\(") {
@'
from django import forms
from .models import Stay

class StayForm(forms.ModelForm):
    class Meta:
        model = Stay
        fields = "__all__"
'@ | Add-Content -Path $forms
    Write-Host "  + created StayForm (fields='__all__')"
  } else {
    # If explicit fields list exists, append our fields
    $new = [regex]::Replace(
      $raw,
      "(class\s+StayForm\([^\)]*\)\s*:\s*(?:.|\r?\n)*?class\s+Meta\s*:\s*(?:.|\r?\n)*?fields\s*=\s*\[)(.*?)(\])",
      { param($m)
        $pre = $m.Groups[1].Value
        $mid = $m.Groups[2].Value
        $post= $m.Groups[3].Value
        $added = $false
        if ($mid -notmatch "price_per_night") { $mid = $mid.TrimEnd(); if ($mid.Length -gt 0 -and $mid.TrimEnd()[-1] -ne ',') { $mid += ',' }; $mid += " 'price_per_night'"; $added = $true }
        if ($mid -notmatch "elect_extra")     { $mid = $mid.TrimEnd(); if ($mid.Length -gt 0 -and $mid.TrimEnd()[-1] -ne ',') { $mid += ',' }; $mid += " 'elect_extra'"; $added = $true }
        if ($added) { return $pre + $mid + $post } else { return $m.Value }
      },
      'Singleline'
    )
    if ($new -ne $raw) {
      Set-Content -Path $forms -Value $new -NoNewline
      Write-Host "  + appended fields to StayForm"
    } else {
      Write-Host "  = StayForm already includes fields or uses '__all__'"
    }
  }
} else {
  Write-Host "  ! $forms not found (skipping)" -ForegroundColor Yellow
}

# 5) stays/admin.py: ensure admin shows fields
$admin = "stays\admin.py"
if (Test-Path $admin) {
  Write-Host "[5/7] Patching $admin"
  Backup-File $admin
  Ensure-ImportLine -Path $admin -Line "from django.contrib import admin" | Out-Null
  Ensure-ImportLine -Path $admin -Line "from .models import Stay" | Out-Null

  $raw = Get-Content -Raw $admin
  if ($raw -notmatch "@admin\.register\(\s*Stay\s*\)") {
@'
@admin.register(Stay)
class StayAdmin(admin.ModelAdmin):
    list_display = ("park","city","state","check_in","nights","price_per_night","elect_extra","paid")
'@ | Add-Content -Path $admin
    Write-Host "  + registered StayAdmin"
  } else {
    $updated = Replace-Regex -Path $admin -Pattern "(list_display\s*=\s*\()(.*?)(\))" -Replacement {
      param($m)
      $pre = $m.Groups[1].Value; $mid = $m.Groups[2].Value; $post = $m.Groups[3].Value
      if ($mid -notmatch "price_per_night") { $mid = $mid.TrimEnd(); if ($mid[-1] -ne ',') { $mid += ',' }; $mid += " ""price_per_night""" }
      if ($mid -notmatch "elect_extra")     { $mid = $mid.TrimEnd(); if ($mid[-1] -ne ',') { $mid += ',' }; $mid += " ""elect_extra""" }
      return $pre + $mid + $post
    } -SingleLine
    if ($updated) { Write-Host "  + updated list_display" } else { Write-Host "  = admin already shows fields" }
  }
} else {
  Write-Host "  ! $admin not found (skipping)" -ForegroundColor Yellow
}

# 6) templates/stays/stay_list.html: photo size, show price/night, optional stars
$template = "templates\stays\stay_list.html"
if (Test-Path $template) {
  Write-Host "[6/7] Patching $template"
  Backup-File $template
  $raw = Get-Content -Raw $template
  $changed = $false

  if ($raw -notmatch "\.stay-photo") {
    if ($raw -match "</style>") {
      $raw = $raw -replace "</style>", ".stay-photo { width: 160px; height: 120px; object-fit: cover; border-radius: 8px; }`r`n</style>"
    } else {
      $raw = "<style>.stay-photo { width: 160px; height: 120px; object-fit: cover; border-radius: 8px; }</style>`r`n" + $raw
    }
    $changed = $true
    Write-Host "  + added .stay-photo CSS"
  }

  if ($raw -match "stay\.photo") {
    $raw = [regex]::Replace($raw, "<img([^>]+)src=""\{\{\s*stay\.photo[^""]+""\s*>", '<img class="stay-photo"$1src="{{ stay.photo.url }}" alt="{{ stay.park }}">')
    $changed = $true
    Write-Host "  + normalized photo tag"
  }

  if ($raw -notmatch "price_per_night") {
    # Try to add column header and cell
    $raw = [regex]::Replace($raw, "(<tr[^>]*>\s*<th[^>]*>[^<]+</th>)", '$1<th>Price/Night</th>', 'Singleline')
    $raw = [regex]::Replace($raw, "(<tr[^>]*>\s*<td[^>]*>)", '$1{% if stay.price_per_night %}${{ stay.price_per_night }}{% else %}—{% endif %}{% if stay.elect_extra %} <small>(+ elec.)</small>{% endif %}</td>', 'Singleline')
    $changed = $true
    Write-Host "  + added Price/Night column"
  }

  if ($changed) {
    Set-Content -Path $template -Value $raw -NoNewline
  } else {
    Write-Host "  = template already updated"
  }
} else {
  Write-Host "  ! $template not found (skipping)" -ForegroundColor Yellow
}

# 7) Migrate and lint/format
Write-Host "[7/7] Migrations + Ruff + Black"
try {
  python manage.py makemigrations
  python manage.py migrate
} catch {
  Write-Host "  ! migration error: $($_.Exception.Message)" -ForegroundColor Yellow
}

try { ruff --version | Out-Null; ruff check . --fix } catch { Write-Host "  ! install Ruff: python -m pip install ruff" -ForegroundColor Yellow }
try { black --version | Out-Null; black . }        catch { Write-Host "  ! install Black: python -m pip install black" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Done. Run the server:" -ForegroundColor Green
Write-Host "  python manage.py runserver" -ForegroundColor Green
Write-Host "Visit: http://127.0.0.1:8000/stays/" -ForegroundColor Green

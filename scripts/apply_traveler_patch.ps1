
param(
  [string]$RepoRoot = "."
)

function Ensure-Text {
  param([string]$Path, [string]$Content)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Set-Content -Path $Path -Value $Content -Encoding UTF8
  Write-Host "Wrote $Path"
}

function Insert-StaticLink {
  param([string]$Path)
  if (-not (Test-Path $Path)) { Write-Host "Skip: $Path not found" -ForegroundColor Yellow; return }
  $text = Get-Content -Raw -Path $Path

  # Ensure {% load static %}
  if ($text -notmatch '{% *load +static *%}') {
    $text = "{% load static %}`r`n" + $text
  }

  # If site_dark_theme.css link missing, insert before </head>
  if ($text -notmatch "site_dark_theme\\.css") {
    $link = '<link rel="stylesheet" href="{% static ''css/site_dark_theme.css'' %}">'
    if ($text -match '</head>') {
      $text = $text -replace '</head>', ("  " + $link + "`r`n</head>")
    } else {
      # Append near top if no head tag found
      $text = $link + "`r`n" + $text
    }
  }

  Set-Content -Path $Path -Value $text -Encoding UTF8
  Write-Host "Patched CSS link & {% load static %} in $Path"
}

# Resolve repo root
Set-Location $RepoRoot

# 1) Create/overwrite files
Ensure-Text "static/css/site_dark_theme.css" @'
/* Global dark theme */
:root{
  --bg:#0e1117;
  --panel:#111827;
  --muted:#94a3b8;
  --text:#e6e6e6;
  --accent:#3b82f6;
  --accent-2:#22d3ee;
  --border:#1f2937;
  --table-strip:#0b1220;
}
* { box-sizing: border-box; }
html, body { background: var(--bg); color: var(--text); margin: 0;
  font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji"; }
.container { max-width: 1100px; margin: 0 auto; }
.navbar, header, footer { background: var(--panel) !important; color: var(--text) !important; border-bottom: 1px solid var(--border); }
.footer { border-top: 1px solid var(--border); }
.card, .panel, .content, .box { background: var(--panel); color: var(--text); border: 1px solid var(--border); border-radius: 10px; }
a { color: var(--accent); text-decoration: none; } a:hover { color: var(--accent-2); }
.button, button, input[type=submit] { background: var(--accent); color: #0b0f19; border: 0; padding: 8px 14px; border-radius: 8px; cursor: pointer;}
.button:hover, button:hover, input[type=submit]:hover { filter: brightness(1.1); }
input, select, textarea { background: #0b1220 !important; color: var(--text) !important; border: 1px solid var(--border) !important; border-radius: 8px; padding: 8px; }
input::placeholder, textarea::placeholder { color: var(--muted); }
table { width: 100%; border-collapse: collapse; background: var(--panel); color: var(--text); }
th, td { border-bottom: 1px solid var(--border); padding: 8px 10px; }
thead th { text-align: left; font-weight: 600; }
tbody tr:nth-child(odd){ background: var(--table-strip); }
#map { border: 1px solid var(--border); border-radius: 10px; }
'@

Ensure-Text "stays/urls.py" @'
from django.urls import path
from . import views

app_name = "stays"

urlpatterns = [
    path("", views.stay_list, name="list"),
    path("add/", views.stay_add, name="add"),
    path("<int:pk>/edit/", views.stay_edit, name="stay_edit"),
]
'@

Ensure-Text "stays/views.py" @'
from django.shortcuts import render, redirect, get_object_or_404
from django.forms import ModelForm
from .models import Stay

class StayForm(ModelForm):
    class Meta:
        model = Stay
        fields = [
            "photo","park","city","state","check_in","leave","nights",
            "rate_per_night","total","fees","paid","site","rating",
            "elect_extra","latitude","longitude"
        ]

def stay_list(request):
    stays = Stay.objects.all().order_by('-check_in')
    return render(request, 'stays/stay_list.html', {'stays': stays})

def stay_add(request):
    if request.method == 'POST':
        form = StayForm(request.POST, request.FILES)
        if form.is_valid():
            form.save()
            return redirect('stays:list')
    else:
        form = StayForm()
    return render(request, 'stays/stay_form.html', {'form': form, 'mode': 'add'})

def stay_edit(request, pk):
    stay = get_object_or_404(Stay, pk=pk)
    if request.method == 'POST':
        form = StayForm(request.POST, request.FILES, instance=stay)
        if form.is_valid():
            form.save()
            return redirect('stays:list')
    else:
        form = StayForm(instance=stay)
    return render(request, 'stays/stay_form.html', {'form': form, 'mode': 'edit', 'stay': stay})
'@

Ensure-Text "templates/stays/stay_form.html" @'
{% extends "base.html" %}
{% load static %}
{% block content %}
<h1>{% if mode == 'edit' %}Edit Stay{% else %}Add Stay{% endif %}</h1>
<div class="panel" style="padding:16px;">
  <form method="post" enctype="multipart/form-data">
    {% csrf_token %}
    <table>
      {{ form.as_table }}
    </table>
    <div style="margin-top:12px;">
      <button type="submit" class="button">Save</button>
      <a class="button" href="{% url 'stays:list' %}" style="margin-left:8px;">Cancel</a>
    </div>
  </form>
</div>
{% endblock %}
'@

# 2) Patch base.html in-place (non-destructive)
# Try common base names; patch whichever exists
$baseCandidates = @(
  "templates/base.html",
  "templates/_base.html",
  "templates/layouts/base.html"
)
foreach ($b in $baseCandidates) {
  if (Test-Path $b) { Insert-StaticLink $b }
}

Write-Host "Patch apply complete."

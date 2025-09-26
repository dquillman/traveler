# apply_edit_delete_and_state_upper.ps1
$ErrorActionPreference = "Stop"

function Backup-IfExists {
  param([string]$Path)
  if (Test-Path $Path) {
    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    Copy-Item $Path "$Path.bak.$ts" -Force
    Write-Host "Backup: $Path.bak.$ts"
  }
}

function Ensure-Contains {
  param([string]$Path, [string]$Needle, [string]$AppendBlock)
  $txt = Get-Content -Raw -Encoding UTF8 $Path
  if ($txt -notmatch [regex]::Escape($Needle)) {
    Add-Content -Path $Path -Value "`r`n`r`n$AppendBlock" -Encoding UTF8
    Write-Host "Appended block to $Path"
  } else {
    Write-Host "Already present in $Path"
  }
}

# --- 1) Patch models.py: add save() to uppercase state ---
$models = "stays\models.py"
if (-not (Test-Path $models)) { Write-Error "Missing $models"; exit 1 }
Backup-IfExists $models
$modelsTxt = Get-Content -Raw -Encoding UTF8 $models

# Ensure from django.db import models is present (usual)
if ($modelsTxt -notmatch "(?m)^\s*from\s+django\.db\s+import\s+models") {
  $modelsTxt = "from django.db import models`r`n$modelsTxt"
}

# Add/replace save() in class Stay to uppercase state
# Try to inject a save() if class Stay exists but no save() method
$patternStay = "(?ms)^\s*class\s+Stay\s*\(models\.Model\)\s*:(.*?)(?=^\s*class\s+|\Z)"
if ($modelsTxt -match $patternStay) {
  $stayBlock = $matches[0]
  if ($stayBlock -notmatch "(?m)^\s*def\s+save\s*\(") {
    $saveBlock = @'
    def save(self, *args, **kwargs):
        if getattr(self, "state", None):
            self.state = self.state.upper()
        super().save(*args, **kwargs)
'@
    # Insert before end of class
    $updatedStay = $stayBlock.TrimEnd() + "`r`n" + $saveBlock + "`r`n"
    $modelsTxt = $modelsTxt -replace [regex]::Escape($stayBlock), [System.Text.RegularExpressions.Regex]::Escape($updatedStay).Replace("\","\\")
    # The above escape trick keeps content; fallback if weird chars:
    $modelsTxt = $modelsTxt -replace "(?ms)^\s*class\s+Stay\s*\(models\.Model\)\s*:(.*?)(?=^\s*class\s+|\Z)", [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $updatedStay }
    Write-Host "Inserted save() into Stay model to uppercase state."
  } else {
    Write-Host "Stay.save() already present; skipped."
  }
} else {
  Write-Host "Could not find class Stay in models.py — skipping uppercase hook."
}
Set-Content -Path $models -Value $modelsTxt -Encoding UTF8

# --- 2) Patch views.py: ensure stay_delete view exists ---
$views = "stays\views.py"
if (-not (Test-Path $views)) { Write-Error "Missing $views"; exit 1 }
Backup-IfExists $views
$viewsTxt = Get-Content -Raw -Encoding UTF8 $views

# Ensure imports present
if ($viewsTxt -notmatch "(?m)from\s+django\.shortcuts\s+import\s+render") {
  $viewsTxt = "from django.shortcuts import render`r`n$viewsTxt"
}
if ($viewsTxt -notmatch "(?m)from\s+django\.shortcuts\s+import\s+redirect") {
  $viewsTxt = $viewsTxt -replace "(?m)from\s+django\.shortcuts\s+import\s+render.*", '$0, redirect'
  if ($viewsTxt -notmatch "redirect") { $viewsTxt = "from django.shortcuts import redirect`r`n$viewsTxt" }
}
if ($viewsTxt -notmatch "(?m)from\s+django\.shortcuts\s+import\s+.*get_object_or_404") {
  $viewsTxt = $viewsTxt -replace "(?m)from\s+django\.shortcuts\s+import\s+render(,|\s*$)", 'from django.shortcuts import render, get_object_or_404'
  if ($viewsTxt -notmatch "get_object_or_404") { $viewsTxt = "from django.shortcuts import get_object_or_404`r`n$viewsTxt" }
}

Set-Content -Path $views -Value $viewsTxt -Encoding UTF8

$deleteView = @'
def stay_delete(request, pk):
    obj = get_object_or_404(Stay, pk=pk)
    if request.method == "POST":
        obj.delete()
        return redirect("stays:list")
    return render(request, "stays/stay_confirm_delete.html", {"stay": obj})
'@
Ensure-Contains -Path $views -Needle "def stay_delete(" -AppendBlock $deleteView

# --- 3) Patch urls.py: add delete route ---
$urls = "stays\urls.py"
if (-not (Test-Path $urls)) { Write-Error "Missing $urls"; exit 1 }
Backup-IfExists $urls
$urlsTxt = Get-Content -Raw -Encoding UTF8 $urls

if ($urlsTxt -notmatch "(?m)path\(\s*\"<int:pk>/delete/\"\s*,\s*views\.stay_delete") {
  # Insert route just after the edit route if possible
  if ($urlsTxt -match "(?m)path\(\s*\"<int:pk>/edit/\".*\)\s*,?") {
    $urlsTxt = $urlsTxt -replace "(?m)(path\(\s*\"<int:pk>/edit/\".*\)\s*,?)", "`$1`r`n    path(\"<int:pk>/delete/\", views.stay_delete, name=\"delete\"),"
  } else {
    $urlsTxt = $urlsTxt -replace "(?ms)urlpatterns\s*=\s*\[(.*?)\]", { param($m) "urlpatterns = [$($m.Groups[1].Value)`r`n    path(\"<int:pk>/delete/\", views.stay_delete, name=\"delete\"),`r`n]" }
  }
  Set-Content -Path $urls -Value $urlsTxt -Encoding UTF8
  Write-Host "Added delete route to stays/urls.py"
} else {
  Write-Host "Delete route already present in stays/urls.py"
}

# --- 4) Update stay_form.html to include Delete button when editing ---
$tplDir = "templates\stays"
if (-not (Test-Path $tplDir)) { New-Item -ItemType Directory -Path $tplDir -Force | Out-Null }
$tplForm = Join-Path $tplDir "stay_form.html"
Backup-IfExists $tplForm
$formHtml = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>{% if stay %}Edit{% else %}Add{% endif %} Stay</h1>
  <form method="post" class="card">
    {% csrf_token %}
    {{ form.as_p }}
    <button type="submit">Save</button>
  </form>

  {% if stay %}
    <form method="post" action="{% url 'stays:delete' stay.pk %}" style="margin-top:1em;">
      {% csrf_token %}
      <button type="submit" style="color:#ff6b6b;">Delete</button>
    </form>
  {% endif %}
{% endblock %}
'@
Set-Content -Path $tplForm -Value $formHtml -Encoding UTF8
Write-Host "Wrote templates/stays/stay_form.html with Delete button."

# --- 5) Add confirm delete template ---
$tplConfirm = Join-Path $tplDir "stay_confirm_delete.html"
if (-not (Test-Path $tplConfirm)) {
  $confirmHtml = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>Delete Stay</h1>
  <div class="card">
    <p>Are you sure you want to delete: <strong>{{ stay }}</strong>?</p>
    <form method="post">
      {% csrf_token %}
      <button type="submit" style="color:#ff6b6b;">Yes, delete</button>
      <a href="{% url 'stays:edit' stay.pk %}" style="margin-left:12px;">Cancel</a>
    </form>
  </div>
{% endblock %}
'@
  Set-Content -Path $tplConfirm -Value $confirmHtml -Encoding UTF8
  Write-Host "Wrote templates/stays/stay_confirm_delete.html"
} else {
  Write-Host "templates/stays/stay_confirm_delete.html already exists"
}

Write-Host "`nDone. Now restart your server:"
Write-Host "  python manage.py runserver"
Write-Host "Edit page now shows Delete; state will be uppercased on save."

# reset_urls_and_template.ps1
$ErrorActionPreference = 'Stop'

# Ensure stays/urls.py exists
$urlsFile = 'stays\urls.py'
$ts  = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (Test-Path $urlsFile) {
    Copy-Item $urlsFile "$urlsFile.bak.$ts" -Force
    Write-Host "Backup: $urlsFile.bak.$ts"
}

$urlsContent = @'
from django.urls import path
from . import views

app_name = "stays"

urlpatterns = [
    path("", views.stay_list, name="list"),
    path("add/", views.stay_add, name="add"),
    path("<int:pk>/edit/", views.stay_edit, name="edit"),
    path("map-data/", views.stays_map_data, name="map_data"),
]
'@

Set-Content -Path $urlsFile -Value $urlsContent -Encoding UTF8
Write-Host "Wrote clean stays/urls.py"

# Ensure templates/stays folder exists
$templateDir = "templates\stays"
if (-not (Test-Path $templateDir)) {
    New-Item -ItemType Directory -Path $templateDir -Force | Out-Null
    Write-Host "Created $templateDir"
}

# Backup old template if exists
$templateFile = Join-Path $templateDir "stay_list.html"
if (Test-Path $templateFile) {
    Copy-Item $templateFile "$templateFile.bak.$ts" -Force
    Write-Host "Backup: $templateFile.bak.$ts"
}

$templateContent = @'
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Stays</title></head>
  <body>
    <h1>Stays</h1>

    <form method="get">
      <label>State</label>
      <select name="state" multiple>
        {% for s in state_choices %}<option value="{{s}}">{{s}}</option>{% endfor %}
      </select>
      <label>City</label>
      <select name="city" multiple>
        {% for c in city_choices %}<option value="{{c}}">{{c}}</option>{% endfor %}
      </select>
      <label>Rating</label>
      <select name="rating" multiple>
        {% for r in rating_choices %}<option value="{{r}}">{{r}}</option>{% endfor %}
      </select>
      <button type="submit">Filter</button>
    </form>

    <ul>
      {% for stay in stays %}
        <li>{{ stay.city }}, {{ stay.state }}{% if stay.rating %} — {{ stay.rating }}★{% endif %}</li>
      {% empty %}
        <li>No stays yet.</li>
      {% endfor %}
    </ul>
  </body>
</html>
'@

Set-Content -Path $templateFile -Value $templateContent -Encoding UTF8
Write-Host "Wrote minimal templates/stays/stay_list.html"

Write-Host "`nDone. Next step: add include('stays.urls') in your main project urls.py if not already present, then run:"
Write-Host "python manage.py runserver"

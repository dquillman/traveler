# safe_delete_button.ps1 — make Delete a GET link to the confirm page (no immediate delete)
$ErrorActionPreference = 'Stop'
$tpl = 'templates\stays\stay_form.html'
if (-not (Test-Path $tpl)) { Write-Error "Missing $tpl"; exit 1 }

# Backup
$ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
Copy-Item $tpl "$tpl.bak.$ts" -Force
Write-Host "Backup: $tpl.bak.$ts"

# Overwrite with safe version
$content = @'
{% extends "stays/_base_stub.html" %}
{% block content %}
  <h1>{% if stay %}Edit{% else %}Add{% endif %} Stay</h1>

  <form method="post" class="card">
    {% csrf_token %}
    {{ form.as_p }}
    <button type="submit">Save</button>
  </form>

  {% if stay %}
    <p style="margin-top:1em;">
      <a href="{% url 'stays:delete' stay.pk %}" style="color:#ff6b6b;">Delete…</a>
      <!-- This now goes to the confirm page (GET). Actual deletion only happens on POST there. -->
    </p>
  {% endif %}
{% endblock %}
'@

Set-Content -Path $tpl -Value $content -Encoding UTF8
Write-Host "Updated $tpl — Delete now opens a confirmation page first."

Traveler Namespace Fix — Quick Steps
====================================

1) Run the patcher (from your repo root):
   PowerShell (Admin not required):
     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
     .\fix_namespacing.ps1

   This will:
     - Update `{% url 'stays_map_data' %}` → `{% url 'stays:stays_map_data' %}`
     - Replace `{{ map_url }}` → `{% url 'stays:stays_map_data' %}`
     - Create .bak backups next to any changed templates

2) Ensure your app URLs are properly namespaced:
   Copy the example from reference_stays_urls.py into stays/urls.py (adjusting other routes as needed).

3) If your map template still errors, replace the JS map block with:
   stay_list_script_block.html (just the <script> block).

4) Sanity-check the URL reverse:
   python manage.py shell -c "from django.urls import reverse; print(reverse('stays:stays_map_data'))"
   Expected output: /stays/map-data/

5) Restart server:
   python manage.py runserver

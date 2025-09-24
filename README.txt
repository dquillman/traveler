Traveler immediate fix — files included
=======================================

Files:
- templates_stays_stay_list.html  -> replace templates/stays/stay_list.html
- stays_views_stays_map_data.py   -> paste into stays/views.py (overwrites stays_map_data)
- install_traveler_fix.ps1        -> installer that backs up and writes these files

Quick install (PowerShell):
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  .\install_traveler_fix.ps1 -Repo "G:\users\daveq\traveler"

Sanity check:
  python manage.py shell -c "from django.urls import reverse; print(reverse('stays:stays_map_data'))"
  # Expect: /stays/map-data/
  python manage.py runserver

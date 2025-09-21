STAYS MAP UPDATE + BACKFILL COMMAND

Files included:
- stays/models.py (adds latitude/longitude fields)
- stays/utils.py (geocode_city_state using Nominatim)
- stays/views.py (stays_map view that outputs JSON to template)
- templates/stays/map.html (Leaflet map + markers)
- stays/management/commands/backfill_coords.py (management command to backfill coords)
- requirements.txt (adds requests)

Install & migrate:
    venv\Scripts\activate
    pip install -r requirements.txt
    python manage.py makemigrations
    python manage.py migrate

Backfill coordinates:
    python manage.py backfill_coords

Run server:
    python manage.py runserver

Notes:
- Leaflet expects [lat, lng] order.
- Nominatim requires a User-Agent; tweak in stays/utils.py.
- If you rate-limit, re-run the command later.

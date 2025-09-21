Traveler Patch — Auto Lat/Lng (Visible only on Add/Edit)
=======================================================
Date: 2025-09-20

YOUR PROJECT STRUCTURE
----------------------
You confirmed your Django settings live in:
    config/settings.py

So your settings module is:
    config.settings

WHAT THIS PATCH DOES
--------------------
1) Adds latitude/longitude fields to the Stay model via a migration.
2) Auto-geocodes on save using a pre_save signal (so you don't need to modify models.py).
3) Shows Lat/Lng inputs on the Add/Edit stay form (NOT read-only, per your request).
4) Provides a one-time backfill command to geocode existing stays missing coordinates.

FILES
-----
stays/apps.py                      → ensures signals are loaded
stays/signals.py                   → pre_save geocode logic (Nominatim via geopy)
stays/forms.py                     → exposes latitude/longitude on the form
stays/templates/stays/stay_form.html → example form template that includes lat/lng
stays/management/commands/backfill_geocode.py → bulk backfill
stays/migrations/0009_add_lat_lng.py → adds DecimalFields (edit dependency before migrating)

REQUIREMENTS
------------
pip install geopy

In config/settings.py add (or ensure):
GEOCODER_USER_AGENT = "traveler-app"

IMPORTANT: Migration dependency
-------------------------------
Edit stays/migrations/0009_add_lat_lng.py and change the dependency
('stays', '0008_previous_migration')
to the actual LAST migration filename in your stays app.
Example: ('stays', '0007_split_city_state').

HOW TO APPLY
------------
1) Copy the 'stays' folder contents into your Django project (app name 'stays').
   If your app has a different name, adjust import paths accordingly.

2) Update the migration dependency as noted above.

3) Install dependency:
   pip install geopy

4) Migrate:
   python manage.py migrate --settings=config.settings stays

5) Backfill existing records (optional):
   python manage.py backfill_geocode --settings=config.settings

6) Ensure your Add/Edit views use the provided StayForm (or include latitude/longitude
   in your existing form). The provided template shows how to include the fields.

NOTES
-----
• Lat/Lng are NOT read-only (per request). Manual values will be respected.
• The geocoder uses OpenStreetMap Nominatim. Be gentle with rate limits.
• If you already have a custom template, just copy the two fields from stay_form.html.

— Enjoy!

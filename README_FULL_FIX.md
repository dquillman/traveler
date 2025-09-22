
# Traveler Full Fix Bundle

This bundle applies steps 1–5:
1. Serve `/media/` in dev
2. Add a non-destructive navbar include
3. Keep your existing layout; add dark theme CSS
4. Ensure media directories exist
5. Provide a small doctor probe and sample fixture

## Apply

```powershell
git add -A
git commit -m "chore: snapshot before full fix bundle"

Expand-Archive -Path .\traveler_full_fix_bundle.zip -DestinationPath . -Force
powershell -ExecutionPolicy Bypass -File .\scripts\apply_full_fix.ps1 -RepoRoot .

python manage.py makemigrations stays
python manage.py migrate
python manage.py runserver
```

## Doctor probe

```powershell
# optional - requires 'requests' (pip install requests)
python .\scripts\probe_site.py http://127.0.0.1:8000
```

## Load sample pins (optional)

```powershell
# After migrations; this will create 2 stays with coordinates
python manage.py loaddata fixtures\stays_sample.json
python manage.py loaddata fixtures\stays_sample2.json
```

Then visit `/stays/` (map will show pins).

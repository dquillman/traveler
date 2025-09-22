
import os, sys, django

BASE_DIR = os.getcwd()
sys.path.append(BASE_DIR)

settings_module = os.environ.get("DJANGO_SETTINGS_MODULE")
if not settings_module:
    # naive guess; adjust to your project name if needed
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "traveler.settings")

try:
    django.setup()
except Exception as e:
    print(f"[probe] django.setup failed: {e}")
    sys.exit(0)

from django.test import Client
client = Client()

def hit(path):
    try:
        resp = client.get(path)
        print(f"[probe] GET {path} -> {resp.status_code}")
        return resp.status_code
    except Exception as e:
        print(f"[probe] GET {path} exception: {e}")
        return -1

for p in ["/", "/stays/", "/stays/add/","/static/css/style.css","/media/stays_photos/placeholder.jpg"]:
    hit(p)

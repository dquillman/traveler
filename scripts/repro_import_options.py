import os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django
django.setup()

from django.test import Client
from django.conf import settings

c = Client()
try:
    settings.ALLOWED_HOSTS.append('testserver')
except Exception:
    settings.ALLOWED_HOSTS = ['testserver']
resp = c.get('/stays/import/options/')
print('status', resp.status_code)

# Print safely regardless of console encoding
try:
    # Prefer configuring stdout to UTF-8 when available (Py3.7+)
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    text = resp.content[:1200].decode('utf-8', errors='replace')
    print(text)
except Exception:
    # Fallback: write raw bytes
    sys.stdout.buffer.write(resp.content[:1200])

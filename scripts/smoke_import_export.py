import os
import io
import sys
from pathlib import Path

# Ensure project root on sys.path
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django
django.setup()

from django.test import Client
from django.core.files.uploadedfile import SimpleUploadedFile
from stays.models import Stay
from django.conf import settings


def main():
    # Allow test client host
    try:
        settings.ALLOWED_HOSTS.append('testserver')
    except Exception:
        settings.ALLOWED_HOSTS = ['testserver']

    client = Client()

    before = Stay.objects.count()

    csv_text = (
        "Park,City,State,Check in,Leave,Rate/nt,Total,Fees,Paid?,Site,Notes\n"
        "Blue Camp,Austin,TX,2024-03-10,2024-03-12,45.50,91.00,5.00,Yes,B12,Test import 1\n"
        "Green Park,Boise,ID,03/15/2024,03/18/2024,40.00,120.00,0,No,A3,Test import 2\n"
    )
    upload = SimpleUploadedFile(
        "stays.csv", csv_text.encode("utf-8"), content_type="text/csv"
    )
    resp = client.post("/stays/import/", {"file": upload})
    after = Stay.objects.count()

    print("Import status:", resp.status_code)
    print("Created rows:", after - before)

    resp2 = client.get("/stays/export/")
    print("Export status:", resp2.status_code)
    content = resp2.content.decode("utf-8", errors="ignore").splitlines()
    print("Export head:")
    for line in content[:4]:
        print(line)


if __name__ == "__main__":
    main()

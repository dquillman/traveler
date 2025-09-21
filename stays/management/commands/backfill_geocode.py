from django.core.management.base import BaseCommand
from time import sleep
from stays.models import Stay
from stays.utils import build_query_from_stay, geocode_address

class Command(BaseCommand):
    help = "Backfill latitude/longitude for Stay rows missing coordinates using city/state/address."

    def add_arguments(self, parser):
        parser.add_argument('--limit', type=int, default=None, help='Max rows to process')

    def handle(self, *args, **opts):
        qs = Stay.objects.filter(latitude__isnull=True) | Stay.objects.filter(longitude__isnull=True)
        processed = 0
        limit = opts.get('limit')
        for stay in qs.iterator():
            if limit is not None and processed >= limit:
                break
            q = build_query_from_stay(stay)
            if not q:
                continue
            coords = geocode_address(q)
            if coords:
                stay.latitude, stay.longitude = coords
                stay.save(update_fields=['latitude', 'longitude'])
                self.stdout.write(self.style.SUCCESS(f"Geocoded {stay.pk}: {coords}"))
                processed += 1
                sleep(1.2)  # be polite to Nominatim
        self.stdout.write(self.style.NOTICE(f"Done. Updated {processed} row(s)."))
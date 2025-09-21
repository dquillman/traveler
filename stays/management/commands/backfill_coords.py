from django.core.management.base import BaseCommand
from stays.models import Stay
from stays.utils import geocode_city_state

class Command(BaseCommand):
    help = "Backfill missing latitude/longitude for stays using geocode_city_state(city, state)."

    def handle(self, *args, **kwargs):
        qs = Stay.objects.filter(latitude__isnull=True) | Stay.objects.filter(longitude__isnull=True)
        total = qs.count()
        updated = 0
        self.stdout.write(f"Backfilling coordinates for {total} stays...")
        for stay in qs.iterator():
            try:
                lat, lon = geocode_city_state(stay.city, stay.state)
                if lat is not None and lon is not None:
                    stay.latitude = lat
                    stay.longitude = lon
                    stay.save(update_fields=["latitude", "longitude"])
                    updated += 1
                else:
                    self.stderr.write(f"No geocode for Stay(id={stay.id}, '{stay.city}, {stay.state}')")
            except Exception as e:
                self.stderr.write(f"Error on Stay(id={stay.id}): {e}")
        self.stdout.write(self.style.SUCCESS(f"Updated {updated}/{total} stays."))

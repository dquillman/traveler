from django.core.management.base import BaseCommand
from django.conf import settings
from geopy.geocoders import Nominatim
from geopy.extra.rate_limiter import RateLimiter
from stays.models import Stay

class BaseColors:
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    END = "\033[0m"

class Command(BaseCommand):
    help = "Geocode any Stay with missing latitude/longitude using Nominatim (OSM)."

    def handle(self, *args, **options):
        ua = getattr(settings, "GEOCODER_USER_AGENT", "traveler-app")
        geolocator = Nominatim(user_agent=ua)
        geocode = RateLimiter(geolocator.geocode, min_delay_seconds=1)

        qs = Stay.objects.filter(latitude__isnull=True) | Stay.objects.filter(longitude__isnull=True)
        total = qs.count()
        self.stdout.write(f"Scanning {total} stays...")

        for s in qs.iterator():
            addr = ", ".join([v for v in [s.address, s.city, s.state, s.zipcode] if v])
            if not addr:
                self.stdout.write(f"{BaseColors.YELLOW}Skipping (no address):{BaseColors.END} {s.pk} {s.name}")
                continue
            try:
                loc = geocode(addr)
            except Exception as e:
                self.stdout.write(f"{BaseColors.RED}Error:{BaseColors.END} {s.pk} {s.name} → {e}")
                continue

            if loc:
                s.latitude = round(loc.latitude, 6)
                s.longitude = round(loc.longitude, 6)
                s.save(update_fields=["latitude", "longitude"])
                self.stdout.write(f"{BaseColors.GREEN}OK{BaseColors.END}: {s.pk} {s.name} → {s.latitude}, {s.longitude}")
            else:
                self.stdout.write(f"{BaseColors.YELLOW}Not found{BaseColors.END}: {s.pk} {s.name}")

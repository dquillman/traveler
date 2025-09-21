from django.db.models.signals import pre_save
from django.dispatch import receiver
from django.conf import settings

from geopy.geocoders import Nominatim
from geopy.extra.rate_limiter import RateLimiter

from .models import Stay

def _full_address(stay: Stay) -> str:
    parts = [getattr(stay, "address", ""), getattr(stay, "city", ""), getattr(stay, "state", ""), getattr(stay, "zipcode", "")]
    return ", ".join([p for p in parts if p])

@receiver(pre_save, sender=Stay)
def auto_geocode_lat_lng(sender, instance: Stay, **kwargs):
    # If both fields already present, respect manual values
    if instance.latitude is not None and instance.longitude is not None:
        return

    addr = _full_address(instance).strip()
    if not addr:
        return

    geolocator = Nominatim(user_agent=getattr(settings, "GEOCODER_USER_AGENT", "traveler-app"))
    geocode = RateLimiter(geolocator.geocode, min_delay_seconds=1)

    try:
        loc = geocode(addr)
    except Exception:
        loc = None

    if loc:
        # Round to 6 decimal places
        instance.latitude = round(loc.latitude, 6)
        instance.longitude = round(loc.longitude, 6)

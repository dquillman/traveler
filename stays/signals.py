from django.db.models.signals import pre_save
from django.dispatch import receiver
from .models import Stay
from .utils import geocode_from_stay
from django.conf import settings
import re

@receiver(pre_save, sender=Stay)
def stays_autogeocode(sender, instance: Stay, **kwargs):
    if getattr(settings, "DISABLE_AUTO_GEOCODE", False):
        return
    # Normalize state to uppercase
    st = getattr(instance, "state", None)
    if isinstance(st, str):
        instance.state = st.strip().upper()
    # Normalize city by removing trailing ", ST"
    city = getattr(instance, "city", None)
    if isinstance(city, str) and city:
        raw = city.strip()
        # Case 1: "City, ST"
        m = re.search(r"^(.*?),(?:\s*)([A-Za-z]{2})$", raw)
        if m:
            base, suff = m.group(1).strip(), m.group(2).upper()
            if not getattr(instance, "state", ""):  # type: ignore
                instance.state = suff
            instance.city = base
        # Case 2: any comma present -> keep only portion before first comma
        elif "," in raw:
            instance.city = raw.split(",", 1)[0].strip()
        else:
            # Case 3: "City ST" (space + 2-letter) with no comma
            m2 = re.search(r"^(.*)\s+([A-Za-z]{2})$", raw)
            if m2:
                base, suff = m2.group(1).strip(), m2.group(2).upper()
                if not getattr(instance, "state", ""):  # type: ignore
                    instance.state = suff
                instance.city = base

    # Only fill if both coords are missing
    lat_missing = not getattr(instance, "latitude", None)
    lng_missing = not getattr(instance, "longitude", None)
    if not (lat_missing and lng_missing):
        return
    coords = geocode_from_stay(instance)
    if coords:
        instance.latitude, instance.longitude = coords

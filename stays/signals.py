from django.db.models.signals import pre_save
from django.dispatch import receiver
from .models import Stay
from .utils import build_query_from_stay, geocode_address

@receiver(pre_save, sender=Stay)
def stays_autogeocode(sender, instance: Stay, **kwargs):
    # Only fill if both coords are missing
    lat_missing = not getattr(instance, "latitude", None)
    lng_missing = not getattr(instance, "longitude", None)
    if not (lat_missing and lng_missing):
        return
    q = build_query_from_stay(instance)
    if not q:
        return
    coords = geocode_address(q)
    if coords:
        instance.latitude, instance.longitude = coords
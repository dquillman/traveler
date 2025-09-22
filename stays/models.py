from django.core.files.storage import default_storage
from django.conf import settings

class Stay(models.Model):
    # your fields...
    photo = models.ImageField(upload_to="stays_photos/", blank=True, null=True)

    @property
    def photo_url(self):
        candidate = self.photo.name if getattr(self, "photo", None) and self.photo and self.photo.name else None
        if candidate:
            try:
                if default_storage.exists(candidate):
                    return settings.MEDIA_URL + candidate
            except Exception:
                pass
        return settings.MEDIA_URL + "stays_photos/placeholder.jpg"

from django.apps import AppConfig

class StaysConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "stays"

    def ready(self):
        try:
            from .utils.placeholders import ensure_placeholder_image
            ensure_placeholder_image()
        except Exception:
            # avoid crash if Pillow/settings not ready
            pass

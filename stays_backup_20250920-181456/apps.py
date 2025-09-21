from django.apps import AppConfig

class StaysConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "stays"

    def ready(self):
        # Import signal handlers
        from . import signals  # noqa: F401

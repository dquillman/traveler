from django.apps import AppConfig

class StaysConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'stays'

    def ready(self):
        # Wire signals
        from . import signals  # noqa: F401
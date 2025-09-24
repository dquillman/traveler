# reference_stays_urls.py
# Place into your app at: stays/urls.py (replace existing content accordingly)

from django.urls import path
from . import views

app_name = "stays"

urlpatterns = [
    path("map-data/", views.stays_map_data, name="stays_map_data"),
    # ... other routes ...
]

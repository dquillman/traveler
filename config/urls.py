from django.contrib import admin
from django.urls import path, include
from django.views.generic.base import RedirectView

urlpatterns = [
    path('appearance/', RedirectView.as_view(url='/stays/appearance/', permanent=False)),
    path('', RedirectView.as_view(url='/stays/', permanent=False)),
    # Root redirects to the map

    # Optional alias so /map/ works too

    # App routes
    path("stays/", include(("stays.urls", "stays"), namespace="stays")),
    path("admin/", admin.site.urls),
]




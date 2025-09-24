from django.contrib import admin
from django.urls import path, include, reverse_lazy
from django.views.generic.base import RedirectView
from django.shortcuts import render

# Inline view functions. Defining them here avoids dependency on stays.views.
def appearance_view(request):
    """Render the site-wide appearance page."""
    return render(request, "appearance.html")

def import_view(request):
    """Render the import page for stays. Requires templates/stays/import.html."""
    return render(request, "stays/import.html")

def export_view(request):
    """Render the export page for stays. Requires templates/stays/export.html."""
    return render(request, "stays/export.html")

urlpatterns = [
    # Redirect the root URL to the list of stays.
    path('', RedirectView.as_view(url=reverse_lazy('stays:list'), permanent=False)),
    # Standalone pages for appearance, import, and export. These avoid missing attributes on stays.views.
    path('appearance/', appearance_view, name='appearance'),
    path('import/', import_view, name='import'),
    path('export/', export_view, name='export'),
    # Delegate all /stays/ URLs to the stays app.
    path('stays/', include(('stays.urls', 'stays'), namespace='stays')),
    path('admin/', admin.site.urls),
]
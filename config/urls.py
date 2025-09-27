from django.contrib import admin
from django.urls import path, include, reverse_lazy
from django.views.generic.base import RedirectView
from django.views.generic import RedirectView as SimpleRedirect
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('', RedirectView.as_view(url=reverse_lazy('stays:list'), permanent=False)),
    path('stays/', include(('stays.urls', 'stays'), namespace='stays')),
    # Legacy convenience routes used by older templates
    # Send to options pages so users can choose location/behavior interactively
    path('import/', SimpleRedirect.as_view(url=reverse_lazy('stays:import_options'), permanent=False)),
    path('export/', SimpleRedirect.as_view(url=reverse_lazy('stays:export_options'), permanent=False)),
    path('appearance/', SimpleRedirect.as_view(url=reverse_lazy('stays:appearance'), permanent=False)),
    path('admin/', admin.site.urls),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

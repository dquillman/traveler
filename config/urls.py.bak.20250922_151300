from django.contrib import admin
from django.urls import path, include, reverse_lazy
from django.views.generic.base import RedirectView

urlpatterns = [
    path('', RedirectView.as_view(url=reverse_lazy('stays:list'), permanent=False)),
    path('stays/', include(('stays.urls', 'stays'), namespace='stays')),
    path('admin/', admin.site.urls),
]

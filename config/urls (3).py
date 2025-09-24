from django.contrib import admin
from django.urls import path, include, reverse_lazy
from django.views.generic.base import RedirectView

# Import the appearance view from the stays app.
from stays import views as stays_views

urlpatterns = [
    # Redirect the root URL to the list of stays.
    path('', RedirectView.as_view(url=reverse_lazy('stays:list'), permanent=False)),
    # Add an appearance page at the project level. You can remove this if you don't need it.
    path('appearance/', stays_views.appearance_view, name='appearance'),
    # Delegate all /stays/ URLs to the stays app.
    path('stays/', include(('stays.urls', 'stays'), namespace='stays')),
    path('admin/', admin.site.urls),
]
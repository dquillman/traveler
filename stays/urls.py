from django.urls import path
from . import views

app_name = 'stays'

urlpatterns = [
    path('', views.stay_list, name='list'),
    path('add/', views.stay_add, name='add'),
    path('<int:pk>/', views.stay_detail, name='detail'),
    path('<int:pk>/edit/', views.stay_edit, name='edit'),
    path('map/', views.stay_map, name='map'),
    path('map/geocode/', views.geocode_missing, name='map_geocode'),
    path('charts/', views.stay_charts, name='charts'),
    path('import/options/', views.import_stays_options, name='import_options'),
    path('export/options/', views.export_stays_options, name='export_options'),
    # CSV import/export
    path('import/', views.import_stays_csv, name='import_stays_csv'),
    path('export/', views.export_stays_csv, name='export_stays_csv'),
]

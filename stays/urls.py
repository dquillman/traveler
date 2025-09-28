from django.urls import path
from . import views

app_name = 'stays'

urlpatterns = [
    path('', views.stay_list, name='list'),
    path('add/', views.stay_add, name='add'),
    path('<int:pk>/', views.stay_detail, name='detail'),
    path('<int:pk>/edit/', views.stay_edit, name='edit'),
    path('<int:pk>/geocode/', views.stay_geocode, name='geocode'),
    path('<int:pk>/delete/', views.stay_delete, name='delete'),
    path('appearance/', views.appearance_page, name='appearance'),
    path('appearance/geocode/', views.appearance_geocode, name='appearance_geocode'),
    path('appearance/purge/', views.appearance_purge, name='appearance_purge'),
    path('appearance/normalize-cities/', views.appearance_normalize_cities, name='appearance_normalize_cities'),
    path('map/', views.stay_map, name='map'),
    path('map/geocode/', views.geocode_missing, name='map_geocode'),
    path('charts/', views.stay_charts, name='charts'),
    path('import/options/', views.import_stays_options, name='import_options'),
    path('import/probe-sheets/', views.import_probe_sheets, name='import_probe_sheets'),
    path('export/options/', views.export_stays_options, name='export_options'),
    # CSV import/export
    path('import/', views.import_stays_csv, name='import_stays_csv'),
    path('export/', views.export_stays_csv, name='export_stays_csv'),
]

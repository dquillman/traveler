from django.urls import path

from . import views
app_name = 'stays'

urlpatterns = [
    path('', views.stay_list, name='list'),
    path('add/', views.stay_add, name='add'),
    path('<int:pk>/', views.stay_detail, name='detail'),
    path('<int:pk>/edit/', views.stay_edit, name='edit'),
    path('charts/', views.stay_charts, name='charts'),
    path('import/', views.import_view, name='import'),
    path('export/', views.export_view, name='export'),
    path('map/', views.map_page, name='map'),       # new route for the map page
    path('map-data/', views.stays_map_data, name='map_data'),
    path('export/', views.export_home, name='stays_export'),
    path('export/csv/', views.export_stays_csv, name='stays_export_csv'),
    path('export/', views.export_home, name='stays_export'),
    path('export/csv/', views.export_stays_csv, name='stays_export_csv'),
    path('charts/', views.charts_page, name='stays_charts'),
    path('charts/data/', views.stays_chart_data, name='stays_chart_data'),
    path('import/', views.import_stays, name='stays_import'),
    path('map/', views.map_page, name='stays_map'),
    path('map/data/', views.stays_map_data, name='stays_map_data'),
    path('appearance/', views.appearance_page, name='stays_appearance'),
]








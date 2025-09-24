from django.urls import path
from stays import views

app_name = 'stays'

# URL patterns for the Stays app. Fixes malformed paths and exposes proper routes.
urlpatterns = [
    path('', views.stay_list, name='list'),
    path('add/', views.stay_add, name='add'),
    # Detail and edit pages expect an integer primary key.
    path('<int:pk>/', views.stay_detail, name='detail'),
    path('<int:pk>/edit/', views.stay_edit, name='edit'),
    path('map/', views.stay_map, name='map'),
    path('charts/', views.stay_charts, name='charts'),
    # Note: we do not define appearance here; it is mapped at the project level.
]
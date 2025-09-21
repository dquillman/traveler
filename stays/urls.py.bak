from django.urls import path
from . import views

app_name = 'stays'

urlpatterns = [
    path('', views.stay_list, name='list'),
    path('add/', views.stay_add, name='add'),
    path('<int:pk>/', views.stay_detail, name='detail'),
    path('<int:pk>/edit/', views.stay_edit, name='edit'),
    path('map/', views.stay_map, name='map'),
    path('charts/', views.stay_charts, name='charts'),
]

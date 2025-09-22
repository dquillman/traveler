from django.urls import path
from . import views

app_name = "stays"

urlpatterns = [
    path("", views.stay_list, name="list"),
    path("add/", views.stay_add, name="add"),
    path("<int:pk>/edit/", views.stay_edit, name="stay_edit"),
]

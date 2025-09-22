from django.contrib import admin
from .models import Stay

@admin.register(Stay)
class StayAdmin(admin.ModelAdmin):
    list_display = ('id', '__str__')   # Add more once fields are stable
    list_filter = ()
    search_fields = ()

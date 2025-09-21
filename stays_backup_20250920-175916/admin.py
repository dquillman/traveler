from django.contrib import admin
from .models import Stay

@admin.register(Stay)
class StayAdmin(admin.ModelAdmin):
    list_display = ("park","city","state","check_in","leave_date","nights","price_night","total","fees","paid","site")
    list_filter = ("paid","state")
    search_fields = ("park","city","state","site","notes")

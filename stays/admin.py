from django.contrib import admin
from .models import Stay

@admin.register(Stay)
class StayAdmin(admin.ModelAdmin):
    list_display = ('id', '__str__')
    list_filter = ()      # no filters until we confirm field names
    search_fields = ()    # no search until we confirm field names

from django import forms
from .models import Stay

class StayForm(forms.ModelForm):
    class Meta:
        model = Stay
        fields = [
            # Basic location identity fields (keep your existing fields here as needed)
            "name", "address", "city", "state", "zipcode",
            # Lat/Lng — not read-only per request
            "latitude", "longitude",
            # Keep your other fields (e.g., price_per_night, elect_extra, photos, rating, etc.) if they exist
        ]
        widgets = {
            "latitude": forms.NumberInput(attrs={"step": "0.000001", "inputmode": "decimal"}),
            "longitude": forms.NumberInput(attrs={"step": "0.000001", "inputmode": "decimal"}),
        }

from django import forms
from .models import Stay
class StayForm(forms.ModelForm):
    class Meta:
        model = Stay
        fields = "__all__"  # avoid unknown field errors if model differs
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # If latitude/longitude exist, give them decimal-friendly widgets
        for fname in ("latitude", "longitude"):
            if fname in self.fields:
                self.fields[fname].widget = forms.NumberInput(attrs={"step": "0.000001", "inputmode": "decimal"})
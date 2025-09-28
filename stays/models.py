from django.db import models
from decimal import Decimal
from django.core.validators import MinValueValidator, MaxValueValidator


class Stay(models.Model):
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    park = models.CharField(max_length=200, default="", blank=True)
    city = models.CharField(max_length=120, default="", blank=True)
    state = models.CharField(max_length=2, default="", blank=True, help_text="2-letter code")
    check_in = models.DateField(null=True, blank=True)
    leave_date = models.DateField(null=True, blank=True)
    price_night = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True, default=Decimal("0"))
    total = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True, default=Decimal("0"))
    fees = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True, default=Decimal("0"))
    paid = models.BooleanField(default=False)
    site = models.CharField(max_length=50, blank=True, default="")
    notes = models.TextField(blank=True, default="")
    photo = models.ImageField(upload_to="stays_photos/", null=True, blank=True)
    rating = models.IntegerField(null=True, blank=True,
                                 validators=[MinValueValidator(1), MaxValueValidator(5)])

    @property
    def nights(self):
        if self.check_in and self.leave_date:
            return max((self.leave_date - self.check_in).days, 0)
        return 0

    def __str__(self):
        base = self.park or f"Stay #{self.pk}"
        loc = ", ".join([p for p in [self.city, self.state] if p])
        return f"{base} - {loc}" if loc else base


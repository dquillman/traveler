from django.db import models
from decimal import Decimal

class Stay(models.Model):
    # Media
    photo = models.ImageField(upload_to="stays_photos/", null=True, blank=True)

    # Core info
    park = models.CharField(max_length=200, null=True, blank=True)
    city = models.CharField(max_length=100, null=True, blank=True)
    state = models.CharField(max_length=50, null=True, blank=True)

    # Dates
    check_in = models.DateField(null=True, blank=True)
    leave = models.DateField(null=True, blank=True)

    # Numbers / money
    nights = models.IntegerField(null=True, blank=True)  # (# Nts)
    rate_per_night = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)  # Price/Night
    total = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    fees = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    paid = models.BooleanField(default=False)

    # Site & rating
    site = models.CharField(max_length=50, null=True, blank=True)
    rating = models.IntegerField(null=True, blank=True)

    # Extras and location
    elect_extra = models.BooleanField(default=False)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    def __str__(self):
        bits = [self.park or "Stay"]
        if self.city: bits.append(self.city)
        if self.state: bits.append(self.state)
        return " — ".join(filter(None, [" ".join(bits),
                                        f"{self.check_in} → {self.leave}" if self.check_in and self.leave else None]))

    class Meta:
        ordering = ["-check_in"]

    # QoL: auto-calc nights/total if possible
    def save(self, *args, **kwargs):
        try:
            if self.check_in and self.leave:
                delta = (self.leave - self.check_in).days
                if delta >= 0:
                    self.nights = delta
        except Exception:
            pass
        try:
            if self.rate_per_night is not None and self.nights is not None:
                base = Decimal(self.rate_per_night) * Decimal(self.nights)
                self.total = (base + (self.fees or Decimal("0.00"))).quantize(Decimal("0.01"))
        except Exception:
            pass
        super().save(*args, **kwargs)

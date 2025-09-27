from django.db import migrations


class Migration(migrations.Migration):
    # Ensure this runs after the re-add in 0011 to avoid duplicate columns
    dependencies = [
        ('stays', '0011_force_add_lat_lng'),
    ]

    # No-op: previous add/remove churn replaced by 0011 and merged in 0012
    operations = []

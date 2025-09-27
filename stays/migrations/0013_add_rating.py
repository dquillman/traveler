from django.db import migrations, models
import django.core.validators


class Migration(migrations.Migration):
    dependencies = [
        ('stays', '0012_merge_0010_add_lat_lng_fix_0011_force_add_lat_lng'),
    ]

    operations = [
        migrations.AddField(
            model_name='stay',
            name='rating',
            field=models.IntegerField(blank=True, null=True, validators=[django.core.validators.MinValueValidator(1), django.core.validators.MaxValueValidator(5)]),
        ),
    ]


from django.db import migrations, models
class Migration(migrations.Migration):
    dependencies = [
        ('stays', '0011_force_add_lat_lng'),
    ]
    operations = [
        migrations.AddField(
            model_name='stay',
            name='latitude',
            field=models.DecimalField(null=True, blank=True, max_digits=9, decimal_places=6),
        ),
        migrations.AddField(
            model_name='stay',
            name='longitude',
            field=models.DecimalField(null=True, blank=True, max_digits=9, decimal_places=6),
        ),
    ]
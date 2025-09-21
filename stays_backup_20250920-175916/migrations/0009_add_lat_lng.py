from django.db import migrations, models

class Migration(migrations.Migration):

    dependencies = [
        # TODO: replace '0008_previous_migration' with your actual last migration in the stays app
        ('stays', '0008_previous_migration'),
    ]

    operations = [
        migrations.AddField(
            model_name='stay',
            name='latitude',
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
        migrations.AddField(
            model_name='stay',
            name='longitude',
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
    ]

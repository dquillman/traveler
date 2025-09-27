from django.db import migrations, connection


def uppercase_states(apps, schema_editor):
    try:
        with connection.cursor() as cursor:
            cursor.execute("UPDATE stays_stay SET state = UPPER(TRIM(state)) WHERE state IS NOT NULL")
    except Exception:
        # Fallback via ORM if SQL fails
        Stay = apps.get_model('stays', 'Stay')
        for s in Stay.objects.exclude(state__isnull=True):
            if s.state:
                new = s.state.strip().upper()
                if new != s.state:
                    s.state = new
                    s.save(update_fields=['state'])


class Migration(migrations.Migration):
    dependencies = [
        ('stays', '0014_repair_rating_column'),
    ]

    operations = [
        migrations.RunPython(uppercase_states, migrations.RunPython.noop),
    ]


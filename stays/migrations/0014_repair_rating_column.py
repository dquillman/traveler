from django.db import migrations, connection


def ensure_rating_column(apps, schema_editor):
    with connection.cursor() as cursor:
        try:
            cursor.execute("PRAGMA table_info('stays_stay')")
            cols = [row[1] for row in cursor.fetchall()]  # (cid, name, type, ...)
        except Exception:
            cols = []
        if 'rating' not in cols:
            try:
                cursor.execute("ALTER TABLE stays_stay ADD COLUMN rating integer NULL")
            except Exception:
                # If this fails, leave it; the charts view guards against missing column
                pass


class Migration(migrations.Migration):
    dependencies = [
        ('stays', '0013_add_rating'),
    ]

    operations = [
        migrations.RunPython(ensure_rating_column, migrations.RunPython.noop),
    ]


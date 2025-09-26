import os
import tempfile

from django.test import TestCase, override_settings
from django.urls import reverse
from django.core.files.uploadedfile import SimpleUploadedFile

from stays.models import Stay


@override_settings(ALLOWED_HOSTS=["testserver", "localhost"], MIGRATION_MODULES={"stays": None})
class ImportExportTests(TestCase):
    def test_options_pages_load(self):
        r1 = self.client.get(reverse("stays:import_options"))
        r2 = self.client.get(reverse("stays:export_options"))
        self.assertEqual(r1.status_code, 200)
        self.assertEqual(r2.status_code, 200)

    def test_export_basic_download(self):
        Stay.objects.create(park="Blue Camp", city="Austin", state="TX")
        url = reverse("stays:export_stays_csv")
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, 200)
        self.assertIn("text/csv", resp["Content-Type"])  # content type
        text = resp.content.decode("utf-8", errors="ignore")
        self.assertTrue(text.startswith("Park,City,State"))
        self.assertIn("Blue Camp,Austin,TX", text)

    def test_export_save_to_dir(self):
        Stay.objects.create(park="Green Park", city="Boise", state="ID")
        with tempfile.TemporaryDirectory() as tmp:
            with override_settings(EXPORTS_DIR=tmp):
                url = reverse("stays:export_stays_csv") + "?save=1&filename=test.csv&subdir=demo"
                resp = self.client.get(url)
                self.assertEqual(resp.status_code, 200)
                saved = resp.headers.get("X-Saved-To") or resp.get("X-Saved-To")
                self.assertIsNotNone(saved)
                self.assertTrue(saved.startswith(tmp))
                self.assertTrue(os.path.exists(saved))

    def test_import_csv_creates_rows(self):
        csv_text = (
            "Park,City,State,Check in,Leave\n"
            "Blue Camp,Austin,TX,2024-03-10,2024-03-12\n"
            "Green Park,Boise,ID,2024-03-15,2024-03-18\n"
        )
        upload = SimpleUploadedFile("stays.csv", csv_text.encode("utf-8"), content_type="text/csv")
        url = reverse("stays:import_stays_csv")
        resp = self.client.post(url, {"file": upload, "delimiter": ","})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(Stay.objects.count(), 2)

    def test_import_csv_dry_run(self):
        csv_text = (
            "Park,City,State\n"
            "Blue Camp,Austin,TX\n"
        )
        upload = SimpleUploadedFile("stays.csv", csv_text.encode("utf-8"), content_type="text/csv")
        url = reverse("stays:import_stays_csv")
        resp = self.client.post(url, {"file": upload, "delimiter": ",", "dry_run": "1"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(Stay.objects.count(), 0)

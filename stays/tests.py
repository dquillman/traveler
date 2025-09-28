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

    def test_import_dedup_by_key(self):
        from stays.models import Stay
        csv_text = (
            "Park,City,State,Check in,Leave\n"
            "Blue Camp,Austin,TX,2024-03-10,2024-03-12\n"
            "Green Park,Boise,ID,2024-05-01,2024-05-03\n"
        )
        upload = SimpleUploadedFile("stays.csv", csv_text.encode("utf-8"), content_type="text/csv")
        url = reverse("stays:import_stays_csv")
        resp1 = self.client.post(url, {"file": upload, "delimiter": ","})
        self.assertEqual(resp1.status_code, 200)
        self.assertEqual(Stay.objects.count(), 2)
        # Import same again; count should remain 2
        upload2 = SimpleUploadedFile("stays.csv", csv_text.encode("utf-8"), content_type="text/csv")
        resp2 = self.client.post(url, {"file": upload2, "delimiter": ","})
        self.assertEqual(resp2.status_code, 200)
        self.assertEqual(Stay.objects.count(), 2)


class RoutesSmokeTests(TestCase):
    def test_root_redirects_to_stays_list(self):
        resp = self.client.get("/")
        self.assertIn(resp.status_code, (301, 302))
        target = reverse("stays:list")
        self.assertTrue(
            resp.headers.get("Location", "").endswith(target),
            msg=f"Expected redirect to {target}, got {resp.headers.get('Location')}",
        )

    def test_stays_list_ok(self):
        url = reverse("stays:list")
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, 200)
        # Ensure no inline rating forms exist on the list page
        self.assertNotIn("/rate/", resp.content.decode("utf-8", errors="ignore"))

    def test_named_urls_resolve(self):
        names = [
            "stays:list",
            "stays:add",
            "stays:appearance",
            "stays:map",
            "stays:charts",
            "stays:import_options",
            "stays:export_options",
            "stays:import_stays_csv",
            "stays:export_stays_csv",
        ]
        for name in names:
            with self.subTest(name=name):
                reverse(name)


from django.test import override_settings


@override_settings(DISABLE_AUTO_GEOCODE=True)
class FilteringTests(TestCase):
    def setUp(self):
        from stays.models import Stay
        from datetime import date
        Stay.objects.create(park="Blue Camp", city="Austin", state="TX", check_in=date(2024,3,10), leave_date=date(2024,3,12), price_night=50, paid=True, rating=5)
        Stay.objects.create(park="Green Park", city="Boise", state="ID", check_in=date(2024,5,1), leave_date=date(2024,5,3), price_night=30, paid=False, rating=3)

    def test_search_q(self):
        url = reverse("stays:list") + "?q=Austin"
        resp = self.client.get(url)
        self.assertContains(resp, "Blue Camp")
        self.assertNotContains(resp, "Green Park")

    def test_filter_state(self):
        url = reverse("stays:list") + "?state=TX"
        resp = self.client.get(url)
        self.assertContains(resp, "Blue Camp")
        self.assertNotContains(resp, "Green Park")
        # City choices should only include Austin when TX selected
        html = resp.content.decode("utf-8", errors="ignore")
        self.assertIn('option value="Austin"', html)
        self.assertNotIn('option value="Boise"', html)

    def test_filter_rating(self):
        url = reverse("stays:list") + "?rating=5"
        resp = self.client.get(url)
        self.assertContains(resp, "Blue Camp")
        self.assertNotContains(resp, "Green Park")

    def test_filter_paid(self):
        url = reverse("stays:list") + "?paid=0"
        resp = self.client.get(url)
        self.assertContains(resp, "Green Park")
        self.assertNotContains(resp, "Blue Camp")

    def test_filter_missing_coords(self):
        from stays.models import Stay
        # Create one with coords and one without
        Stay.objects.create(park="No Coords", city="Elgin", state="IL", latitude=None, longitude=None)
        Stay.objects.create(park="Has Coords", city="Elgin", state="IL", latitude=42.03, longitude=-88.28)
        url = reverse("stays:list") + "?missing_coords=1"
        resp = self.client.get(url)
        self.assertContains(resp, "No Coords")
        self.assertNotContains(resp, "Has Coords")

    def test_filter_date_range(self):
        # Only Boise stay falls within May window
        url = reverse("stays:list") + "?start=2024-05-01&end=2024-05-31"
        resp = self.client.get(url)
        self.assertContains(resp, "Green Park")
        self.assertNotContains(resp, "Blue Camp")

    def test_filter_year(self):
        # Year filter should include either check_in or leave_date years
        url = reverse("stays:list") + "?year=2024"
        resp = self.client.get(url)
        self.assertContains(resp, "Blue Camp")
        self.assertContains(resp, "Green Park")
        # A non-existing year should show none
        resp2 = self.client.get(reverse("stays:list") + "?year=1999")
        self.assertNotContains(resp2, "Blue Camp")
        self.assertNotContains(resp2, "Green Park")

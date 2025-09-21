from django.core.management.base import BaseCommand
from django.conf import settings
from django.urls import reverse, NoReverseMatch
from pathlib import Path
class Command(BaseCommand):
    help = "Doctor Natashia: quick UI diagnostic (templates, navbar include, static file, and URL names)."
    def handle(self, *args, **options):
        base_dir = Path(getattr(settings, 'BASE_DIR', Path.cwd()))
        ok = True
        def say(status, msg):
            prefix = "✅" if status else "❌"
            self.stdout.write(f"{prefix} {msg}")
        base_tpl = base_dir / "templates" / "base.html"
        nav_tpl = base_dir / "templates" / "partials" / "navbar.html"
        say(base_tpl.exists(), f"templates/base.html exists at {base_tpl}")
        ok &= base_tpl.exists()
        say(nav_tpl.exists(), f"templates/partials/navbar.html exists at {nav_tpl}")
        ok &= nav_tpl.exists()
        if base_tpl.exists():
            content = base_tpl.read_text(encoding="utf-8", errors="ignore")
            has_include = '{% include "partials/navbar.html" %}' in content
            say(has_include, "base.html includes partials/navbar.html")
            ok &= has_include
        static_css = base_dir / "static" / "css" / "style.css"
        say(static_css.exists(), f"static/css/style.css present at {static_css}")
        ok &= static_css.exists()
        for name in ["stays:list", "stays:add", "stays:map", "stays:charts"]:
            try:
                reverse(name)
                say(True, f"URL name '{name}' resolves")
            except NoReverseMatch:
                say(False, f"URL name '{name}' DOES NOT resolve")
                ok = False
        if ok:
            self.stdout.write("\nAll good. If UI still looks off, open DevTools (F12) → Network → confirm /static/css/style.css = 200.")
        else:
            self.stdout.write("\nSome checks failed. Fix the ❌ items and re-run: python manage.py doctor_natashia")

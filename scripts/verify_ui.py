
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
base_html = ROOT / "templates" / "base.html"
static_css = ROOT / "static" / "css" / "style.css"
settings_py = ROOT / "config" / "settings.py"

errors = []

if not base_html.exists():
    errors.append("templates/base.html is missing")
else:
    txt = base_html.read_text(encoding="utf-8")
    if "cdn.tailwindcss.com" not in txt:
        errors.append("base.html missing Tailwind CDN (guard against blank UI)")
    if "css/style.css" not in txt:
        errors.append("base.html missing static css/style.css link")
    for name in ["stays:list","stays:add","stays:map","stays:charts"]:
        if name not in txt:
            errors.append(f"base.html nav missing {name} link (or pattern changed)")

if not static_css.exists():
    errors.append("static/css/style.css is missing")

if not settings_py.exists():
    errors.append("config/settings.py missing")
else:
    s = settings_py.read_text(encoding="utf-8")
    if "django.contrib.staticfiles" not in s: errors.append("settings.py missing django.contrib.staticfiles")
    if "STATIC_URL" not in s: errors.append("settings.py missing STATIC_URL")
    if "STATICFILES_DIRS" not in s: errors.append("settings.py missing STATICFILES_DIRS")

if errors:
    print("UI VERIFY ❌:")
    for e in errors: print(" -", e)
    sys.exit(1)
else:
    print("UI VERIFY ✅ All good!")

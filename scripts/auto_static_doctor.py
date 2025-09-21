
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # project root when placed in scripts/
settings_py = ROOT / "config" / "settings.py"
static_dir = ROOT / "static" / "css"
style_css = static_dir / "style.css"

def ensure_static_css():
    static_dir.mkdir(parents=True, exist_ok=True)
    if not style_css.exists():
        style_css.write_text("/* placeholder so 404s stop; Tailwind handles most UI */\n", encoding="utf-8")
        print("• Created static/css/style.css")
    else:
        print("• Found static/css/style.css")

def patch_settings():
    if not settings_py.exists():
        print("⚠ settings.py not found:", settings_py)
        return
    txt = settings_py.read_text(encoding="utf-8")
    changed = False

    if "django.contrib.staticfiles" not in txt:
        txt = re.sub(r"(INSTALLED_APPS\s*=\s*\[)", r"\1\n    'django.contrib.staticfiles',", txt, count=1)
        print("• Added django.contrib.staticfiles to INSTALLED_APPS"); changed = True

    if "STATIC_URL" not in txt:
        txt += "\n\nSTATIC_URL = '/static/'\n"
        print("• Added STATIC_URL = '/static/'"); changed = True

    if "STATICFILES_DIRS" not in txt:
        if "BASE_DIR" not in txt:
            txt = "from pathlib import Path\nBASE_DIR = Path(__file__).resolve().parent.parent\n\n" + txt
            print("• Inserted BASE_DIR definition"); changed = True
        txt += "\nSTATICFILES_DIRS = [BASE_DIR / 'static']\n"
        print("• Added STATICFILES_DIRS = [BASE_DIR / 'static']"); changed = True
    else:
        if "BASE_DIR / 'static'" not in txt and 'BASE_DIR / "static"' not in txt:
            txt = re.sub(r"(STATICFILES_DIRS\s*=\s*\[)([^\]]*)\]", r"\1\2, BASE_DIR / 'static']", txt, count=1)
            print("• Appended BASE_DIR / 'static' to STATICFILES_DIRS"); changed = True

    if changed:
        backup = settings_py.with_suffix(".py.bak")
        backup.write_text(settings_py.read_text(encoding="utf-8"), encoding="utf-8")
        settings_py.write_text(txt, encoding="utf-8")
        print(f"• Backed up settings.py → {backup.name} and wrote changes")
    else:
        print("• settings.py already OK")

def main():
    ensure_static_css()
    patch_settings()
    print("\nNow run:")
    print("  venv\\Scripts\\python.exe manage.py findstatic css/style.css")
    print("  venv\\Scripts\\python.exe manage.py runserver")

if __name__ == '__main__':
    main()

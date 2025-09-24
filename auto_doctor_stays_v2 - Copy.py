# auto_doctor_stays_v2.py
"""
Auto-Doctor (stays) v2
- Scrubs stray references to stay_views / stays.views from config/urls.py
- Normalizes root to a single include(('stays.urls', 'stays'), namespace='stays')
- Ensures stays/urls.py exposes the expected routes and names
- Idempotent (safe to re-run)

Usage:
    venv\Scripts\python.exe auto_doctor_stays_v2.py
"""

from __future__ import annotations
from pathlib import Path
import re
import sys

PROJECT_ROOT = Path(__file__).resolve().parent
CONFIG_URLS = PROJECT_ROOT / "config" / "urls.py"
STAYS_URLS  = PROJECT_ROOT / "stays" / "urls.py"

EXPECTED_STAYS = [
    ("",                "stay_list",   "list"),
    ("map/",            "stay_map",    "map"),
    ("add/",            "stay_add",    "add"),
    ("<int:pk>/",       "stay_detail", "detail"),
    ("<int:pk>/edit/",  "stay_edit",   "edit"),
    ("charts/",         "stay_charts", "charts"),
]

INCLUDE_LINE = "path('stays/', include(('stays.urls', 'stays'), namespace='stays')),"


def normalize_imports(txt: str) -> str:
    """Ensure django.urls imports include both path and include."""
    # Ensure django.urls import exists and has both path, include
    if "from django.urls import" not in txt:
        txt = "from django.urls import path, include\n" + txt
    else:
        # Add missing names into the import line
        def fix_import(m):
            items = [x.strip() for x in m.group(1).split(",")]
            want = {"path", "include"}
            have = set(items)
            items += sorted(list(want - have))
            # Deduplicate and keep order
            dedup = []
            seen = set()
            for it in items:
                if it and it not in seen:
                    dedup.append(it)
                    seen.add(it)
            return "from django.urls import " + ", ".join(dedup)
        txt = re.sub(r"from\s+django\.urls\s+import\s+([^\n]+)", fix_import, txt, count=1)
    return txt


def scrub_stray_stayviews(txt: str) -> str:
    """Remove any direct import/usage of stay_views or stays.views in root urls."""
    before = txt

    # Remove imports like:
    #   from stays import views as stay_views
    #   from stays import views
    #   import stays.views as stay_views
    #   import stays.views
    txt = re.sub(r'^\s*from\s+stays\s+import\s+views(?:\s+as\s+\w+)?\s*$', '', txt, flags=re.MULTILINE)
    txt = re.sub(r'^\s*import\s+stays\.views(?:\s+as\s+\w+)?\s*$', '', txt, flags=re.MULTILINE)

    # Remove any path(...) line that references stay_views or stays.views
    # (handles common single-line cases)
    txt = re.sub(r'^\s*path\([^#\n]*?(stay_views|stays\.views)[^#\n]*\)\s*,?\s*$',
                 '', txt, flags=re.MULTILINE)

    # Also remove short top-level aliases like:
    #   path("stay/<int:pk>/", stay_views.stay_detail, ...)
    #   path("map/", stay_views.stays_map, ...)
    # This is already covered by the regex above, but we add a second pass
    # that trims now-empty lines and extra commas.
    txt = re.sub(r'\n{3,}', '\n\n', txt)

    # Ensure urlpatterns exists
    if "urlpatterns" not in txt:
        txt += "\nurlpatterns = []\n"

    # Ensure SINGLE correct include present
    if INCLUDE_LINE not in txt:
        txt = re.sub(
            r"urlpatterns\s*=\s*\[\s*",
            lambda m: m.group(0) + "\n    " + INCLUDE_LINE + "\n",
            txt, count=1
        )

    # Optionally remove any other stays/* include duplicates
    lines = txt.splitlines()
    cleaned = []
    seen_include = False
    for line in lines:
        if INCLUDE_LINE in line.strip():
            if seen_include:
                # skip duplicates
                continue
            seen_include = True
        cleaned.append(line)
    txt = "\n".join(cleaned)

    # Tidy multiple blank lines
    txt = re.sub(r'\n{3,}', '\n\n', txt)

    return txt


def patch_config_urls(path: Path) -> bool:
    if not path.exists():
        print(f"[Auto-Doctor] Missing {path}")
        return False
    original = path.read_text(encoding="utf-8")
    txt = original

    txt = normalize_imports(txt)
    txt = scrub_stray_stayviews(txt)

    if txt != original:
        path.write_text(txt, encoding="utf-8")
        print("• Patched config/urls.py")
        return True
    else:
        print("✓ config/urls.py already normalized")
        return False


def ensure_stays_urls(path: Path) -> bool:
    """Create or ensure stays/urls.py with expected entries."""
    header = "from django.urls import path\nfrom . import views\n\napp_name = 'stays'\n\nurlpatterns = [\n"
    footer = "]\n"
    lines = [f"    path('{p}', views.{v}, name='{n}'),\n" for p, v, n in EXPECTED_STAYS]
    desired = header + "".join(lines) + footer

    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(desired, encoding="utf-8")
        print("• Created stays/urls.py")
        return True

    txt = path.read_text(encoding="utf-8")
    changed = False

    # If missing required imports/app_name or too different, overwrite with desired
    if "from . import views" not in txt or "app_name" not in txt or "urlpatterns" not in txt:
        path.write_text(desired, encoding="utf-8")
        print("• Rewrote stays/urls.py (normalize imports/app_name/urlpatterns)")
        return True

    # Ensure each expected entry exists; append missing ones
    for ptn, view, name in EXPECTED_STAYS:
        marker = f"path('{ptn}', views.{view}, name='{name}')"
        if marker not in txt:
            # Insert before closing bracket of urlpatterns
            txt = re.sub(r"\]\s*$", f"    path('{ptn}', views.{view}, name='{name}'),\n]\n", txt, count=1)
            changed = True

    if changed:
        path.write_text(txt, encoding="utf-8")
        print("• Updated stays/urls.py (added missing routes)")
    else:
        print("✓ stays/urls.py OK")
    return changed


def main():
    any_change = False
    any_change |= patch_config_urls(CONFIG_URLS)
    any_change |= ensure_stays_urls(STAYS_URLS)

    print("\nNext steps:")
    print("  1) venv\\Scripts\\python.exe verify_stays_setup.py -v")
    print("  2) venv\\Scripts\\python.exe manage.py runserver")

    if any_change:
        sys.exit(0)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()

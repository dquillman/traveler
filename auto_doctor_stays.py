#!/usr/bin/env python
# auto_doctor_stays.py
"""
One-shot "Auto-Doctor" for the 'stays' app routing.
- Normalizes config/urls.py (removes stray stay_views.* routes; keeps the namespaced include).
- Ensures stays/urls.py has the expected routes.
- Prints a short report and suggested next commands.

USAGE (from project root):
    venv\Scripts\python.exe auto_doctor_stays.py
"""

from __future__ import annotations
from pathlib import Path
import re
import sys

PROJECT_ROOT = Path(__file__).resolve().parent
CONFIG_URLS = PROJECT_ROOT / "config" / "urls.py"
STAYS_URLS  = PROJECT_ROOT / "stays" / "urls.py"

# Expected stays url names and their callables
EXPECTED_STAYS_PATTERNS = [
    ("",             "stay_list",  "list"),
    ("map/",         "stay_map",   "map"),
    ("add/",         "stay_add",   "add"),
    ("<int:pk>/",    "stay_detail","detail"),
    ("<int:pk>/edit/","stay_edit", "edit"),
    ("charts/",      "stay_charts","charts"),
]

def patch_config_urls(path: Path) -> tuple[bool, str]:
    if not path.exists():
        return False, f"Missing {path}"
    txt = path.read_text(encoding="utf-8")

    before = txt

    # 1) Ensure import lines
    if "from django.contrib import admin" not in txt:
        txt = "from django.contrib import admin\n" + txt
    if "from django.urls import path, include" not in txt:
        # handle case where only path is imported
        if "from django.urls import path" in txt and "include" not in txt:
            txt = txt.replace("from django.urls import path", "from django.urls import path, include")
        elif "from django.urls import include" in txt and "path" not in txt:
            txt = txt.replace("from django.urls import include", "from django.urls import path, include")
        elif "from django.urls import" not in txt:
            txt = "from django.urls import path, include\n" + txt

    # 2) Nuke any direct references to stay_views.*
    #    e.g. path("stays/new/", stay_views.stay_create, ...)
    txt = re.sub(r"^\s*from\s+stays\s+import\s+views\s+as\s+stay_views\s*\n", "", txt, flags=re.MULTILINE)
    txt = re.sub(r"^\s*from\s+stays\s+import\s+views\s*\n", "", txt, flags=re.MULTILINE)
    txt = re.sub(r'^\s*path\(\s*["\']stays/.*?\)\s*,?\s*$', "", txt, flags=re.MULTILINE)

    # 3) Ensure urlpatterns exists
    if "urlpatterns" not in txt:
        txt += "\nurlpatterns = []\n"

    # 4) Inject the single, correct include if missing
    include_line = "path('stays/', include(('stays.urls', 'stays'), namespace='stays')),"
    if include_line not in txt:
        # Try to insert right after urlpatterns = [
        pattern = r"urlpatterns\s*=\s*\[\s*"
        if re.search(pattern, txt):
            txt = re.sub(pattern, lambda m: m.group(0) + "\n    " + include_line + "\n", txt, count=1)
        else:
            # fallback: append full block
            txt += f"\nurlpatterns = [\n    {include_line}\n]\n"

    changed = (txt != before)
    if changed:
        path.write_text(txt, encoding="utf-8")
    return changed, "config/urls.py normalized"

def ensure_stays_urls(path: Path) -> tuple[bool, str]:
    """
    Make sure stays/urls.py exports the expected names and callables.
    If file doesn't exist, create it.
    If exists, ensure entries are present (idempotent).
    """
    header = "from django.urls import path\nfrom . import views\n\napp_name = 'stays'\n\nurlpatterns = [\n"
    footer = "]\n"
    lines = []
    for pattern, view, name in EXPECTED_STAYS_PATTERNS:
        lines.append(f"    path('{pattern}', views.{view}, name='{name}'),\n")
    desired = header + "".join(lines) + footer

    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(desired, encoding="utf-8")
        return True, "stays/urls.py created"

    txt = path.read_text(encoding="utf-8")
    changed = False

    # Ensure imports and app_name
    if "from . import views" not in txt or "app_name" not in txt:
        txt = desired
        changed = True
    else:
        # Ensure each expected line exists; append missing ones in-place
        for pattern, view, name in EXPECTED_STAYS_PATTERNS:
            expected_line = f"path('{pattern}', views.{view}, name='{name}')"
            if expected_line not in txt:
                # Try to insert before closing bracket of urlpatterns
                txt = re.sub(r"urlpatterns\s*=\s*\[\s*", lambda m: m.group(0), txt)
                txt = re.sub(r"\]\s*$", f"    path('{pattern}', views.{view}, name='{name}'),\n]\n", txt, count=1)
                changed = True

    if changed:
        path.write_text(txt, encoding="utf-8")
    return changed, "stays/urls.py ensured"

def main():
    print("=== Auto-Doctor (stays) ===")

    chg1, msg1 = patch_config_urls(CONFIG_URLS)
    print(("• " if chg1 else "✓ ") + msg1)

    chg2, msg2 = ensure_stays_urls(STAYS_URLS)
    print(("• " if chg2 else "✓ ") + msg2)

    print("\nNext steps:")
    print("  1) venv\\Scripts\\python.exe verify_stays_setup.py -v")
    print("  2) venv\\Scripts\\python.exe manage.py runserver")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(\"[Auto-Doctor] Error:\", e)
        sys.exit(1)

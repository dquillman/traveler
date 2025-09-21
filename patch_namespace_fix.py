import re
import os
import sys
from datetime import datetime
from pathlib import Path

PROJECT_ROOT = Path.cwd()  # run from your project root (same folder as manage.py)
CONFIG_URLS = PROJECT_ROOT / "config" / "urls.py"
STAYS_URLS  = PROJECT_ROOT / "stays" / "urls.py"
TEMPLATE_DIRS = [
    PROJECT_ROOT / "stays" / "templates",
    PROJECT_ROOT / "templates",
]

def backup(path: Path):
    if not path.exists():
        return
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    bak = path.with_suffix(path.suffix + f".{ts}.bak")
    bak.write_bytes(path.read_bytes())

def ensure_include_import(text: str) -> str:
    # Ensure "from django.urls import include, path" (add include if missing)
    pat = r'from\s+django\.urls\s+import\s+([^\n]+)'
    m = re.search(pat, text)
    if not m:
        # add a fresh import at top
        return 'from django.urls import include, path\n' + text
    existing = m.group(1)
    parts = [p.strip() for p in existing.split(',')]
    changed = False
    if 'path' not in parts:
        parts.append('path'); changed = True
    if 'include' not in parts:
        parts.append('include'); changed = True
    if changed:
        new_line = 'from django.urls import ' + ', '.join(sorted(set(parts))) + '\n'
        text = re.sub(pat, new_line, text, count=1)
    return text

def ensure_stays_include(text: str) -> str:
    # Add include(("stays.urls", "stays"), namespace="stays") if missing
    if 'namespace="stays"' in text or "namespace='stays'" in text:
        return text
    # Try to insert inside urlpatterns list
    urlpatterns_pat = r'urlpatterns\s*=\s*\['
    if re.search(urlpatterns_pat, text):
        insert = '    path("stays/", include(("stays.urls", "stays"), namespace="stays")),\n'
        text = re.sub(urlpatterns_pat, lambda m: m.group(0) + "\n" + insert, text, count=1)
    else:
        # Fallback: append a fresh urlpatterns
        block = '\n\nurlpatterns = [\n    path("stays/", include(("stays.urls", "stays"), namespace="stays")),\n]\n'
        text += block
    return text

def write_if_changed(path: Path, new_text: str, changed_files: list):
    old = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    if old != new_text:
        backup(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(new_text, encoding="utf-8", newline="\n")
        changed_files.append(str(path))

def create_or_update_stays_urls(changed_files: list):
    template = (
        "from django.urls import path\n"
        "from . import views\n\n"
        "app_name = \"stays\"\n\n"
        "urlpatterns = [\n"
        "    path(\"\", views.stay_list, name=\"list\"),\n"
        "    path(\"add/\", views.stay_add, name=\"add\"),\n"
        "    path(\"<int:pk>/\", views.stay_detail, name=\"detail\"),\n"
        "    path(\"<int:pk>/edit/\", views.stay_edit, name=\"edit\"),\n"
        "]\n"
    )

    if not STAYS_URLS.exists():
        write_if_changed(STAYS_URLS, template, changed_files)
        return

    # Update existing: ensure app_name present
    text = STAYS_URLS.read_text(encoding="utf-8", errors="replace")
    if 'app_name' not in text:
        # insert app_name after imports
        text = re.sub(r'(\nfrom\s+\.?\s*import\s*views[^\n]*\n|\nfrom\s+django\.urls[^\n]*\n[^\n]*\n)*', 
                      lambda m: m.group(0) + '\napp_name = "stays"\n\n',
                      text, count=1)
    # Ensure at least one named pattern exists; if none, append our defaults
    if 'name=' not in text:
        text = text.rstrip() + "\n\n" + template

    write_if_changed(STAYS_URLS, text, changed_files)

def update_config_urls(changed_files: list):
    if not CONFIG_URLS.exists():
        print(f"[WARN] {CONFIG_URLS} not found; skipped.", file=sys.stderr)
        return
    text = CONFIG_URLS.read_text(encoding="utf-8", errors="replace")
    text2 = ensure_include_import(text)
    text2 = ensure_stays_include(text2)
    write_if_changed(CONFIG_URLS, text2, changed_files)

def clean_templates(changed_files: list):
    targets = []
    for base in TEMPLATE_DIRS:
        if not base.exists():
            continue
        for p in base.rglob("*.html"):
            targets.append(p)

    for p in targets:
        raw = p.read_bytes()
        # Remove leading BOM if any
        if raw.startswith(b'\xef\xbb\xbf'):
            raw = raw[len(b'\xef\xbb\xbf'):]
        text = raw.decode('utf-8', errors='replace')
        new_text = text.replace('\uFFFD', '')  # drop replacement char
        if new_text != text:
            backup(p)
            p.write_text(new_text, encoding='utf-8', newline="\n")
            changed_files.append(str(p))

def main():
    changed = []
    create_or_update_stays_urls(changed)
    update_config_urls(changed)
    clean_templates(changed)
    if changed:
        print("Patched files:")
        for c in changed:
            print(" -", c)
    else:
        print("No changes were necessary. (Already configured.)")

if __name__ == "__main__":
    main()
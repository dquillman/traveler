import re
from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path.cwd()
CONFIG_DIR = PROJECT_ROOT / "config"
CONFIG_URLS = CONFIG_DIR / "urls.py"
STAYS_URLS = PROJECT_ROOT / "stays" / "urls.py"

def ts():
    return datetime.now().strftime("%Y%m%d-%H%M%S")

def backup(p: Path):
    if p.exists():
        p.with_suffix(p.suffix + f".{ts()}.bak").write_bytes(p.read_bytes())

def read_text(p: Path):
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""

def write_text(p: Path, s: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding="utf-8", newline="\n")

def normalize_config_urls():
    text = read_text(CONFIG_URLS)

    if not text:
        # create minimal config/urls.py if missing
        text = (
            "from django.contrib import admin\n"
            "from django.urls import include, path\n\n"
            "urlpatterns = [\n"
            "    path('admin/', admin.site.urls),\n"
            "    path('stays/', include((\"stays.urls\", \"stays\"), namespace='stays')),\n"
            "]\n"
        )
        write_text(CONFIG_URLS, text)
        return True

    backup(CONFIG_URLS)

    # Ensure imports
    if "from django.contrib import admin" not in text:
        text = "from django.contrib import admin\n" + text
    if "from django.urls" in text:
        text = re.sub(
            r"from\s+django\.urls\s+import\s+([^\n]+)",
            lambda m: "from django.urls import " + ", ".join(sorted(set([*(x.strip() for x in m.group(1).split(',')), "include", "path"]))),
            text,
            count=1
        )
    else:
        text = "from django.urls import include, path\n" + text

    # Remove any include of config.urls (self-include)
    text = re.sub(r'.*include\(\s*[\'"]config\.urls[\'"].*\)\s*,?\s*\n', "", text)

    # Build a clean urlpatterns
    # Remove existing stays includes; we'll re-add one canonical line
    text = re.sub(r'.*include\(\s*\(\s*[\'"]stays\.urls[\'"]\s*,\s*[\'"]stays[\'"]\s*\)\s*,\s*namespace\s*=\s*[\'"]stays[\'"]\s*\).*\n', "", text)
    text = re.sub(r'.*include\(\s*[\'"]stays\.urls[\'"].*\)\s*,?\s*\n', "", text)

    # Ensure urlpatterns block exists
    if "urlpatterns" not in text:
        text += "\nurlpatterns = []\n"

    # Inject canonical stays include at the top of urlpatterns list
    text = re.sub(
        r"urlpatterns\s*=\s*\[",
        "urlpatterns = [\n    path('stays/', include((\"stays.urls\", \"stays\"), namespace='stays')),",
        text, count=1
    )

    # De-duplicate identical lines
    lines = text.splitlines()
    seen = set()
    deduped = []
    for ln in lines:
        key = ln.strip()
        if key in seen and key.startswith("path("):
            continue
        seen.add(key)
        deduped.append(ln)
    text = "\n".join(deduped)

    write_text(CONFIG_URLS, text)
    return True

def normalize_stays_urls():
    text = read_text(STAYS_URLS)
    changed = False

    base = (
        "from django.urls import path\n"
        "from . import views\n\n"
        "app_name = \"stays\"\n\n"
        "urlpatterns = [\n"
        "    path('', views.stay_list, name='list'),\n"
        "    path('add/', views.stay_add, name='add'),\n"
        "    path('<int:pk>/', views.stay_detail, name='detail'),\n"
        "    path('<int:pk>/edit/', views.stay_edit, name='edit'),\n"
        "]\n"
    )

    if not text:
        write_text(STAYS_URLS, base)
        return True

    backup(STAYS_URLS)

    # Remove any include("config.urls") or include of itself
    text2 = re.sub(r'.*include\(\s*[\'"](config|stays)\.urls[\'"].*\)\s*,?\s*\n', "", text)
    if text2 != text:
        changed = True
        text = text2

    # Ensure app_name
    if "app_name" not in text:
        text = re.sub(r"(from\s+\.\s+import\s+views[^\n]*\n)", r"\1\napp_name = \"stays\"\n", text, count=1)
        if "app_name" not in text:
            # can't find import anchor; just prepend
            text = "app_name = \"stays\"\n" + text
        changed = True

    # Ensure at least one named route; if none, replace with base
    if "urlpatterns" not in text or "name=" not in text:
        text = base
        changed = True

    if changed:
        write_text(STAYS_URLS, text)
    return changed

def scrub_other_loops():
    changed = False
    # Scan all urls.py under the project
    for p in PROJECT_ROOT.rglob("urls.py"):
        if p == CONFIG_URLS or p == STAYS_URLS:
            continue
        txt = read_text(p)
        if not txt:
            continue
        if "include(\"config.urls\"" in txt or "include('config.urls'" in txt:
            backup(p)
            new = re.sub(r'.*include\(\s*[\'"]config\.urls[\'"].*\)\s*,?\s*\n', "", txt)
            write_text(p, new)
            changed = True
    return changed

def main():
    did1 = normalize_config_urls()
    did2 = normalize_stays_urls()
    did3 = scrub_other_loops()
    print("Done. Changes applied:" , any([did1, did2, did3]))
    print("Checked files:")
    print(" -", CONFIG_URLS)
    print(" -", STAYS_URLS)
    for p in sorted(PROJECT_ROOT.rglob("urls.py")):
        print(" -", p)

if __name__ == "__main__":
    main()
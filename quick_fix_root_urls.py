# quick_fix_root_urls.py
from pathlib import Path
import re

p = Path("config/urls.py")
txt = p.read_text(encoding="utf-8")

before = txt

# 1) Remove any stays direct view imports at the root
txt = re.sub(r'^\s*from\s+stays\s+import\s+views(?:\s+as\s+\w+)?\s*\n', '', txt, flags=re.MULTILINE)

# 2) Remove any direct path lines that call stays views from the root urls,
#    e.g. path("map/", stay_views.stays_map, ...), path("stays/new/", ...), etc.
txt = re.sub(r'^\s*path\(\s*["\'](?:stays/)?[^"\']*["\']\s*,\s*[^)]*stays?_?map[^)]*\)\s*,?\s*$',
             '', txt, flags=re.MULTILINE)
txt = re.sub(r'^\s*path\(\s*["\']stays/[^"\']*["\']\s*,\s*[^)]*\)\s*,?\s*$',
             '', txt, flags=re.MULTILINE)

# 3) Ensure we have the correct include for the namespaced stays app
include_line = "path('stays/', include(('stays.urls', 'stays'), namespace='stays')),"
if "from django.urls import" not in txt:
    txt = "from django.urls import path, include\n" + txt
elif "include" not in txt.split("from django.urls import",1)[1]:
    txt = txt.replace("from django.urls import path", "from django.urls import path, include")

if "urlpatterns" not in txt:
    txt += "\nurlpatterns = []\n"

if include_line not in txt:
    # inject after urlpatterns = [
    txt = re.sub(r"urlpatterns\s*=\s*\[\s*",
                 lambda m: m.group(0) + "\n    " + include_line + "\n",
                 txt, count=1)

# 4) Tidy extra blank lines
txt = re.sub(r'\n{3,}', '\n\n', txt)

if txt != before:
    p.write_text(txt, encoding="utf-8")
    print("Patched config/urls.py ✅")
else:
    print("config/urls.py already clean ✅")

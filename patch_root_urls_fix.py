from pathlib import Path
import re
p = Path("config/urls.py")
txt = p.read_text(encoding="utf-8")
# Remove any line that references stay_create
txt2 = re.sub(r".*stay_create.*\n", "", txt)
# Ensure we include only the namespaced stays include
if "include((" not in txt2 or "namespace=\"stays\"" not in txt2:
    txt2 = re.sub(r"path\(\s*[\"\\']stays/.*", "", txt2)  # drop other stays lines
    inject = "path('stays/', include(('stays.urls', 'stays'), namespace='stays')),"
    if "urlpatterns" in txt2:
        txt2 = re.sub(r"urlpatterns\s*=\s*\[\s*", lambda m: m.group(0) + "\n    " + inject + "\n", txt2, count=1)
    else:
        txt2 += f"\nurlpatterns = [\n    {inject}\n]\n"
p.write_text(txt2, encoding="utf-8")
print("Patched config/urls.py")

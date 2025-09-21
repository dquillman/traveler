from pathlib import Path
import re
from datetime import datetime

PROJ = Path.cwd()
URLS = PROJ / "stays" / "urls.py"

def backup(p: Path):
    if p.exists():
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        p.with_suffix(p.suffix + f".{ts}.bak").write_bytes(p.read_bytes())

def main():
    if not URLS.exists():
        print(f"[ERROR] {URLS} not found")
        return
    txt = URLS.read_text(encoding="utf-8", errors="replace")
    orig = txt

    # Ensure 'from django.urls import path'
    if "from django.urls" not in txt:
        txt = "from django.urls import path\n" + txt
    else:
        txt = re.sub(r"from\s+django\.urls\s+import\s+([^\n]+)",
                     lambda m: "from django.urls import " + ", ".join(sorted(set([*(x.strip() for x in m.group(1).split(',')), "path"]))),
                     txt, count=1)

    # Ensure 'from . import views'
    if re.search(r"from\s+\.\s+import\s+views", txt) is None:
        # place after django.urls import if possible
        if "from django.urls import" in txt:
            txt = re.sub(r"(from\s+django\.urls\s+import[^\n]*\n)",
                         r"\1from . import views\n",
                         txt, count=1)
        else:
            txt = "from . import views\n" + txt

    if txt != orig:
        backup(URLS)
        URLS.write_text(txt, encoding="utf-8", newline="\n")
        print("Updated:", URLS)
    else:
        print("No change required:", URLS)

if __name__ == "__main__":
    main()
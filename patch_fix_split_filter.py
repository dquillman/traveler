from pathlib import Path
from datetime import datetime
import re

PROJ = Path.cwd()
TPL = PROJ / "stays" / "templates" / "stays" / "stay_form.html"

def backup(p: Path):
    if p.exists():
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        p.with_suffix(p.suffix + f".{ts}.bak").write_bytes(p.read_bytes())

def main():
    if not TPL.exists():
        print(f"[ERROR] Template not found: {TPL}")
        return
    txt = TPL.read_text(encoding="utf-8", errors="replace")
    orig = txt

    pattern = r'{%\s*if\s*field\.name\s*not\s*in\s*"[^"]*"\|split:"[^"]*"\s*%}'
    replacement = ("{% if field.name != 'name' and field.name != 'address' and field.name != 'city' "
                   "and field.name != 'state' and field.name != 'zipcode' "
                   "and field.name != 'latitude' and field.name != 'longitude' %}")
    txt2 = re.sub(pattern, replacement, txt)

    if txt2 == orig and '|split:' not in txt:
        print("No change needed; 'split' filter not found.")
        return

    backup(TPL)
    TPL.write_text(txt2, encoding="utf-8", newline="\n")
    print("Updated:", TPL)

if __name__ == "__main__":
    main()
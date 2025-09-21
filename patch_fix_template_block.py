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
        print(f"[ERROR] Not found: {TPL}")
        return
    txt = TPL.read_text(encoding="utf-8", errors="replace")
    orig = txt

    # Normalize Windows line endings to \n for matching
    txt = txt.replace('\r\n', '\n')

    # Replace the multi-line if with a single-line version
    pattern = re.compile(
        r"{%\s*for\s+field\s+in\s+form\.visible_fields\s*%}\s*"
        r"{%\s*if[^%]*%}",
        re.DOTALL
    )

    if pattern.search(txt):
        txt = pattern.sub(
            "{% for field in form.visible_fields %}\n"
            "{% if field.name != 'name' and field.name != 'address' and field.name != 'city' and field.name != 'state' and field.name != 'zipcode' and field.name != 'latitude' and field.name != 'longitude' %}",
            txt, count=1
        )
    else:
        # Fallback: target the specific old line if it exists
        txt = txt.replace(
            "{% if field.name != 'name' and field.name != 'address' and field.name != 'city'\n                and field.name != 'state' and field.name != 'zipcode'\n                and field.name != 'latitude' and field.name != 'longitude' %}",
            "{% if field.name != 'name' and field.name != 'address' and field.name != 'city' and field.name != 'state' and field.name != 'zipcode' and field.name != 'latitude' and field.name != 'longitude' %}"
        )

    if txt != orig:
        backup(TPL)
        TPL.write_text(txt, encoding="utf-8", newline="\n")
        print("Updated:", TPL)
    else:
        print("No changes made (template already simplified).")

if __name__ == "__main__":
    main()
# auto_fix_base_nav.py
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
BASE_HTML = None

# Find base.html in common places
candidates = [
    ROOT / "templates" / "base.html",
    ROOT / "stays" / "templates" / "base.html",
]
for c in candidates:
    if c.exists():
        BASE_HTML = c
        break

if not BASE_HTML:
    print("Couldn't find base.html in expected locations.")
    raise SystemExit(1)

txt = BASE_HTML.read_text(encoding="utf-8")
orig = txt

# Map old → new url names (template {% url %} and raw strings)
replacements = {
    # brand/home → stays list
    r"(\{\%\s*url\s*['\"])home(['\"])": r"\1stays:list\2",
    r'href="/"\s*': 'href="{% url \'stays:list\' %}" ',  # rare, but nice to normalize

    # create/add
    r"(\{\%\s*url\s*['\"])stay_create(['\"])": r"\1stays:add\2",

    # map
    r"(\{\%\s*url\s*['\"])stays_map(['\"])": r"\1stays:map\2",
}

for pattern, repl in replacements.items():
    txt = re.sub(pattern, repl, txt)

# (Optional) tighten whitespace
txt = re.sub(r"[ \t]+(\n)", r"\1", txt)

if txt != orig:
    BASE_HTML.write_text(txt, encoding="utf-8")
    print(f"Patched: {BASE_HTML}")
else:
    print("No changes needed; base.html already OK.")

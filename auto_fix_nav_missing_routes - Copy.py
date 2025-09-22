# auto_fix_nav_missing_routes.py
"""
Wraps nav links for optional routes (import/export/appearance) in base.html so
they no longer blow up with NoReverseMatch when those URL names are missing.

It converts:
    <a href="{% url 'import_stays_csv' %}">Import</a>
into:
    {% url 'import_stays_csv' as import_url %}{% if import_url %}<a href="{{ import_url }}">Import</a>{% endif %}

Same for export_stays_csv and appearance_edit.

Idempotent & safe to run multiple times.
"""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
candidates = [
    ROOT / "templates" / "base.html",
    ROOT / "stays" / "templates" / "base.html",
]

base = None
for c in candidates:
    if c.exists():
        base = c
        break

if not base:
    print("Couldn't find base.html in templates/. Nothing changed.")
    raise SystemExit(0)

txt = base.read_text(encoding="utf-8")
orig = txt

def wrap(name: str, label: str) -> str:
    # Build patterns for an <a> using {% url 'name' %} with any classes/content.
    # We'll replace the entire anchor with a guarded version using 'as var' form.
    var = f"{name}_url"
    # Regex: find <a ... href="{% url 'name' %}">LABEL</a> (LABEL can vary; we keep inner HTML)
    pattern = re.compile(
        rf'<a([^>]*?)href="\{{%\s*url\s*[\'"]{re.escape(name)}[\'"]\s*%\}}"([^>]*)>(.*?)</a>',
        re.IGNORECASE | re.DOTALL,
    )
    def repl(m):
        before_attrs = m.group(1)
        after_attrs = m.group(2)
        inner_html = m.group(3)
        # rebuild anchor but guarded
        anchor = f'{{% url \'{name}\' as {var} %}}{{% if {var} %}}<a{before_attrs}href="{{{{ {var} }}}}"{after_attrs}>{inner_html}</a>{{% endif %}}'
        return anchor
    return pattern.sub(repl, txt)

for nm, lbl in [
    ("import_stays_csv", "Import"),
    ("export_stays_csv", "Export"),
    ("appearance_edit", "Appearance"),
]:
    txt = wrap(nm, lbl)

if txt != orig:
    base.write_text(txt, encoding="utf-8")
    print(f"Patched: {base}")
else:
    print("No changes needed; base.html already guarded.")

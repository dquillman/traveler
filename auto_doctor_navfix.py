# auto_doctor_navfix.py
"""
Fixes un-namespaced {% url 'stay_*' %} and reverse('stay_*') calls
→ converts to namespaced 'stays:*' across templates & python files.
Optionally adds a root redirect to stays:list in config/urls.py (safe & idempotent).
"""

from pathlib import Path
import re

PROJECT = Path(__file__).resolve().parent
TEMPLATE_DIRS = [
    PROJECT / "templates",
    PROJECT / "stays" / "templates",
]
CODE_DIRS = [
    PROJECT / "stays",
    PROJECT / "config",
]

# map of un-namespaced → namespaced
url_names = {
    "stay_list":   "stays:list",
    "stay_map":    "stays:map",
    "stay_add":    "stays:add",
    "stay_detail": "stays:detail",
    "stay_edit":   "stays:edit",
    "stay_charts": "stays:charts",
}

def patch_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    original = text

    # Django template tags {% url 'stay_list' ... %}
    for old, new in url_names.items():
        # {% url 'stay_list' %} or {% url 'stay_list' arg %}
        text = re.sub(rf"(\{{%\s*url\s*['\"])({old})(['\"])", rf"\1{new}\3", text)

    # Python reverse('stay_list'), reverse_lazy("stay_list")
    for old, new in url_names.items():
        text = re.sub(rf"(reverse(?:_lazy)?\(\s*['\"])({old})(['\"])", rf"\1{new}\3", text)

    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False

def scan_and_patch(dirs, exts=(".html", ".htm", ".py")) -> int:
    changed = 0
    for root in dirs:
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if p.is_file() and p.suffix.lower() in exts:
                try:
                    if patch_file(p):
                        print(f"• Patched: {p}")
                        changed += 1
                except UnicodeDecodeError:
                    pass
    return changed

def ensure_root_redirect():
    """Add a root redirect to stays:list to config/urls.py (optional)."""
    cfg = PROJECT / "config" / "urls.py"
    if not cfg.exists():
        return False

    txt = cfg.read_text(encoding="utf-8")
    orig = txt

    # ensure imports
    if "from django.urls import" not in txt:
        txt = "from django.urls import path, include, reverse_lazy\n" + txt
    else:
        if "reverse_lazy" not in txt:
            txt = txt.replace("from django.urls import path, include",
                              "from django.urls import path, include, reverse_lazy")

    if "from django.views.generic.base import RedirectView" not in txt:
        txt = "from django.views.generic.base import RedirectView\n" + txt

    # ensure urlpatterns exists
    if "urlpatterns" not in txt:
        txt += "\nurlpatterns = []\n"

    redirect_line = "path('', RedirectView.as_view(url=reverse_lazy('stays:list'), permanent=False)),"
    if redirect_line not in txt:
        txt = re.sub(
            r"urlpatterns\s*=\s*\[\s*",
            lambda m: m.group(0) + "\n    " + redirect_line + "\n",
            txt, count=1
        )

    if txt != orig:
        cfg.write_text(txt, encoding="utf-8")
        print("• Added root redirect → stays:list in config/urls.py")
        return True
    return False

def main():
    total = 0
    total += scan_and_patch(TEMPLATE_DIRS, exts=(".html", ".htm"))
    total += scan_and_patch(CODE_DIRS,     exts=(".py",))

    ensure_root_redirect()

    if total == 0:
        print("✓ No un-namespaced 'stay_*' references found.")
    else:
        print(f"Patched {total} file(s).")

if __name__ == "__main__":
    main()

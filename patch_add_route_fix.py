import re
from pathlib import Path
from datetime import datetime

PROJ = Path.cwd()
STAYS_DIR = PROJ / "stays"
VIEWS = STAYS_DIR / "views.py"
URLS  = STAYS_DIR / "urls.py"
TPL   = STAYS_DIR / "templates" / "stays" / "stay_form.html"

def ts(): return datetime.now().strftime("%Y%m%d-%H%M%S")

def backup(p: Path):
    if p.exists():
        p.with_suffix(p.suffix + f".{ts()}.bak").write_bytes(p.read_bytes())

def read(p: Path): return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""
def write(p: Path, s: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding="utf-8", newline="\n")

def ensure_urls_has_add():
    changed = False
    text = read(URLS)
    if not text:
        text = (
            "from django.urls import path\n"
            "from . import views\n\n"
            "app_name = 'stays'\n\n"
            "urlpatterns = [\n"
            "    path('', views.stay_list, name='list'),\n"
            "    path('add/', views.stay_add, name='add'),\n"
            "    path('<int:pk>/', views.stay_detail, name='detail'),\n"
            "    path('<int:pk>/edit/', views.stay_edit, name='edit'),\n"
            "]\n"
        )
        write(URLS, text)
        return True

    orig = text
    if 'app_name' not in text:
        text = re.sub(r'(from\s+\.?\s*import\s*views[^\n]*\n)', r"\1\napp_name = 'stays'\n", text, count=1) or ("app_name = 'stays'\n" + text)
    if "from django.urls" not in text:
        text = "from django.urls import path\n" + text
    elif "path" not in re.search(r'from\s+django\.urls\s+import\s+([^\n]+)', text).group(1):
        text = re.sub(r'from\s+django\.urls\s+import\s+([^\n]+)',
                      lambda m: "from django.urls import " + (m.group(1)+", path"),
                      text, count=1)

    # Does a pattern named 'add' exist?
    if re.search(r"name\s*=\s*['\"]add['\"]", text) is None:
        # Try to find an existing create-like view name to route to
        candidates = ["stay_add", "stay_create", "add_stay", "create_stay"]
        view_to_use = None
        vtxt = read(VIEWS)
        for c in candidates:
            if re.search(rf"def\s+{c}\s*\(", vtxt):
                view_to_use = c
                break
        if not view_to_use:
            view_to_use = "stay_add"
        # Inject a line in urlpatterns
        if "urlpatterns" in text:
            text = re.sub(r"urlpatterns\s*=\s*\[",
                          lambda m: m.group(0) + f"\n    path('add/', views.{view_to_use}, name='add'),",
                          text, count=1)
        else:
            text += f"\n\nurlpatterns = [\n    path('add/', views.{view_to_use}, name='add'),\n]\n"
        changed = True

    if text != orig:
        backup(URLS)
        write(URLS, text)
        changed = True
    return changed

def ensure_views_has_stay_add():
    txt = read(VIEWS)
    if "def stay_add(" in txt:
        return False

    # If a create-like view exists, create a thin alias that calls it.
    for alt in ["stay_create", "add_stay", "create_stay"]:
        if re.search(rf"def\s+{alt}\s*\(", txt):
            alias = (
                "\n\n# Auto-added alias so {% url 'stays:add' %} works\n"
                "def stay_add(request, *args, **kwargs):\n"
                f"    return {alt}(request, *args, **kwargs)\n"
            )
            backup(VIEWS)
            write(VIEWS, txt + alias)
            return True

    # Else, inject a minimal ModelForm-based create view
    injector = (
        "\n\nfrom django.shortcuts import render, redirect\n"
        "from django.urls import reverse\n"
        "from django.forms import ModelForm\n"
        "try:\n"
        "    from .models import Stay\n"
        "except Exception:\n"
        "    Stay = None\n"
        "\n"
        "class _AutoStayForm(ModelForm):\n"
        "    class Meta:\n"
        "        model = Stay\n"
        "        fields = '__all__'\n"
        "\n"
        "def stay_add(request):\n"
        "    if Stay is None:\n"
        "        return render(request, 'stays/stay_form.html', {'form': None, 'error': 'Stay model not found'})\n"
        "    form = _AutoStayForm(request.POST or None, request.FILES or None)\n"
        "    if request.method == 'POST' and form.is_valid():\n"
        "        obj = form.save()\n"
        "        # Prefer detail if it resolves, otherwise list\n"
        "        try:\n"
        "            return redirect('stays:detail', pk=obj.pk)\n"
        "        except Exception:\n"
        "            try:\n"
        "                return redirect('stays:list')\n"
        "            except Exception:\n"
        "                return redirect('/')\n"
        "    return render(request, 'stays/stay_form.html', {'form': form})\n"
    )
    backup(VIEWS)
    write(VIEWS, txt + injector)
    return True

def ensure_template():
    if TPL.exists(): return False
    html = (
        "{% load static %}\n"
        "<!doctype html>\n"
        "<html>\n"
        "<head>\n"
        "  <meta charset=\"utf-8\">\n"
        "  <title>Add Stay</title>\n"
        "  <style>\n"
        "    body{font-family:system-ui,Segoe UI,Arial,sans-serif;margin:2rem;}\n"
        "    form{max-width:640px}\n"
        "    label{display:block;margin-top:0.75rem;font-weight:600}\n"
        "    input,select,textarea{width:100%;padding:0.5rem;border:1px solid #ccc;border-radius:6px}\n"
        "    button{margin-top:1rem;padding:0.6rem 1rem;border:0;border-radius:8px}\n"
        "  </style>\n"
        "</head>\n"
        "<body>\n"
        "  <h1>Add Stay</h1>\n"
        "  {% if error %}<p style=\"color:#b00\">{{ error }}</p>{% endif %}\n"
        "  <form method=\"post\" enctype=\"multipart/form-data\">\n"
        "    {% csrf_token %}\n"
        "    {% if form %}\n"
        "      {{ form.as_p }}\n"
        "      <button type=\"submit\">Save</button>\n"
        "    {% else %}\n"
        "      <p>No form available.</p>\n"
        "    {% endif %}\n"
        "  </form>\n"
        "</body>\n"
        "</html>\n"
    )
    TPL.parent.mkdir(parents=True, exist_ok=True)
    TPL.write_text(html, encoding="utf-8", newline="\n")
    return True

def main():
    changed = []
    if ensure_urls_has_add(): changed.append("stays/urls.py")
    if ensure_views_has_stay_add(): changed.append("stays/views.py")
    if ensure_template(): changed.append("stays/templates/stays/stay_form.html")
    if changed:
        print("Created/updated:", ", ".join(changed))
    else:
        print("No changes needed; 'stays:add' should already resolve.")

if __name__ == "__main__":
    main()
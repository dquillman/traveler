from pathlib import Path
from datetime import datetime
import re

PROJ = Path.cwd()
STAYS = PROJ / "stays"
URLS = STAYS / "urls.py"
VIEWS = STAYS / "views.py"
TPL_DETAIL = STAYS / "templates" / "stays" / "stay_detail.html"
TPL_FORM = STAYS / "templates" / "stays" / "stay_form.html"

def ts(): return datetime.now().strftime("%Y%m%d-%H%M%S")
def backup(p: Path):
    if p.exists():
        p.with_suffix(p.suffix + f".{ts()}.bak").write_bytes(p.read_bytes())
def read(p: Path): return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""
def write(p: Path, s: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding="utf-8", newline="\n")

def ensure_urls():
    changed = False
    txt = read(URLS)
    if not txt:
        txt = "from django.urls import path\nfrom . import views\n\napp_name = 'stays'\n\nurlpatterns = []\n"
    # ensure imports
    if "from django.urls" not in txt:
        txt = "from django.urls import path\n" + txt
    if re.search(r"from\s+\.\s+import\s+views", txt) is None:
        txt = re.sub(r"(from\s+django\.urls\s+import[^\n]*\n)", r"\1from . import views\n", txt, count=1) or ("from . import views\n" + txt)
    if "app_name" not in txt:
        txt = re.sub(r"(from\s+\.\s+import\s+views[^\n]*\n)", r"\1\napp_name = 'stays'\n", txt, count=1) or (txt + "\napp_name = 'stays'\n")

    # ensure urlpatterns exists
    if "urlpatterns" not in txt:
        txt += "\nurlpatterns = []\n"

    def add_route(pattern, view, name):
        nonlocal txt
        if re.search(rf"name\s*=\s*['\"]{name}['\"]", txt):
            return
        txt = re.sub(r"urlpatterns\s*=\s*\[",
                     lambda m: m.group(0) + f"\n    path('{pattern}', views.{view}, name='{name}'),",
                     txt, count=1)

    add_route("<int:pk>/", "stay_detail", "detail")
    add_route("<int:pk>/edit/", "stay_edit", "edit")

    backup(URLS)
    write(URLS, txt)

def ensure_views():
    txt = read(VIEWS)
    if not txt:
        txt = ""

    changed = False
    # common imports
    need_imports = []
    if "get_object_or_404" not in txt:
        need_imports.append("from django.shortcuts import render, get_object_or_404, redirect")
    elif "render" not in txt or "redirect" not in txt:
        need_imports.append("from django.shortcuts import render, get_object_or_404, redirect")
    if "reverse" not in txt:
        need_imports.append("from django.urls import reverse")
    if "ModelForm" not in txt:
        need_imports.append("from django.forms import ModelForm")
    if "from .models import Stay" not in txt:
        need_imports.append("from .models import Stay")

    if need_imports:
        txt = "\n".join(sorted(set(need_imports))) + "\n\n" + txt
        changed = True

    if "def stay_detail(" not in txt:
        txt += (
            "\n\ndef stay_detail(request, pk):\n"
            "    obj = get_object_or_404(Stay, pk=pk)\n"
            "    return render(request, 'stays/stay_detail.html', {'stay': obj})\n"
        )
        changed = True

    if "class _EditStayForm(" not in txt:
        txt += (
            "\n\nclass _EditStayForm(ModelForm):\n"
            "    class Meta:\n"
            "        model = Stay\n"
            "        fields = '__all__'\n"
        )
        changed = True

    if "def stay_edit(" not in txt:
        txt += (
            "\n\ndef stay_edit(request, pk):\n"
            "    obj = get_object_or_404(Stay, pk=pk)\n"
            "    form = _EditStayForm(request.POST or None, request.FILES or None, instance=obj)\n"
            "    if request.method == 'POST' and form.is_valid():\n"
            "        obj = form.save()\n"
            "        try:\n"
            "            return redirect('stays:detail', pk=obj.pk)\n"
            "        except Exception:\n"
            "            return redirect('/')\n"
            "    return render(request, 'stays/stay_form.html', {'form': form, 'stay': obj})\n"
        )
        changed = True

    if changed:
        backup(VIEWS)
        write(VIEWS, txt)

def ensure_templates():
    if not TPL_DETAIL.exists():
        html = (
            "<!doctype html>\n<html>\n<head><meta charset='utf-8'><title>Stay Detail</title></head>\n"
            "<body>\n  <h1>{{ stay.park }} {{ stay.site }}</h1>\n"
            "  <p>{{ stay.city }}, {{ stay.state }}</p>\n"
            "  <p>Lat: {{ stay.latitude }} Lng: {{ stay.longitude }}</p>\n"
            "  <p><a href=\"{% url 'stays:edit' stay.pk %}\">Edit</a> | <a href=\"{% url 'stays:list' %}\">Back</a></p>\n"
            "</body>\n</html>\n"
        )
        TPL_DETAIL.parent.mkdir(parents=True, exist_ok=True)
        TPL_DETAIL.write_text(html, encoding="utf-8", newline="\n")
    if not TPL_FORM.exists():
        html = (
            "<!doctype html>\n<html>\n<head><meta charset='utf-8'><title>Edit Stay</title></head>\n"
            "<body>\n  <h1>Edit Stay</h1>\n"
            "  <form method=\"post\" enctype=\"multipart/form-data\">\n"
            "    {% csrf_token %}\n"
            "    {{ form.as_p }}\n"
            "    <button type=\"submit\">Save</button>\n"
            "  </form>\n"
            "  <p><a href=\"{% if stay %}{% url 'stays:detail' stay.pk %}{% else %}{% url 'stays:list' %}{% endif %}\">Back</a></p>\n"
            "</body>\n</html>\n"
        )
        TPL_FORM.parent.mkdir(parents=True, exist_ok=True)
        TPL_FORM.write_text(html, encoding="utf-8", newline="\n")

def main():
    ensure_urls()
    ensure_views()
    ensure_templates()
    print("Detail/Edit routes and views ensured.")

if __name__ == "__main__":
    main()
# verify_stays_setup.py
import os
import sys
import argparse
import traceback

# ------------- CONFIG -------------
DEFAULT_SETTINGS = "config.settings"   # change if your settings module is different
APP_LABEL = "stays"
TEMPLATES = [
    f"{APP_LABEL}/stay_list.html",
    f"{APP_LABEL}/map.html",
    f"{APP_LABEL}/stay_form.html",
    f"{APP_LABEL}/stay_detail.html",
]
URLNAMES = [
    f"{APP_LABEL}:list",
    f"{APP_LABEL}:map",
    f"{APP_LABEL}:add",
    f"{APP_LABEL}:detail",
    f"{APP_LABEL}:edit",
]
# ----------------------------------

def header(title):
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)

def ok(msg):
    print(f"✔ {msg}")

def fail(msg):
    print(f"✘ {msg}")

def main():
    parser = argparse.ArgumentParser(description="Verify stays wiring (urls, views, templates, ORM).")
    parser.add_argument("--settings", default=os.environ.get("DJANGO_SETTINGS_MODULE", DEFAULT_SETTINGS),
                        help="Django settings module (default: %(default)s)")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose errors")
    args = parser.parse_args()

    # Point DJANGO_SETTINGS_MODULE
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", args.settings)

    header("1) Django setup")
    try:
        import django
        django.setup()
        ok(f"Django set up with settings: {args.settings}")
    except Exception as e:
        fail("Failed to set up Django")
        if args.verbose:
            traceback.print_exc()
        sys.exit(1)

    header("2) Import stays app modules")
    try:
        from django.urls import reverse, NoReverseMatch
        from django.template.loader import get_template
        from importlib import import_module

        urls = import_module(f"{APP_LABEL}.urls")
        views = import_module(f"{APP_LABEL}.views")
        ok("Imported stays.urls and stays.views")
    except Exception:
        fail("Could not import stays.urls or stays.views")
        if args.verbose:
            traceback.print_exc()
        sys.exit(1)

    header("3) Check view functions presence")
    expected_views = ["stay_list", "stay_map", "stay_add", "stay_detail", "stay_edit"]
    missing = [v for v in expected_views if not hasattr(views, v)]
    if missing:
        for v in missing:
            fail(f"Missing view: {APP_LABEL}.views.{v}")
    else:
        ok("All expected views exist")
    if missing:
        sys.exit(2)

    header("4) Reverse URL names")
    problems = False
    for name in URLNAMES:
        try:
            if name.endswith(":detail") or name.endswith(":edit"):
                # These patterns require pk
                reverse(name, kwargs={"pk": 1})
            else:
                reverse(name)
            ok(f"Reversed {name}")
        except NoReverseMatch as e:
            problems = True
            fail(f"Could not reverse {name} ({e})")
        except Exception:
            problems = True
            fail(f"Error reversing {name}")
            if args.verbose:
                traceback.print_exc()
    if problems:
        sys.exit(3)

    header("5) Load templates")
    tpl_problems = False
    for tpl in TEMPLATES:
        try:
            get_template(tpl)
            ok(f"Loaded template: {tpl}")
        except Exception:
            tpl_problems = True
            fail(f"Missing or broken template: {tpl}")
            if args.verbose:
                traceback.print_exc()
    if tpl_problems:
        sys.exit(4)

    header("6) ORM sanity checks (optional)")
    try:
        from stays.models import Stay
        total = Stay.objects.count()
        with_coords = Stay.objects.exclude(latitude__isnull=True)\
                                  .exclude(longitude__isnull=True).count()
        ok(f"Stays in DB: {total} (with lat/lng: {with_coords})")
    except Exception:
        # Not fatal—maybe migrations not applied yet
        fail("Could not query Stay model (migrations? database?)")
        if args.verbose:
            traceback.print_exc()

    header("✅ All checks passed")
    return 0

if __name__ == "__main__":
    sys.exit(main())

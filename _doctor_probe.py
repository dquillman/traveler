import json, importlib
from django.apps import apps
from django.urls import get_resolver

data = {}

# Stay model fields (concrete only)
try:
    Stay = apps.get_model("stays","Stay")
    fields = [f.name for f in Stay._meta.get_fields() if getattr(f,"concrete",False)]
except Exception:
    fields = []
data["stay_fields"] = fields

# URL names (walk nested patterns)
def collect(patterns, acc):
    for p in patterns:
        if hasattr(p, "url_patterns"):
            collect(p.url_patterns, acc)
        else:
            n = getattr(p, "name", None)
            if n:
                acc.append(n)

resolver = get_resolver()
acc = []
collect(resolver.url_patterns, acc)
data["url_names"] = sorted(set([n for n in acc if n]))

# stays.views attributes
try:
    views = importlib.import_module("stays.views")
    members = [a for a in dir(views) if not a.startswith("_")]
except Exception:
    members = []
data["stays_views"] = members

print("===DOCTOR_JSON_START===")
print(json.dumps(data))
print("===DOCTOR_JSON_END===")
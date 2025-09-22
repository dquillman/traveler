Continue = "Stop"
function Ensure-Dir(){ if(-not(Test-Path )){ New-Item -ItemType Directory -Path  | Out-Null } }
if(-not(Test-Path ".\manage.py")){ throw "Run from project root." }
 = Get-ChildItem -Recurse -Filter "settings.py" | Where-Object { .FullName -notmatch '\\venv\\|\.venv\\' } | Select-Object -First 1
 = Get-ChildItem -Recurse -Filter "urls.py" | Where-Object { .FullName -notmatch '\\venv\\|\.venv\\' -and (Get-Content .FullName) -match 'urlpatterns\s*=' } | Select-Object -First 1
 = Get-Content .FullName -Raw
if( -notmatch 'MEDIA_URL\s*='){  = .TrimEnd()+"

MEDIA_URL = ""/media/""
MEDIA_ROOT = BASE_DIR / ""media""
"; Set-Content .FullName  -Encoding UTF8 }
 = Get-Content .FullName -Raw
if( -notmatch 'from django\.conf import settings'){  = "from django.conf import settings
"+ }
if( -notmatch 'from django\.conf\.urls\.static import static'){  = "from django.conf.urls.static import static
"+ }
if( -notmatch 'urlpatterns\s*\+\=\s*static\(settings\.MEDIA_URL'){  = .TrimEnd()+"
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
" }
Set-Content .FullName  -Encoding UTF8
 = Join-Path (Get-Location) "stays"
 = Join-Path  "apps.py"
 = Join-Path  "utils"; Ensure-Dir 
 = Join-Path  "placeholders.py"
Set-Content  @"
from django.apps import AppConfig
class StaysConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "stays"
    def ready(self):
        try:
            from .utils.placeholders import ensure_placeholder_image
            ensure_placeholder_image()
        except Exception:
            pass

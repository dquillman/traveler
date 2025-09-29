from pathlib import Path
import os
from datetime import datetime, timezone

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = 'dev-not-for-prod'
# Allow DEBUG/ALLOWED_HOSTS to be configured via environment for deployments
DEBUG = os.getenv('DEBUG', 'True').lower() in {'1', 'true', 'yes', 'on'}

# Robustly parse ALLOWED_HOSTS from env; tolerate quotes/whitespace and empty values
_ALLOWED_HOSTS_ENV = os.getenv('ALLOWED_HOSTS')
_DEFAULT_HOSTS = ["localhost", "127.0.0.1", "[::1]", ".onrender.com"]
if _ALLOWED_HOSTS_ENV is None:
    # No env provided → use defaults
    ALLOWED_HOSTS = _DEFAULT_HOSTS
else:
    # Env provided; parse and ignore empties/quotes/whitespace
    _parsed_hosts = [h.strip().strip('"\'') for h in _ALLOWED_HOSTS_ENV.split(',') if h.strip().strip('"\'')]
    # If parsing yields nothing (e.g., value was "" or spaces), fall back to defaults
    ALLOWED_HOSTS = _parsed_hosts or _DEFAULT_HOSTS

# CSRF trusted origins for hosted envs (only affects POST/CSRf-protected views)
_CSRF_ENV = os.getenv('CSRF_TRUSTED_ORIGINS')
if _CSRF_ENV is None:
    CSRF_TRUSTED_ORIGINS = ["https://*.onrender.com"]
else:
    _parsed_origins = [o.strip().strip('"\'') for o in _CSRF_ENV.split(',') if o.strip().strip('"\'')]
    CSRF_TRUSTED_ORIGINS = _parsed_origins or ["https://*.onrender.com"]

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'stays.apps.StaysConfig',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    # (WhiteNoise inserted below if available)
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

# Optionally enable WhiteNoise if installed (useful in local dev without installing it)
try:
    import whitenoise  # type: ignore  # noqa: F401
    MIDDLEWARE.insert(1, 'whitenoise.middleware.WhiteNoiseMiddleware')
    _WHITENOISE = True
except Exception:
    _WHITENOISE = False

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates', BASE_DIR / 'stays' / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
                'stays.context_processors.site_appearance',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}

# If DATABASE_URL is provided (e.g., on Render with PostgreSQL), use it.
_DATABASE_URL = os.getenv('DATABASE_URL')
if _DATABASE_URL:
    try:
        import dj_database_url  # type: ignore
        DATABASES['default'] = dj_database_url.parse(_DATABASE_URL, conn_max_age=600)
    except Exception:
        # Fallback: keep sqlite if parsing package unavailable
        pass

AUTH_PASSWORD_VALIDATORS = []

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'America/Chicago'
USE_I18N = True
USE_TZ = True

STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
if _WHITENOISE:
    STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# For geopy/Nominatim auto-geocoding
GEOCODER_USER_AGENT = "traveler-app"


STATICFILES_DIRS = [BASE_DIR / 'static']

# App version (surface in navbar). Update on releases.
APP_VERSION = "v0.1.30"

# Build timestamp (for display in UI). Can be provided by env; otherwise set at import time.
APP_BUILD_AT = os.getenv('BUILD_TIMESTAMP') or datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%SZ')

# --- Optional S3/R2 media storage ---
AWS_BUCKET = os.getenv('AWS_STORAGE_BUCKET_NAME')
AWS_S3_ENDPOINT_URL = os.getenv('AWS_S3_ENDPOINT_URL')
AWS_S3_REGION_NAME = os.getenv('AWS_S3_REGION_NAME')
AWS_S3_CUSTOM_DOMAIN = os.getenv('AWS_S3_CUSTOM_DOMAIN')
if AWS_BUCKET:
    INSTALLED_APPS.append('storages')
    STORAGES = {
        'default': {
            'BACKEND': 'storages.backends.s3boto3.S3Boto3Storage',
        },
        'staticfiles': {
            'BACKEND': 'whitenoise.storage.CompressedManifestStaticFilesStorage' if _WHITENOISE else 'django.contrib.staticfiles.storage.StaticFilesStorage',
        },
    }
    AWS_S3_FILE_OVERWRITE = False
    AWS_DEFAULT_ACL = None
    AWS_QUERYSTRING_AUTH = False
    AWS_S3_REGION_NAME = AWS_S3_REGION_NAME or None
    AWS_S3_ENDPOINT_URL = AWS_S3_ENDPOINT_URL or None
    if AWS_S3_CUSTOM_DOMAIN:
        MEDIA_URL = f"https://{AWS_S3_CUSTOM_DOMAIN.rstrip('/')}/"
    elif AWS_S3_ENDPOINT_URL and AWS_BUCKET:
        MEDIA_URL = f"{AWS_S3_ENDPOINT_URL.rstrip('/')}/{AWS_BUCKET}/"

# --- Production security (effective when DEBUG is False) ---
# Trust proxy headers for HTTPS (Render/most PaaS set X-Forwarded-Proto)
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

if not DEBUG:
    SECURE_SSL_REDIRECT = True
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = int(os.getenv('SECURE_HSTS_SECONDS', '31536000'))  # 1 year
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    X_FRAME_OPTIONS = 'DENY'
    SECURE_REFERRER_POLICY = 'strict-origin-when-cross-origin'

# CSRF trusted origins (needed for HTTPS on Render)
CSRF_TRUSTED_ORIGINS = [o for o in os.getenv('CSRF_TRUSTED_ORIGINS', 'https://*.onrender.com').split(',') if o]

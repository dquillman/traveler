#!/usr/bin/env bash
set -euo pipefail

# Render start script
# - Applies migrations
# - Launches Gunicorn

python manage.py migrate --noinput

# Defaults are safe for small instances; override via env if needed
WEB_CONCURRENCY="${WEB_CONCURRENCY:-2}"
WEB_TIMEOUT="${WEB_TIMEOUT:-120}"
PORT="${PORT:-8000}"

exec gunicorn config.wsgi:application \
  --bind 0.0.0.0:"${PORT}" \
  --workers "${WEB_CONCURRENCY}" \
  --timeout "${WEB_TIMEOUT}" \
  --preload


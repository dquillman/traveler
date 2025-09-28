#!/usr/bin/env bash
set -euo pipefail

# Render build script
# - Installs dependencies
# - Collects static files

python -m pip install --upgrade pip
pip install -r requirements.txt

# Collect static assets (no DB required)
python manage.py collectstatic --noinput


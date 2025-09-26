#!/usr/bin/env bash
set -euo pipefail
export DJANGO_SETTINGS_MODULE=config.settings_test

# Default to testing 'stays' if no labels are provided
if [ "$#" -eq 0 ]; then
  set -- stays
fi

exec python manage.py test -v 2 "$@"


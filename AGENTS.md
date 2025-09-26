# Repository Guidelines

## Project Structure & Modules
- app: Django project with app `stays`.
- `config/`: project settings, URLs, WSGI/ASGI.
- `stays/`: models, views, URLs, templates, and management commands.
- `templates/`: base layout and shared pages; app-specific under `stays/templates/stays/`.
- `static/` and `media/`: static assets and uploaded files.
- `db.sqlite3`: local dev database (ignored backups in root).

## Build, Run, and Test
- Setup: `python -m venv .venv && .venv\\Scripts\\activate`
- Install: `pip install -r requirements.txt`
- Migrate: `python manage.py migrate`
- Run: `python manage.py runserver` (app at `/` under namespace `stays`)
- Lint (optional): `./lint_autofix.ps1` or run `ruff` if installed.

## Coding Style & Naming
- Python 3.13, Django 5: 4‑space indents, type-friendly, f-strings.
- Views: function-based in `stays/views.py`.
- URLs: namespaced under `stays` (e.g., `stays:list`, `stays:import_stays_csv`).
- Templates: extend `templates/base.html`; prefer `{% url 'stays:...' %}` over hard paths.

## Testing Guidelines
- Framework: Django `TestCase` (none committed yet).
- Place tests in `stays/tests/` or `stays/tests.py`.
- Name tests `test_*.py`; run with `python manage.py test`.
- Aim for coverage of views (list, map, charts, import/export) and model helpers.

## Commit & PR Guidelines
- Commits: present-tense and scoped (e.g., `fix: add CSV import view`).
- Include rationale when behavior changes; reference issues (e.g., `Fixes #12`).
- PRs: description, reproduction steps, screenshots (for UI), and risk notes.
- Check list: tests pass, no unused files, templates render without `NoReverseMatch`.

## Security & Config Tips
- Do not commit secrets; use env for sensitive settings.
- Uploaded media writes to `media/`; validate CSV inputs.
- Use namespaced URLs to avoid collisions; run `python manage.py check` before pushes.

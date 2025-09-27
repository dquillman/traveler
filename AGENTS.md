# Repository Guidelines

## Project Structure & Module Organization
- Root Django project: `config/` (settings, URLs, WSGI/ASGI).
- App: `stays/` (models, function views in `stays/views.py`, URLs, templates, mgmt commands).
- Templates: shared in `templates/`; app pages in `stays/templates/stays/` and extend `templates/base.html`.
- Assets: `static/` for static files; `media/` for uploads.
- Database: `db.sqlite3` for local dev (backups ignored).

## Build, Test, and Development Commands
- Create venv (Windows): `python -m venv .venv && .venv\Scripts\activate`
- Install deps: `pip install -r requirements.txt`
- Migrations: `python manage.py migrate`
- Run server: `python manage.py runserver` (app at `/` under namespace `stays`).
- Lint (optional): `./lint_autofix.ps1` or `ruff .` if installed.
- System checks: `python manage.py check`

## Coding Style & Naming Conventions
- Python 3.13, Django 5; 4-space indents, add types where practical, prefer f-strings.
- Views: function-based in `stays/views.py`.
- URLs: namespaced under `stays` (e.g., `stays:list`, `stays:import_stays_csv`). Use `{% url 'stays:...' %}` not hard paths.
- Templates: extend `templates/base.html`; keep app-specific under `stays/templates/stays/`.
 - Ratings: list page is read-only; edit rating only via add/edit forms.

## Testing Guidelines
- Framework: Django `TestCase`.
- Location: `stays/tests/` or `stays/tests.py`.
- Naming: `test_*.py` and descriptive test names.
- Run: `python manage.py test`.
- Aim to cover list/map/charts/import-export views and model helpers.

## Commit & Pull Request Guidelines
- Commits: present-tense, scoped (e.g., `fix: add CSV import view`). Include rationale for behavior changes; link issues (e.g., `Fixes #12`).
- PRs: clear description, reproduction steps, screenshots for UI, and risk notes.
- Checklist: tests pass, no unused files, templates render without `NoReverseMatch`.

## Security & Configuration Tips
- Do not commit secrets; use environment variables.
- Validate uploaded CSVs; uploaded files write to `media/`.
- Keep URLs namespaced to avoid collisions.
- Run `python manage.py check` before pushing.

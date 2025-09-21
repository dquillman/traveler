# Traveler Fixed Bundle (Nav + URLs)

This bundle contains safe replacements for:
- templates/base.html  (adds banner menu, guards optional links)
- stays/urls.py        (canonical names: list/add/detail/edit/map/charts)
- config/urls.py       (root redirect to stays:list; includes stays; admin)

## Install (backup first!)

From your project root (`G:\users\daveq\traveler`):

1) Create backups:
   - templates\base.html.bak
   - stays\urls.py.bak
   - config\urls.py.bak

2) Unzip this bundle into the project root, **overwriting** the three files above.

3) Run:
   venv\Scripts\python.exe manage.py runserver

If you have custom routes in config/urls.py, re-add them after the include/redirect lines.

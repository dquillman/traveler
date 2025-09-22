Been There — Overnight Fix Bundle (with Git Push)

1) Unzip into your Django project root (same folder as manage.py)
2) Activate your venv
3) Run:  .\scripts\overnight_fix.ps1
4) A report is created in ./reports and (if in a Git repo) committed on a new branch and pushed to 'origin'.
5) Optional: If GitHub CLI 'gh' is installed and logged in, an issue will be created with the report body.

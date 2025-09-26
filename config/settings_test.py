from .settings import *  # noqa

# Ensure test client host is allowed
ALLOWED_HOSTS = list(ALLOWED_HOSTS) + ["testserver", "localhost"]

# Disable migrations for the stays app to avoid legacy conflicts during tests
MIGRATION_MODULES = dict(globals().get('MIGRATION_MODULES', {}) or {})
MIGRATION_MODULES.update({
    "stays": None,
})

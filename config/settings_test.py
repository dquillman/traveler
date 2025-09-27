from .settings import *  # noqa: F401,F403

# Disable stays app migrations during tests due to historical conflicts.
MIGRATION_MODULES = {
    **globals().get("MIGRATION_MODULES", {}),
    "stays": None,
}

# Faster password hasher for tests
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.MD5PasswordHasher",
]

# Ensure emails don’t try to send
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"


from __future__ import annotations

import subprocess
from datetime import datetime
from django.core.management.base import BaseCommand, CommandError
from django.conf import settings


class Command(BaseCommand):
    help = "Create an annotated git checkpoint tag including the current APP_VERSION. Usage: checkpoint [--push]"

    def add_arguments(self, parser):
        parser.add_argument("--push", action="store_true", help="Push tags to origin after creating")

    def handle(self, *args, **opts):
        version = getattr(settings, "APP_VERSION", None) or "v0.0.0"
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        tag_name = f"checkpoint-{version}-{ts}"
        msg = f"Checkpoint {version} at {ts}"
        try:
            subprocess.check_call(["git", "tag", "-a", tag_name, "-m", msg])
            self.stdout.write(self.style.SUCCESS(f"Created tag {tag_name}"))
            if opts.get("push"):
                subprocess.check_call(["git", "push", "--tags"])
                self.stdout.write(self.style.SUCCESS("Pushed tags to origin"))
        except Exception as e:
            raise CommandError(f"Git tag failed: {e}")


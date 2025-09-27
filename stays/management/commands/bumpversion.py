from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Tuple

from django.core.management.base import BaseCommand, CommandError
from django.conf import settings


SETTINGS_PATH = Path(settings.BASE_DIR) / "config" / "settings.py"


def parse_version(s: str) -> Tuple[int, int, int]:
    s = s.strip().lower().lstrip("v")
    parts = s.split(".")
    if len(parts) != 3:
        raise ValueError("version must be like vX.Y.Z or X.Y.Z")
    return (int(parts[0]), int(parts[1]), int(parts[2]))


def format_version(t: Tuple[int, int, int]) -> str:
    return f"v{t[0]}.{t[1]}.{t[2]}"


class Command(BaseCommand):
    help = "Bump APP_VERSION in config/settings.py and create a git tag. Usage: bumpversion [major|minor|patch|vX.Y.Z] [--push]"

    def add_arguments(self, parser):
        parser.add_argument(
            "level",
            nargs="?",
            default="patch",
            help="One of major|minor|patch or an explicit version like v1.2.3",
        )
        parser.add_argument(
            "--push",
            action="store_true",
            help="If set, attempts to push the branch and tags to origin",
        )

    def handle(self, *args, **opts):
        level = (opts.get("level") or "patch").strip()
        push = bool(opts.get("push"))

        if not SETTINGS_PATH.exists():
            raise CommandError(f"settings not found at {SETTINGS_PATH}")

        text = SETTINGS_PATH.read_text(encoding="utf-8")
        m = re.search(r"^APP_VERSION\s*=\s*\"([^\"]+)\"", text, re.M)
        if not m:
            raise CommandError("APP_VERSION not found in config/settings.py")
        current = m.group(1)
        try:
            major, minor, patch = parse_version(current)
        except Exception as e:
            raise CommandError(f"Invalid current APP_VERSION '{current}': {e}")

        if re.match(r"^v?\d+\.\d+\.\d+$", level):
            new_ver = level if level.startswith("v") else f"v{level}"
        else:
            if level not in {"major", "minor", "patch"}:
                raise CommandError("level must be major|minor|patch or vX.Y.Z")
            if level == "major":
                major, minor, patch = major + 1, 0, 0
            elif level == "minor":
                minor, patch = minor + 1, 0
            else:
                patch += 1
            new_ver = format_version((major, minor, patch))

        if new_ver == current:
            self.stdout.write(self.style.WARNING(f"APP_VERSION already {current}"))
            return

        updated = re.sub(
            r"^APP_VERSION\s*=\s*\"([^\"]+)\"",
            f'APP_VERSION = "{new_ver}"',
            text,
            flags=re.M,
        )
        SETTINGS_PATH.write_text(updated, encoding="utf-8")
        self.stdout.write(self.style.SUCCESS(f"Updated APP_VERSION: {current} -> {new_ver}"))

        # Commit and tag
        try:
            subprocess.check_call(["git", "add", str(SETTINGS_PATH)])
            subprocess.check_call(["git", "commit", "-m", f"chore: bump version to {new_ver}"])
            subprocess.check_call(["git", "tag", "-a", new_ver, "-m", f"Release {new_ver}"])
            self.stdout.write(self.style.SUCCESS(f"Created tag {new_ver}"))
        except Exception as e:
            raise CommandError(f"Git operations failed: {e}")

        if push:
            try:
                subprocess.check_call(["git", "push", "-u", "origin", "--tags"])
                self.stdout.write(self.style.SUCCESS("Pushed branch and tags to origin"))
            except Exception as e:
                raise CommandError(f"Push failed: {e}")


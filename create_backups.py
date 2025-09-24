"""
Script to create timestamped `.bak` backups of specified files.

This script accepts one or more file paths as command‑line arguments and
creates a copy of each file with a `.bak.<timestamp>` suffix appended to
its original filename. For example, `views.py` becomes
`views.py.bak.20250923_114530`.

Usage:
    python create_backups.py path/to/file1.py path/to/file2.py ...

If a file does not exist, the script will report it and continue.
"""

import sys
import shutil
import datetime
from pathlib import Path

def main(args: list[str]) -> None:
    if not args:
        print("Usage: python create_backups.py <file1> <file2> ...")
        return

    # Generate a single timestamp for all backups in this run
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    for file_str in args:
        path = Path(file_str)
        if not path.exists():
            print(f"File not found: {path}")
            continue

        # Construct backup filename by inserting `.bak.<timestamp>` after the suffix
        backup_name = f"{path.name}.bak.{timestamp}"
        backup_path = path.with_name(backup_name)
        
        try:
            shutil.copy2(path, backup_path)
            print(f"Backed up {path} -> {backup_path}")
        except Exception as exc:
            print(f"Failed to back up {path}: {exc}")


if __name__ == "__main__":
    main(sys.argv[1:])
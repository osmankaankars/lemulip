#!/usr/bin/env python3
"""Create a source ZIP from the same checked public file list as the publisher."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import zipfile

import privacy_check

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        help="Create a new source ZIP at this path; never replace a file")
    options = parser.parse_args()
    names = json.loads(subprocess.check_output(
        [sys.executable, str(ROOT / "script/privacy_check.py"), "--list-files"], cwd=ROOT
    ))
    with (ROOT / "Resources/Info.plist").open("rb") as stream:
        version = plistlib.load(stream)["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
        raise ValueError("Invalid source version")

    # Read and validate the exact bytes that will be packaged. Never archive Git
    # history, build products, symlinks, owner names, or extended attributes.
    entries: list[tuple[str, bytes, int]] = []
    for name in names:
        path = ROOT / name
        relative = Path(name)
        if any((ROOT / Path(*relative.parts[:index])).is_symlink()
               for index in range(1, len(relative.parts) + 1)):
            raise ValueError("A source path changed to a symlink")
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as stream:
            information = os.fstat(stream.fileno())
            if not stat.S_ISREG(information.st_mode) or information.st_size > privacy_check.size_limit(name):
                raise ValueError("A source file changed during packaging")
            data = stream.read(privacy_check.size_limit(name) + 1)
        failures = privacy_check.content_failures(name, data)
        if failures:
            raise ValueError("Source content failed the public privacy check: " + failures[0])
        mode = 0o755 if information.st_mode & 0o111 else 0o644
        entries.append((name, data, mode))

    output = options.output if options.output else ROOT / "dist" / f"Freewheel-{version}-Source.zip"
    if not output.is_absolute():
        output = ROOT / output
    if output.suffix != ".zip":
        raise ValueError("Source output must be a ZIP file")
    output_folder = output.parent
    if output_folder.is_symlink():
        raise ValueError("Output directory must not be a symlink")
    output_folder.mkdir(exist_ok=True)
    # Exclusive creation preserves any earlier source package.
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data, mode in entries:
            entry = zipfile.ZipInfo("Freewheel/" + name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | mode) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    print(f"Created {output.name}: {len(entries)} checked source files")
    print("SHA256 " + hashlib.sha256(output.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError):
        print("Source packaging stopped. Resolve the reported privacy or file error; existing archives are preserved.", file=sys.stderr)
        raise SystemExit(1)

#!/usr/bin/env python3
"""Package banian_stretch/src into dist/banian_stretch_v<VERSION>.rbz.

Usage: python3 banian_stretch/tools/build_rbz.py
"""
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DIST = ROOT / "dist"
LOADER = SRC / "banian_stretch.rb"


def main() -> int:
    match = re.search(r"VERSION\s*=\s*'([^']+)'", LOADER.read_text(encoding="utf-8"))
    if not match:
        print("VERSION not found in loader", file=sys.stderr)
        return 1
    version = match.group(1)
    DIST.mkdir(exist_ok=True)
    out = DIST / f"banian_stretch_v{version}.rbz"

    files = [LOADER] + sorted(p for p in (SRC / "banian_stretch").rglob("*") if p.is_file())
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as rbz:
        for path in files:
            rbz.write(path, path.relative_to(SRC).as_posix())
    print(f"{out.relative_to(ROOT.parent)}  ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

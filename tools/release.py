#!/usr/bin/env python3
"""Build the source archive with a SHA-256 inventory (SHA256SUMS.txt inside the archive).

The archive holds no build output: setup.sh / Setup-Windows.cmd download the engine and build the
packs on the target computer. Ready-to-run packages are made by packaging/build_appimage.py and
packaging/build_windows_installer.py.

    python3 tools/release.py [--out dist/OpenExhibit-Studio-0.3.0-source.zip]
"""

import argparse
import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.3.0"
# Created by setup, builds and tools; never part of the source.
IGNORED = {
    ".git",
    ".godot",
    "__pycache__",
    "node_modules",
    "dist",
    ".venv",
    "downloads",
    ".ruff_cache",
    "bin",
}


def files():
    for path in sorted(ROOT.rglob("*")):
        rel = path.relative_to(ROOT)
        if (
            not path.is_file()
            or IGNORED.intersection(rel.parts)
            or rel.suffix in {".pyc", ".bak"}
            or ".writing-" in path.name
            or rel.as_posix() == "SHA256SUMS.txt"  # written fresh into the archive
        ):
            continue
        yield path, rel.as_posix()


def build(out: Path) -> None:
    for required in ["tools/contest/museum.quiz.json", "docs/TEST-RESULTS.md"]:
        if not (ROOT / required).is_file():
            raise FileNotFoundError(required)
    out = out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        sums = []
        for path, name in files():
            if path.resolve() == out:
                continue
            archive.write(path, "OpenExhibitStudio/" + name)
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1 << 20), b""):
                    digest.update(chunk)
            sums.append(f"{digest.hexdigest()}  {name}\n")
        archive.writestr("OpenExhibitStudio/SHA256SUMS.txt", "".join(sums))
    print(out.name, out.stat().st_size, "bytes", flush=True)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    cli.add_argument("--out", type=Path, default=ROOT / "dist" / f"OpenExhibit-Studio-{VERSION}-source.zip")
    cli.add_argument("--source", action="store_true", help=argparse.SUPPRESS)  # accepted for old scripts
    build(cli.parse_args().out)

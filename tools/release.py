#!/usr/bin/env python3
"""Build complete, Windows portable or source distributions with SHA-256 inventories.

The source archive holds no build output: setup.sh / Setup-Windows.cmd download the engine
and build the packs on the target computer.
"""

import argparse
import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.3.0"


def files(kind):
    # .venv and downloads/ are created by setup; bin/ holds build output and the engine.
    ignored = {".git", ".godot", "__pycache__", "node_modules", "dist", ".venv", "downloads", ".ruff_cache"}
    for path in sorted(ROOT.rglob("*")):
        rel = path.relative_to(ROOT)
        if (
            not path.is_file()
            or ignored.intersection(rel.parts)
            or rel.suffix in {".pyc", ".bak"}
            or ".writing-" in path.name
            or rel.as_posix() == "SHA256SUMS.txt"  # written fresh into every archive
        ):
            continue
        if kind == "source" and rel.parts[0] == "bin":
            continue
        if kind == "windows":
            if rel.parts[0] == "bin":
                if len(rel.parts) < 3 or rel.parts[1] != "windows":
                    continue
                rel = Path("bin", *rel.parts[2:])
            elif rel.parts[0] in {"app", "tests"} and rel.parts[:2] != ("tests", "results"):
                continue
            elif len(rel.parts) == 1 and rel.name not in {
                "LICENSE",
                "README.md",
                "Studio.cmd",
                "Player.cmd",
                "Setup-Windows.cmd",
            }:
                continue
        yield path, rel.as_posix()


def build(path, kind):
    needed = ["tools/contest/museum.quiz.json", "docs/TEST-RESULTS.md"]
    if kind != "source":
        needed += [
            "bin/studio.pck",
            "bin/player.pck",
            "bin/windows/studio.pck",
            "bin/windows/player.pck",
            "bin/windows/godot.exe",
            "bin/windows/python/python.exe",
        ]
    if kind == "complete":
        needed.append("bin/godot")
    for rel in needed:
        if not (ROOT / rel).is_file():
            raise FileNotFoundError(rel)
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as arc:
        sums = []
        for file, name in files(kind):
            if file.resolve() == path:
                continue
            arc.write(file, "OpenExhibitStudio/" + name)
            with file.open("rb") as stream:
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1048576), b""):
                    digest.update(chunk)
            sums.append(digest.hexdigest() + "  " + name + "\n")
        arc.writestr("OpenExhibitStudio/SHA256SUMS.txt", "".join(sums))
    print(kind, path.name, path.stat().st_size, "bytes", flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", type=Path, default=ROOT / "dist" / f"OpenExhibit-Studio-{VERSION}.zip")
    group = p.add_mutually_exclusive_group()
    group.add_argument("--windows", action="store_true")
    group.add_argument("--source", action="store_true")
    a = p.parse_args()
    build(a.out, "windows" if a.windows else "source" if a.source else "complete")

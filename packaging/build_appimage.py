#!/usr/bin/env python3
"""Build OpenExhibit-Studio-<version>-x86_64.AppImage.

The image holds the official Godot 4.7.1 Linux engine, Studio and Player packs exported with that
engine, the examples, services, firmware and documentation, and the pure-Python serial and MQTT
libraries (pylib/). The live-audience and hardware services run with the system's python3.

It is assembled with mksquashfs (apt install squashfs-tools) and the AppImage type-2 runtime, so no
downloaded build tool runs during the build.

    python3 packaging/build_appimage.py [--out FILE] [--runtime FILE] [--offline] [--appdir DIR]
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import runtimes

HERE = Path(__file__).resolve().parent
# The type-2 runtime is published only as a rolling "continuous" build, so it cannot be pinned by
# version; the build prints its SHA-256. Pass --runtime to use a copy you keep.
RUNTIME_URL = "https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64"


def sha256(path: Path) -> str:
    return runtimes.file_digest(path, "sha256")


def runtime_file(explicit: Path | None, cache: Path, offline: bool) -> Path:
    if explicit:
        return explicit
    cached = cache / "appimage-runtime-x86_64"
    if not cached.is_file():
        if offline:
            raise SystemExit(f"{cached} is missing (offline build); pass --runtime FILE.")
        cache.mkdir(parents=True, exist_ok=True)
        print("Downloading the AppImage runtime …", flush=True)
        with urllib.request.urlopen(RUNTIME_URL, timeout=120) as response, cached.open("wb") as out:
            shutil.copyfileobj(response, out)
    return cached


def assemble(appdir: Path, cache: Path, offline: bool) -> None:
    """Lay out the AppDir: AppImage metadata at the top, the application under usr/lib/openexhibit."""
    base = appdir / "usr" / "lib" / "openexhibit"
    engine_zip = runtimes.fetch("godot-linux", cache, offline)
    engine = runtimes.extract_member(engine_zip, "Godot_v4.7.1-stable_linux.x86_64", base / "bin" / "godot")
    runtimes.build_packs(engine, "linux", base / "bin")
    runtimes.copy_payload(base)
    runtimes.install_wheels(base / "pylib", cache, offline)

    shutil.copy2(HERE / "appimage" / "AppRun", appdir / "AppRun")
    (appdir / "AppRun").chmod(0o755)
    desktop = HERE / "appimage" / "openexhibit-studio.desktop"
    shutil.copy2(desktop, appdir / desktop.name)
    shutil.copy2(HERE / "openexhibit.png", appdir / "openexhibit.png")
    (appdir / ".DirIcon").symlink_to("openexhibit.png")
    for folder, source in [
        ("usr/share/applications", desktop),
        ("usr/share/icons/hicolor/256x256/apps", HERE / "openexhibit.png"),
    ]:
        (appdir / folder).mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, appdir / folder / source.name)


def pack(appdir: Path, runtime: Path, out: Path) -> None:
    """AppImage = runtime ELF followed directly by a squashfs image of the AppDir."""
    with tempfile.TemporaryDirectory(prefix="openexhibit-squashfs-") as tmp:
        image = Path(tmp) / "AppDir.squashfs"
        subprocess.run(
            ["mksquashfs", str(appdir), str(image), "-root-owned", "-noappend", "-no-xattrs"]
            + ["-comp", "zstd", "-Xcompression-level", "19", "-quiet", "-no-progress"],
            check=True,
        )
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("wb") as target:
            for part in (runtime, image):
                with part.open("rb") as source:
                    shutil.copyfileobj(source, target)
    out.chmod(0o755)


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    default = runtimes.ROOT / "dist" / f"OpenExhibit-Studio-{runtimes.VERSION}-x86_64.AppImage"
    cli.add_argument("--out", type=Path, default=default)
    cli.add_argument("--runtime", type=Path, help="AppImage type-2 runtime to use (default: download)")
    cli.add_argument("--cache", type=Path, default=runtimes.CACHE)
    cli.add_argument("--offline", action="store_true")
    cli.add_argument("--appdir", type=Path, help="keep the assembled AppDir here (must not exist)")
    options = cli.parse_args()
    if not shutil.which("mksquashfs"):
        cli.error("mksquashfs not found: sudo apt install squashfs-tools")
    runtime = runtime_file(options.runtime, options.cache, options.offline)
    with tempfile.TemporaryDirectory(prefix="openexhibit-appdir-") as tmp:
        appdir = options.appdir or Path(tmp) / "AppDir"
        appdir.mkdir(parents=True)
        assemble(appdir, options.cache, options.offline)
        pack(appdir, runtime, options.out.resolve())
    size = options.out.stat().st_size / 1e6
    print(f"Built {options.out} ({size:.1f} MB)")
    print(f"  sha256 {sha256(options.out)}")
    print(f"  runtime sha256 {sha256(runtime)}")


if __name__ == "__main__":
    main()

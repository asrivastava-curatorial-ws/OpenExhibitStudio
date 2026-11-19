#!/usr/bin/env python3
"""Pinned third-party files that go into the AppImage and the Windows installer.

Each file is downloaded once into a cache folder (default: downloads/, shared with setup.sh) and
checked against the digest below before use, so a build uses exactly these bytes or stops.

    python3 packaging/runtimes.py              # fetch and verify everything (e.g. before going offline)
    python3 packaging/runtimes.py --offline    # only verify what is already in the cache
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "downloads"
VERSION = "0.3.0"


@dataclass(frozen=True)
class Download:
    name: str
    base_url: str
    algorithm: str
    digest: str

    @property
    def url(self) -> str:
        return self.base_url + urllib.parse.quote(self.name)


GODOT = "https://github.com/godotengine/godot/releases/download/4.7.1-stable/"
# Official CPython builds from python-build-standalone (the builds uv installs); digests from the
# release's SHA256SUMS.
CPYTHON = "https://github.com/astral-sh/python-build-standalone/releases/download/20260718/"
PYPI = "https://files.pythonhosted.org/packages/"

RUNTIMES = {
    "godot-linux": Download(
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        GODOT,
        "sha512",
        "4ccdab7a48eeccbe8819a2fc1f6262f8d72065d98601bcb3743fcbd7ebd39f37"
        "3758a788ee3293a05ec5b2c48538266c437404312e372225cd2df273945a2de9",
    ),
    "godot-windows": Download(
        "Godot_v4.7.1-stable_win64.exe.zip",
        GODOT,
        "sha512",
        "a6b02c527c18ba9936e63562032701432b2dc57d98d6483ceaccb00fe14af16a"
        "f5773ae8a55e7b4d614edf121c4d9e420d870f804edb1dac16362298a01ce6c4",
    ),
    "python-windows": Download(
        "cpython-3.12.13+20260718-x86_64-pc-windows-msvc-install_only_stripped.tar.gz",
        CPYTHON,
        "sha256",
        "0d422a1439ec308e03f47df551bc30f5994727c456e414b026d202bcda9b7c1c",
    ),
    "pyserial": Download(
        "pyserial-3.5-py2.py3-none-any.whl",
        PYPI + "07/bc/587a445451b253b285629263eb51c2d8e9bcea4fc97826266d186f96f558/",
        "sha256",
        "c4451db6ba391ca6ca299fb3ec7bae67a5c55dde170964c7a14ceefec02f2cf0",
    ),
    "paho-mqtt": Download(
        "paho_mqtt-2.1.0-py3-none-any.whl",
        PYPI + "c4/cb/00451c3cf31790287768bb12c6bec834f5d292eaf3022afc88e14b8afc94/",
        "sha256",
        "6db9ba9b34ed5bc6b6e3812718c7e06e2fd7444540df2455d2c51bd58808feee",
    ),
}
# Pure-Python libraries for USB serial and MQTT, bundled with both packages.
HARDWARE_WHEELS = ("pyserial", "paho-mqtt")

# Parts of the Windows CPython build that OpenExhibit never uses (tests, Tk, headers, import libs).
PYTHON_WINDOWS_UNUSED = [
    "include",
    "libs",
    "tcl",
    "Lib/test",
    "Lib/idlelib",
    "Lib/tkinter",
    "Lib/turtledemo",
    "Lib/turtle.py",
    "DLLs/_tkinter.pyd",
    "DLLs/tcl86t.dll",
    "DLLs/tk86t.dll",
]


def file_digest(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(key: str, cache: Path = CACHE, offline: bool = False) -> Path:
    """Return the verified cached file for `key`, downloading it first when needed."""
    item = RUNTIMES[key]
    target = cache / item.name
    if not target.is_file():
        if offline:
            raise SystemExit(f"{item.name} is missing from {cache} (offline build).")
        cache.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {item.name} …", flush=True)
        with tempfile.NamedTemporaryFile(dir=cache, prefix=".partial-", delete=False) as handle:
            partial = Path(handle.name)
            try:
                with urllib.request.urlopen(item.url, timeout=120) as response:
                    shutil.copyfileobj(response, handle)
            except BaseException:
                partial.unlink(missing_ok=True)
                raise
        partial.replace(target)
    actual = file_digest(target, item.algorithm)
    if actual != item.digest:
        raise SystemExit(
            f"{target} does not match its pinned {item.algorithm.upper()} (got {actual}). "
            "Delete it and run the build again."
        )
    return target


def extract_member(archive: Path, member: str, destination: Path, mode: int = 0o755) -> Path:
    """Copy one file out of a zip archive (used for the Godot executables)."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle, bundle.open(member) as source, destination.open("wb") as out:
        shutil.copyfileobj(source, out)
    destination.chmod(mode)
    return destination


def install_wheels(target: Path, cache: Path = CACHE, offline: bool = False) -> None:
    """Install the pinned pure-Python hardware libraries into `target` with this machine's pip.

    The wheels are platform-independent, so the same files serve Linux and Windows.
    """
    wheels = [str(fetch(key, cache, offline)) for key in HARDWARE_WHEELS]
    target.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--quiet",
            "--no-index",
            "--no-deps",
            "--no-compile",
            "--disable-pip-version-check",
            "--root-user-action=ignore",
            "--target",
            str(target),
            *wheels,
        ],
        check=True,
    )
    shutil.rmtree(target / "bin", ignore_errors=True)  # console scripts with this machine's paths
    for record in target.glob("*.dist-info/direct_url.json"):
        record.unlink()  # would only record this build machine's download folder


def install_windows_python(destination: Path, cache: Path = CACHE, offline: bool = False) -> None:
    """Unpack the Windows CPython build into `destination` (python.exe at its top) and add the
    hardware libraries to its site-packages. Nothing in it is executed here."""
    archive = fetch("python-windows", cache, offline)
    if destination.exists():
        shutil.rmtree(destination)
    with tempfile.TemporaryDirectory(prefix="openexhibit-python-") as tmp:
        with tarfile.open(archive) as bundle:
            bundle.extractall(tmp, filter="data")
        shutil.move(str(Path(tmp) / "python"), destination)
    for relative in PYTHON_WINDOWS_UNUSED:
        path = destination / relative
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    for test_module in (destination / "DLLs").glob("_test*.pyd"):
        test_module.unlink()
    if not (destination / "python.exe").is_file():
        raise SystemExit("Unexpected layout in the Windows CPython archive (python.exe not found).")
    install_wheels(destination / "Lib" / "site-packages", cache, offline)


def build_packs(engine: Path, platform: str, out: Path) -> None:
    """Export studio.pck and player.pck with the given Godot executable."""
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools" / "build.py"),
            "--godot",
            str(engine),
            "--platform",
            platform,
            "--mode",
            "packs",
            "--out",
            str(out),
        ],
        check=True,
    )


# What both packages ship from the source tree, relative to the repository root.
PAYLOAD_DIRS = ["examples", "tools", "gateway", "firmware", "docs", "licenses"]
PAYLOAD_FILES = ["README.md", "LICENSE", "CHANGELOG.md"]
SKIPPED_PARTS = {"__pycache__", "node_modules", ".pytest_cache"}


def copy_payload(destination: Path, extra_files: tuple[str, ...] = ()) -> None:
    """Copy the documentation, examples, services and firmware next to the engine."""
    for name in PAYLOAD_DIRS:
        shutil.copytree(
            ROOT / name,
            destination / name,
            ignore=shutil.ignore_patterns(*SKIPPED_PARTS, "*.pyc"),
            dirs_exist_ok=True,
        )
    shutil.rmtree(destination / "tools" / "dev", ignore_errors=True)  # developer helpers only
    for name in (*PAYLOAD_FILES, *extra_files):
        shutil.copy2(ROOT / name, destination / name)


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    cli.add_argument("--cache", type=Path, default=CACHE)
    cli.add_argument("--offline", action="store_true", help="verify the cache without downloading")
    cli.add_argument(
        "keys", nargs="*", metavar="NAME", help="any of: " + ", ".join(RUNTIMES) + " (default: all)"
    )
    options = cli.parse_args()
    unknown = sorted(set(options.keys) - set(RUNTIMES))
    if unknown:
        cli.error("unknown name(s): " + ", ".join(unknown))
    for key in options.keys or RUNTIMES:
        path = fetch(key, options.cache, options.offline)
        print(f"ok  {RUNTIMES[key].algorithm}  {path.name}")


if __name__ == "__main__":
    main()

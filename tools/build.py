#!/usr/bin/env python3
"""Build independent Godot data packs, portable Linux runtime, or native exports."""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.3.0"


def run(argv):
    result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode or "SCRIPT ERROR:" in result.stdout or "ERROR:" in result.stdout:
        print(result.stdout, file=sys.stderr)
        raise RuntimeError("Build failed: " + " ".join(map(str, argv)))
    return result.stdout


def preset(name, platform):
    return f'''[preset.0]
name="{name}"
platform="{platform}"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=""
binary_format/embed_pck=false
binary_format/architecture="x86_64"
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
application/modify_resources=false
'''


def build(engine, dest, mode, platform):
    engine = str(Path(shutil.which(engine) or engine).resolve(strict=True))
    version = subprocess.check_output([engine, "--version"], text=True).strip()
    if not version.startswith(("4.7.1.", "4.6.3.")):
        print(f"Building with {version}; 0.3.0 was verified with 4.7.1 (and 4.6.3).", file=sys.stderr)
    dest = dest.resolve()
    dest.mkdir(parents=True, exist_ok=True)
    target = "Windows Desktop" if platform == "windows" else "Linux"
    with tempfile.TemporaryDirectory(prefix="openexhibit-build-") as tmp:
        for role in ("player", "studio"):
            stage = Path(tmp) / role
            stage.mkdir()
            for name in ["core", "player", "assets"] + (["studio"] if role == "studio" else []):
                shutil.copytree(
                    ROOT / "app" / name, stage / name, ignore=shutil.ignore_patterns("*.uid", "*.import")
                )
            config = (ROOT / "app/project.godot").read_text()
            if role == "player":
                config = config.replace("OpenExhibit Studio", "OpenExhibit Player").replace(
                    "res://studio/studio.tscn", "res://player/player.tscn"
                )
            (stage / "project.godot").write_text(config)
            (stage / "export_presets.cfg").write_text(preset("Release", target))
            run([engine, "--headless", "--path", str(stage), "--editor", "--import"])
            if mode == "native":
                out = dest / ("OpenExhibit" + role.title() + (".exe" if platform == "windows" else ""))
                flag = "--export-release"
            else:
                out = dest / (role + ".pck")
                flag = "--export-pack"
            run([engine, "--headless", "--path", str(stage), flag, "Release", str(out)])
            if not out.is_file() or out.stat().st_size < 1024:
                raise RuntimeError("Missing " + str(out))
            print("Built", out.name, out.stat().st_size, flush=True)
    if mode == "portable":
        if platform != "linux" or not sys.platform.startswith("linux"):
            raise ValueError("Build --mode portable on the Linux host.")
        shutil.copy2(engine, dest / "godot")
        (dest / "godot").chmod(0o755)
        print("Bundled Godot", version)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--godot", default="godot")
    p.add_argument("--out", type=Path, default=ROOT / "bin")
    p.add_argument("--mode", choices=["packs", "portable", "native"], default="packs")
    p.add_argument(
        "--platform", choices=["linux", "windows"], default="windows" if os.name == "nt" else "linux"
    )
    a = p.parse_args()
    build(a.godot, a.out, a.mode, a.platform)

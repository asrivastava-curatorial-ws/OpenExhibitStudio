#!/usr/bin/env python3
"""Render one calibrated feed from a calibrated Godot viewport at deterministic show time."""

import argparse
import json
import zipfile
import shutil
import os
import tempfile
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("project", type=Path)
    p.add_argument("output_id")
    p.add_argument("movie", type=Path)
    p.add_argument("--frames", type=int, default=120)
    p.add_argument("--fps", type=int, default=24)
    p.add_argument("--godot", default="godot")
    a = p.parse_args()
    if a.movie.suffix.lower() not in (".avi", ".png") or not 1 <= a.fps <= 120 or a.frames < 1:
        p.error("Choose .avi or .png and positive frames/fps.")
    a.movie.parent.mkdir(parents=True, exist_ok=True)
    if a.project.suffix.lower() == ".oex":
        with zipfile.ZipFile(a.project) as arc:
            project = json.loads(arc.read("project.oes.json"))
    else:
        project = json.loads(a.project.read_text(encoding="utf8"))
    output = next((o for o in project["installation"]["outputs"] if o["id"] == a.output_id), None)
    if not output:
        p.error("Unknown output ID.")
    pack = ROOT / "bin/player.pck"
    launch = (
        ["--path", str(ROOT / "app")] if (ROOT / "app/project.godot").exists() else ["--main-pack", str(pack)]
    )
    engine = ROOT / "bin" / ("godot.exe" if os.name == "nt" else "godot")
    engine = str(engine) if a.godot == "godot" and engine.exists() else a.godot
    if a.movie.suffix.lower() == ".avi" and not shutil.which("ffmpeg"):
        p.error("Install FFmpeg to encode AVI, or choose .png for an image sequence.")
    with tempfile.TemporaryDirectory() as temp:
        prefix = (
            str(a.movie.resolve().with_suffix("")) + "-"
            if a.movie.suffix.lower() == ".png"
            else str(Path(temp) / "frame-")
        )
        cmd = [
            engine,
            *launch,
            "--script",
            "res://player/render_frames.gd",
            "--fixed-fps",
            str(a.fps),
            "--audio-driver",
            "Dummy",
            "--",
            "--project",
            str(a.project.resolve()),
            "--output",
            a.output_id,
            "--frames",
            str(a.frames),
            "--fps",
            str(a.fps),
            "--prefix",
            prefix,
        ]
        subprocess.run(cmd, check=True)
        if a.movie.suffix.lower() == ".avi":
            subprocess.run(
                [
                    "ffmpeg",
                    "-v",
                    "error",
                    "-y",
                    "-framerate",
                    str(a.fps),
                    "-i",
                    prefix + "%06d.png",
                    "-an",
                    "-c:v",
                    "ffv1",
                    str(a.movie.resolve()),
                ],
                check=True,
            )

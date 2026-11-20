#!/usr/bin/env python3
"""Rebuild examples/16-green-screen: two short looping sample videos, one sample picture and the
project file. The samples are drawn here (no third-party footage); exhibits use their own media.

Needs NumPy, Pillow and FFmpeg with libvpx-vp9.   python3 tools/dev/make_booth_samples.py
"""

from __future__ import annotations

import hashlib
import json
import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "examples" / "16-green-screen"
W, H, FPS, SECONDS = 1280, 720, 24, 6
FRAMES = FPS * SECONDS
Y, X = np.mgrid[0:H, 0:W].astype(np.float32)


def encode(name: str, frames) -> None:
    """Pipe RGB frames to FFmpeg as a small VP9 WebM that loops seamlessly."""
    target = OUT / "assets" / name
    command = ["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24"]
    command += ["-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-an", "-c:v", "libvpx-vp9", "-b:v", "0"]
    command += [
        "-crf",
        "36",
        "-row-mt",
        "1",
        "-deadline",
        "good",
        "-cpu-used",
        "2",
        "-pix_fmt",
        "yuv420p",
        str(target),
    ]
    with subprocess.Popen(command, stdin=subprocess.PIPE) as ffmpeg:
        for frame in frames:
            ffmpeg.stdin.write(np.clip(frame, 0, 255).astype(np.uint8).tobytes())
        ffmpeg.stdin.close()
    if ffmpeg.returncode:
        raise SystemExit(f"FFmpeg failed for {name}")


def gradient(top, bottom):
    t = (Y / (H - 1))[..., None]
    return np.array(top, np.float32) * (1 - t) + np.array(bottom, np.float32) * t


def space():
    """Twinkling stars and a banded planet turning once per loop."""
    rng = np.random.default_rng(16)
    sky = gradient((4, 6, 16), (12, 22, 52))
    glow = np.exp(-(((X - 260) / 420) ** 2 + ((Y - 160) / 260) ** 2))[..., None] * np.array((60, 26, 90))
    sky = sky + glow
    stars = rng.integers([0, 0], [W - 1, H - 1], size=(420, 2))
    bright = rng.uniform(90, 255, 420)
    speed = rng.integers(1, 4, 420)
    phase = rng.uniform(0, 2 * math.pi, 420)
    cx, cy, radius = 960.0, 430.0, 250.0
    nx, ny = (X - cx) / radius, (Y - cy) / radius
    inside = nx**2 + ny**2 <= 1
    nz = np.sqrt(np.clip(1 - nx**2 - ny**2, 0, 1))
    light = np.clip(-0.55 * nx - 0.45 * ny + 0.7 * nz, 0, 1) ** 0.8
    latitude = np.arcsin(np.clip(ny, -1, 1))
    longitude = np.arctan2(nx, nz)
    for i in range(FRAMES):
        turn = 2 * math.pi * i / FRAMES
        frame = sky.copy()
        twinkle = bright * (0.65 + 0.35 * np.sin(speed * turn + phase))
        for dy, dx, share in [(0, 0, 1.0), (0, 1, 0.45), (1, 0, 0.45)]:
            frame[stars[:, 1] + dy, stars[:, 0] + dx] = np.maximum(
                frame[stars[:, 1] + dy, stars[:, 0] + dx], (twinkle * share)[:, None]
            )
        bands = 0.5 + 0.5 * np.sin(latitude * 9 + 0.6 * np.sin(longitude * 3 + turn))
        surface = np.stack([200 + 40 * bands, 130 + 50 * bands, 80 + 30 * bands], axis=-1)
        planet = surface * (0.12 + 0.88 * light)[..., None]
        frame[inside] = planet[inside]
        yield frame


def ocean():
    """Moving light ripples, sun rays and bubbles rising through blue water."""
    rng = np.random.default_rng(17)
    water = gradient((18, 92, 150), (3, 22, 48))
    depth = 1 - Y / H
    floor_line = H - 70 - 26 * np.sin(X / 150) - 14 * np.sin(X / 47 + 1.3)
    sand = (Y > floor_line)[..., None]
    count = 46
    bx = rng.uniform(40, W - 40, count)
    by = rng.uniform(0, H, count)
    size = rng.uniform(5, 15, count)
    laps = rng.integers(1, 3, count)  # whole trips per loop keeps the loop seamless
    wobble = rng.uniform(0, 2 * math.pi, count)
    for i in range(FRAMES):
        turn = 2 * math.pi * i / FRAMES
        ripples = np.sin(X / 37 + np.sin(Y / 53 + turn) * 2 + turn) * np.sin(Y / 41 - turn + np.sin(X / 71))
        frame = water + (np.clip(ripples, 0, 1) ** 3 * 70 * depth**2)[..., None]
        rays = np.clip(np.sin((X + 0.45 * Y) / 90 + np.sin(turn) * 0.8), 0, 1) ** 6
        frame = frame + (rays * 45 * depth)[..., None]
        frame = np.where(sand, np.array((120, 104, 70), np.float32) * (0.55 + 0.3 * depth)[..., None], frame)
        for j in range(count):
            y = (by[j] - laps[j] * (H + 60) * i / FRAMES) % (H + 60) - 30
            x = bx[j] + 10 * math.sin(turn * 2 + wobble[j])
            r = size[j]
            x0, x1 = int(max(0, x - r - 2)), int(min(W, x + r + 3))
            y0, y1 = int(max(0, y - r - 2)), int(min(H, y + r + 3))
            if x0 >= x1 or y0 >= y1:
                continue
            d = np.hypot(X[y0:y1, x0:x1] - x, Y[y0:y1, x0:x1] - y)
            ring = np.clip(1 - np.abs(d - r) / 1.6, 0, 1) * 0.8 + (d < r * 0.35) * 0.35
            frame[y0:y1, x0:x1] += ring[..., None] * np.array((200, 230, 255)) * 0.6
        yield frame


def sunset() -> Image.Image:
    """A still picture: evening sky, sun and three layers of hills."""
    w, h = 1920, 1080
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = yy / h
    sky = np.stack([255 - 60 * t, 150 - 40 * t + 40 * (1 - t) ** 3, 120 + 40 * t], axis=-1)
    sun = np.exp(-(((xx - 1300) ** 2 + (yy - 560) ** 2) / (2 * 140**2)))[..., None] * np.array((60, 50, 10))
    disc = ((xx - 1300) ** 2 + (yy - 560) ** 2 < 95**2)[..., None]
    image = np.where(disc, np.array((255, 236, 180), np.float32), sky + sun)
    for height, colour, waves in [
        (660, (120, 70, 110), (230, 90)),
        (780, (80, 44, 84), (170, 55)),
        (900, (40, 24, 50), (120, 40)),
    ]:
        ridge = height + 60 * np.sin(xx / waves[0]) + 30 * np.sin(xx / waves[1] + 2)
        image = np.where((yy > ridge)[..., None], np.array(colour, np.float32), image)
    return Image.fromarray(np.clip(image, 0, 255).astype(np.uint8))


def project(assets: dict) -> dict:
    base = json.loads((ROOT / "examples" / "15-live-show" / "project.oes.json").read_text(encoding="utf-8"))
    text = "Step in front of the green screen, choose a world and take a photo or a short video to keep."
    return {
        **{k: base[k] for k in ("format", "version", "canvas", "variables", "rules", "timelines", "devices")},
        "title": "Step into another world",
        "start": "main",
        "assets": assets,
        "scenes": [
            {
                "id": "main",
                "name": "Booth welcome",
                "background": "#0d1117",
                "objects": [
                    {
                        "id": "title",
                        "name": "Title",
                        "kind": "text",
                        "rect": [80, 180, 1120, 120],
                        "text": "Step into another world",
                        "font": 64,
                        "color": "#e6edf3",
                        "align": 1,
                    },
                    {
                        "id": "help",
                        "name": "Help",
                        "kind": "text",
                        "rect": [140, 330, 1000, 160],
                        "text": text,
                        "font": 30,
                        "color": "#8b949e",
                        "align": 1,
                    },
                ],
            }
        ],
        "installation": base["installation"],
        "settings": {"idle_seconds": 0, "autoplay": ""},
        "extensions": {
            "greenscreen": {
                "title": "Step into another world",
                "backgrounds": [
                    {"asset": "space", "name": "Deep space", "fit": "cover"},
                    {"asset": "ocean", "name": "Under the sea", "fit": "cover"},
                    {"asset": "sunset", "name": "Sunset hills", "fit": "cover"},
                ],
                "photo": True,
                "clip": True,
                "clip_seconds": 8,
                "countdown": 3,
                "keep_minutes": 30,
                "cycle_seconds": 20,
                "mirror": True,
            }
        },
    }


def main() -> None:
    (OUT / "assets").mkdir(parents=True, exist_ok=True)
    encode("space.webm", space())
    encode("ocean.webm", ocean())
    sunset().save(OUT / "assets" / "sunset.jpg", quality=88, optimize=True)
    assets = {}
    for asset_id, name in [("space", "space.webm"), ("ocean", "ocean.webm"), ("sunset", "sunset.jpg")]:
        data = (OUT / "assets" / name).read_bytes()
        assets[asset_id] = {"path": f"assets/{name}", "sha256": hashlib.sha256(data).hexdigest()}
        print(f"{name}: {len(data) / 1024:.0f} KiB")
    (OUT / "project.oes.json").write_text(json.dumps(project(assets), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

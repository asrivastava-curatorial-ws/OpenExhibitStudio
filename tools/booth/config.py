"""Green-screen booth settings and the background media an exhibit provides.

Settings are always cleaned, never rejected: a value of the wrong type or out of range falls back
to its default or is clamped, so a hand-edited project or the setup page cannot break the booth.
"""

from __future__ import annotations

import json
import re
import zipfile
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

VIDEO_TYPES = {".webm": "video/webm", ".mp4": "video/mp4", ".m4v": "video/mp4"}
IMAGE_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}
FITS = ("cover", "contain")
GREEN = "#00b140"

DEFAULTS = {
    "title": "Green screen",
    "photo": True,
    "clip": True,
    "clip_seconds": 8,
    "countdown": 3,
    "keep_minutes": 30,
    "cycle_seconds": 20,
    "mirror": True,
    "camera": "",
    # Tolerance and softness are distances in the CbCr colour plane; see booth/web/keyer.js.
    "key": {"color": GREEN, "tolerance": 0.22, "softness": 0.1, "spill": 0.6},
    # Where the camera picture sits: x/y place its bottom centre (0–1 of the screen), scale is its
    # height relative to the screen, crop trims left/top/right/bottom edges of the camera frame.
    "person": {"scale": 1.0, "x": 0.5, "y": 1.0, "crop": [0.0, 0.0, 0.0, 0.0]},
}


def _number(value, low: float, high: float, default: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value != value:
        return default
    return round(min(high, max(low, float(value))), 4)


def _flag(value, default: bool) -> bool:
    return value if isinstance(value, bool) else default


def _text(value, limit: int, default: str) -> str:
    return value.strip()[:limit] if isinstance(value, str) and value.strip() else default


def _color(value, default: str) -> str:
    return value.lower() if isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", value) else default


def clean_settings(raw) -> dict:
    """Return complete, in-range settings from any JSON value."""
    raw = raw if isinstance(raw, dict) else {}
    key = raw.get("key") if isinstance(raw.get("key"), dict) else {}
    person = raw.get("person") if isinstance(raw.get("person"), dict) else {}
    crop = person.get("crop")
    crop = (
        [_number(v, 0.0, 0.45, 0.0) for v in crop] if isinstance(crop, list) and len(crop) == 4 else [0.0] * 4
    )
    k, p = DEFAULTS["key"], DEFAULTS["person"]
    return {
        "title": _text(raw.get("title"), 120, DEFAULTS["title"]),
        "photo": _flag(raw.get("photo"), True),
        "clip": _flag(raw.get("clip"), True),
        "clip_seconds": int(_number(raw.get("clip_seconds"), 2, 30, DEFAULTS["clip_seconds"])),
        "countdown": int(_number(raw.get("countdown"), 0, 10, DEFAULTS["countdown"])),
        "keep_minutes": int(_number(raw.get("keep_minutes"), 1, 1440, DEFAULTS["keep_minutes"])),
        "cycle_seconds": int(_number(raw.get("cycle_seconds"), 0, 600, DEFAULTS["cycle_seconds"])),
        "mirror": _flag(raw.get("mirror"), True),
        "camera": _text(raw.get("camera"), 200, ""),
        "key": {
            "color": _color(key.get("color"), k["color"]),
            "tolerance": _number(key.get("tolerance"), 0.0, 1.0, k["tolerance"]),
            "softness": _number(key.get("softness"), 0.005, 1.0, k["softness"]),
            "spill": _number(key.get("spill"), 0.0, 1.0, k["spill"]),
        },
        "person": {
            "scale": _number(person.get("scale"), 0.2, 3.0, p["scale"]),
            "x": _number(person.get("x"), -0.5, 1.5, p["x"]),
            "y": _number(person.get("y"), 0.0, 2.0, p["y"]),
            "crop": crop,
        },
    }


@dataclass(frozen=True)
class Media:
    name: str
    path: Path
    mime: str
    fit: str = "cover"

    @property
    def kind(self) -> str:
        return "video" if self.mime.startswith("video/") else "image"


def media(path: Path, name: str = "", fit: str = "cover", images_only: bool = False) -> Media:
    suffix = path.suffix.lower()
    mime = IMAGE_TYPES.get(suffix) or (None if images_only else VIDEO_TYPES.get(suffix))
    if not mime:
        wanted = "PNG, JPEG or WebP" if images_only else "WebM or MP4 video, or a PNG, JPEG or WebP picture"
        hint = " Browsers cannot play Ogg Theora; convert it to WebM." if suffix == ".ogv" else ""
        raise ValueError(f"{path.name}: use {wanted}.{hint}")
    if not path.is_file():
        raise ValueError(f"{path.name} is missing.")
    return Media(_text(name, 80, path.stem), path, mime, fit if fit in FITS else "cover")


@dataclass
class Booth:
    settings: dict
    backgrounds: list[Media] = field(default_factory=list)
    overlay: Media | None = None
    warnings: list[str] = field(default_factory=list)


def from_config(path: Path) -> Booth:
    """Read the run file Studio writes: settings plus absolute media paths."""
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("The booth configuration must be a JSON object.")
    booth = Booth(clean_settings(data.get("settings")))
    for item in data.get("backgrounds", []) if isinstance(data.get("backgrounds"), list) else []:
        try:
            booth.backgrounds.append(
                media(Path(str(item["path"])), item.get("name", ""), item.get("fit", ""))
            )
        except (ValueError, KeyError, TypeError, AttributeError) as error:
            booth.warnings.append(str(error))
    if isinstance(data.get("overlay"), str) and data["overlay"]:
        try:
            booth.overlay = media(Path(data["overlay"]), "Overlay", images_only=True)
        except ValueError as error:
            booth.warnings.append(str(error))
    return booth


def from_project(path: Path, workdir: Path) -> Booth:
    """Read the booth from an exhibit folder, its project.oes.json, or a verified .oex package
    (unpacked into `workdir`)."""
    if path.suffix.lower() == ".oex":
        from deploy import verify  # tools/deploy.py checks members, paths and checksums

        verify(path)
        with zipfile.ZipFile(path) as package:
            for name in package.namelist():
                if not name.endswith("/"):
                    package.extract(name, workdir)
        project_file = workdir / "project.oes.json"
    else:
        project_file = path / "project.oes.json" if path.is_dir() else path
    project = json.loads(project_file.read_text(encoding="utf-8"))
    extension = project.get("extensions", {}).get("greenscreen") if isinstance(project, dict) else None
    if not isinstance(extension, dict):
        raise ValueError("This exhibit has no green-screen booth yet (set it up in Studio → Green screen).")
    assets = project.get("assets", {}) if isinstance(project.get("assets"), dict) else {}

    def asset_file(asset_id) -> Path:
        entry = assets.get(asset_id) if isinstance(asset_id, str) else None
        relative = PurePosixPath(str(entry.get("path", ""))) if isinstance(entry, dict) else None
        if relative is None or relative.is_absolute() or ".." in relative.parts or not relative.parts:
            raise ValueError(f"Background {asset_id!r} is not among the exhibit's assets.")
        return project_file.parent.joinpath(*relative.parts)

    settings = dict(extension)
    settings.setdefault("title", project.get("title"))
    booth = Booth(clean_settings(settings))
    for item in extension.get("backgrounds", []) if isinstance(extension.get("backgrounds"), list) else []:
        try:
            booth.backgrounds.append(
                media(asset_file(item.get("asset")), item.get("name", ""), item.get("fit", ""))
            )
        except (ValueError, AttributeError) as error:
            booth.warnings.append(str(error))
    if extension.get("overlay"):
        try:
            booth.overlay = media(asset_file(extension["overlay"]), "Overlay", images_only=True)
        except ValueError as error:
            booth.warnings.append(str(error))
    return booth

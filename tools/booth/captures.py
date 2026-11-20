"""Visitors' photos and clips: kept on this computer for a limited time and served by a random code.

Nothing is listed or uploaded anywhere. A capture is reachable only by its 72-bit code (shown as a
QR code on the booth screen) until it expires; expired files are deleted by sweep().
"""

from __future__ import annotations

import os
import re
import secrets
import threading
import time
from dataclasses import dataclass
from pathlib import Path

CODE = re.compile(r"[A-Za-z0-9_-]{12}")
SUFFIX = {"image/jpeg": ".jpg", "video/webm": ".webm", "video/mp4": ".mp4"}
MIME = {suffix: mime for mime, suffix in SUFFIX.items()}
LIMIT = {"image/jpeg": 25 * 2**20, "video/webm": 160 * 2**20, "video/mp4": 160 * 2**20}


def _looks_like(mime: str, head: bytes) -> bool:
    if mime == "image/jpeg":
        return head.startswith(b"\xff\xd8\xff")
    if mime == "video/webm":
        return head.startswith(b"\x1a\x45\xdf\xa3")  # EBML header
    return head[4:8] == b"ftyp"  # MP4 starts with its file-type box


@dataclass(frozen=True)
class Capture:
    code: str
    path: Path
    mime: str
    created: float

    @property
    def kind(self) -> str:
        return "photo" if self.mime.startswith("image/") else "clip"


class Store:
    def __init__(self, folder: Path, keep_minutes: float, max_files: int = 2000, clock=time.time):
        self.folder = folder
        self.keep = keep_minutes * 60
        self.max_files = max_files
        self.clock = clock
        self.lock = threading.Lock()
        self.items: dict[str, Capture] = {}
        folder.mkdir(parents=True, exist_ok=True)
        try:
            folder.chmod(0o700)
        except OSError:
            pass  # e.g. on file systems without POSIX permissions
        for path in folder.iterdir():  # captures from an earlier run stay valid until they expire
            if path.is_file() and CODE.fullmatch(path.stem) and path.suffix in MIME:
                self.items[path.stem] = Capture(path.stem, path, MIME[path.suffix], path.stat().st_mtime)
            elif path.is_file() and path.name.startswith(".") and path.name.endswith(".part"):
                path.unlink(missing_ok=True)
        self.sweep()

    def expires(self, capture: Capture) -> float:
        return capture.created + self.keep

    def add(self, stream, length: int, mime: str) -> Capture:
        """Store `length` bytes read from `stream` and return the new capture."""
        if mime not in SUFFIX:
            raise ValueError("Send a JPEG photo or a WebM/MP4 clip.")
        if not 0 < length <= LIMIT[mime]:
            raise ValueError("The capture is empty or too large.")
        code = secrets.token_urlsafe(9)
        partial = self.folder / f".{code}.part"
        try:
            with os.fdopen(os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as out:
                remaining, head = length, b""
                while remaining:
                    chunk = stream.read(min(remaining, 1 << 20))
                    if not chunk:
                        raise ValueError("The upload ended early.")
                    if len(head) < 16:
                        head += chunk[:16]
                    out.write(chunk)
                    remaining -= len(chunk)
            if not _looks_like(mime, head):
                raise ValueError("The file does not match its declared type.")
            final = self.folder / (code + SUFFIX[mime])
            os.replace(partial, final)
        finally:
            partial.unlink(missing_ok=True)
        capture = Capture(code, final, mime, self.clock())
        os.utime(final, (capture.created, capture.created))
        with self.lock:
            self.items[code] = capture
            while len(self.items) > self.max_files:  # oldest first when the booth is very busy
                self._remove(min(self.items.values(), key=lambda c: c.created))
        return capture

    def get(self, code: str) -> Capture | None:
        if not CODE.fullmatch(code or ""):
            return None
        with self.lock:
            capture = self.items.get(code)
            if capture and self.clock() >= self.expires(capture):
                self._remove(capture)
                return None
            return capture

    def sweep(self) -> int:
        """Delete expired captures; returns how many."""
        now = self.clock()
        with self.lock:
            expired = [c for c in self.items.values() if now >= self.expires(c)]
            for capture in expired:
                self._remove(capture)
        return len(expired)

    def clear(self) -> int:
        with self.lock:
            count = len(self.items)
            for capture in list(self.items.values()):
                self._remove(capture)
        return count

    def count(self) -> int:
        with self.lock:
            return len(self.items)

    def _remove(self, capture: Capture) -> None:
        self.items.pop(capture.code, None)
        capture.path.unlink(missing_ok=True)

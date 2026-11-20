#!/usr/bin/env python3
"""Green-screen photo booth: visitors in front of a green cloth appear in your videos and pictures.

The booth page does the camera work in the browser of the booth computer (WebGL chroma key, see
booth/web/keyer.js); this service serves that page and the background media, keeps visitors'
photos and clips for a limited time, and lets phones download them by QR code.

Two listeners, as for the live audience: the booth/operator one on 127.0.0.1 (browsers allow the
camera only on a local address; API calls need the bearer token from the booth URL), and the
public one on the chosen LAN address, which serves nothing but the download page of a capture.

    python3 tools/greenscreen.py --project exhibit.oex --bind 192.168.1.20 --open
"""

from __future__ import annotations

import argparse
import html
import json
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from booth import config
from booth.captures import Store
from servicekit import Server, allowed_hosts, lan_address, qr_svg, write_private

ROOT = Path(__file__).resolve().parent
WEB = ROOT / "booth" / "web"
FONTS = ROOT / "contest" / "web"
STATIC = {
    "booth.js": (WEB, "text/javascript; charset=utf-8"),
    "keyer.js": (WEB, "text/javascript; charset=utf-8"),
    "booth.css": (WEB, "text/css; charset=utf-8"),
    "download.css": (WEB, "text/css; charset=utf-8"),
    "mono.woff2": (FONTS, "font/woff2"),
    "bengali.ttf": (FONTS, "font/ttf"),
    "devanagari.ttf": (FONTS, "font/ttf"),
}
CSP = (
    "default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; "
    "img-src 'self' data: blob:; media-src 'self' blob: mediastream:; object-src 'none'; base-uri 'none'; "
    "frame-ancestors 'none'"
)
CAPTURE_PAGE = re.compile(r"/p/([A-Za-z0-9_-]{12})(/file)?")


class Refused(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


class Handler(BaseHTTPRequestHandler):
    server_version = "OpenExhibit/0.3"

    def log_message(self, *_):
        pass

    # ------------------------------------------------------------------ responses
    def _headers(self, status: int, mime: str, length: int, cache: bool = False, extra: dict | None = None):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "max-age=300" if cache else "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", CSP)
        for name, value in (extra or {}).items():
            self.send_header(name, value)
        self.end_headers()

    def reply(self, value, status: int = 200, mime: str = "application/json; charset=utf-8", cache=False):
        raw = (
            value
            if isinstance(value, bytes)
            else (json.dumps(value) if mime.startswith("application/json") else value).encode()
        )
        self._headers(status, mime, len(raw), cache)
        self.wfile.write(raw)

    def send_file(self, path: Path, mime: str, download_name: str = "", cache: bool = False):
        """Send a file, honouring a single byte range (needed for video seeking, especially on iPhones)."""
        size = path.stat().st_size
        start, end, status, extra = 0, size - 1, 200, {"Accept-Ranges": "bytes"}
        wanted = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", "").strip())
        if wanted and size and wanted.group(1) + wanted.group(2):
            first, last = wanted.groups()
            if first:
                start, end = int(first), min(size - 1, int(last)) if last else size - 1
            else:
                start = max(0, size - int(last))
            if start > end:
                self._headers(416, "text/plain", 0, extra={"Content-Range": f"bytes */{size}"})
                return
            status, extra["Content-Range"] = 206, f"bytes {start}-{end}/{size}"
        if download_name:
            extra["Content-Disposition"] = f'attachment; filename="{download_name}"'
        self._headers(status, mime, max(0, end - start + 1), cache, extra)
        with path.open("rb") as stream:
            stream.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = stream.read(min(remaining, 256 * 1024))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    # ------------------------------------------------------------------ routing
    def dispatch(self, post: bool):
        server = self.server
        if not server.http_host_ok(self.headers.get("Host", "")):
            raise Refused(403, "Unknown host address.")
        url = urlsplit(self.path)
        if url.path == "/favicon.ico":
            self._headers(204, "text/plain", 0)
            return
        if server.operator:
            self.operator(url.path, url.query, post)
        else:
            self.public(url.path, url.query, post)

    def public(self, path: str, query: str, post: bool):
        """The LAN side: download pages of existing captures and their stylesheet, nothing else."""
        if post:
            raise Refused(404, "Not found.")
        if path == "/download.css":
            return self.send_file(WEB / "download.css", STATIC["download.css"][1], cache=True)
        page = CAPTURE_PAGE.fullmatch(path)
        if not page:
            raise Refused(404, "Not found.")
        capture = self.server.service.store.get(page.group(1))
        if not capture:
            return self.reply(_expired_page(), 404, "text/html; charset=utf-8")
        if page.group(2):
            name = ""
            if parse_qs(query).get("download") == ["1"]:
                stamp = time.strftime("%Y%m%d-%H%M", time.localtime(capture.created))
                name = f"green-screen-{stamp}{capture.path.suffix}"
            return self.send_file(capture.path, capture.mime, name)
        return self.reply(self.server.service.download_page(capture), mime="text/html; charset=utf-8")

    def operator(self, path: str, query: str, post: bool):
        service = self.server.service
        if path in ("/", "/booth") and not post:
            return self.send_file(WEB / "booth.html", "text/html; charset=utf-8")
        if path[1:] in STATIC and not post:
            folder, mime = STATIC[path[1:]]
            return self.send_file(folder / path[1:], mime, cache=True)
        media = service.media_file(path)
        if media and not post:  # <video>/<img> cannot send the token; this listener is loopback-only
            return self.send_file(media.path, media.mime)
        qr = re.fullmatch(r"/qr/([A-Za-z0-9_-]{12})\.svg", path)
        if qr and not post:
            return self.reply(qr_svg(service.capture_url(qr.group(1))), mime="image/svg+xml")
        if not path.startswith("/api/"):
            raise Refused(404, "Not found.")
        auth = self.headers.get("Authorization", "")
        if not secrets.compare_digest(auth.encode(), ("Bearer " + service.secret).encode()):
            raise Refused(403, "Open the booth from Studio or the URL the service printed.")
        if not post:
            if path == "/api/booth":
                return self.reply(service.booth_state())
            if path == "/api/settings":
                return self.reply({"settings": service.settings})
            if path == "/api/status":
                return self.reply({"captures": service.store.count(), "download": service.download_root})
            raise Refused(404, "Not found.")
        origin = self.headers.get("Origin")
        if origin and urlsplit(origin).netloc != self.headers.get("Host"):
            raise Refused(403, "Origin does not match the booth.")
        length = self.headers.get("Content-Length", "")
        if not length.isdecimal():
            raise Refused(411, "Send a Content-Length.")
        if path == "/api/capture":
            capture = service.store.add(self.rfile, int(length), self.headers.get_content_type())
            return self.reply(service.describe(capture))
        if int(length) > 256 * 1024 or self.headers.get_content_type() != "application/json":
            raise ValueError("Send a small JSON object.")
        data = json.loads(self.rfile.read(int(length)) or b"{}")
        if not isinstance(data, dict):
            raise ValueError("Send a JSON object.")
        if path == "/api/settings":
            return self.reply({"settings": service.update_settings(data.get("settings"))})
        if path == "/api/captures/clear":
            return self.reply({"deleted": service.store.clear()})
        if path == "/api/stop":
            service.stop.set()
            return self.reply({"ok": True})
        raise Refused(404, "Not found.")

    def handle_request(self, post: bool):
        try:
            self.dispatch(post)
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            return
        except Refused as error:
            self.reply({"error": str(error)}, error.status)
        except (ValueError, TypeError, KeyError, UnicodeError, OverflowError) as error:
            self.reply({"error": str(error)[:240]}, 400)

    def do_GET(self):
        self.handle_request(False)

    def do_POST(self):
        self.handle_request(True)


def _expired_page() -> str:
    return _page(
        "Not available",
        "<h1>This picture is no longer here</h1><p>Photos and videos from the booth are deleted "
        "after a while. Ask at the exhibit if you need help.</p>",
    )


def _page(title: str, body: str) -> str:
    return (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        f'<title>{html.escape(title)}</title><link rel="stylesheet" href="/download.css"></head>'
        f"<body><main>{body}</main></body></html>"
    )


class BoothService:
    def __init__(
        self,
        booth: config.Booth,
        store: Store,
        address="127.0.0.1",
        port=8788,
        operator_port=8789,
        settings_file: Path | None = None,
    ):
        self.booth = booth
        self.store = store
        self.settings = booth.settings
        self.settings_file = settings_file
        self.secret = secrets.token_urlsafe(32)
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.public = Server((lan_address(address), port), Handler)
        try:
            self.operator = Server(("127.0.0.1", operator_port), Handler)
        except BaseException:
            self.public.server_close()
            raise
        for server, private in [(self.public, False), (self.operator, True)]:
            server.service, server.operator = self, private
            server.http_host_ok = allowed_hosts(server).__contains__
        self.download_root = "http://%s:%d" % self.public.server_address[:2]
        self.booth_url = "http://127.0.0.1:%d/booth#%s" % (self.operator.server_address[1], self.secret)
        self.threads: list[threading.Thread] = []

    # ------------------------------------------------------------------ state
    def media_file(self, path: str) -> config.Media | None:
        if path == "/media/overlay":
            return self.booth.overlay
        found = re.fullmatch(r"/media/bg/(\d{1,3})", path)
        if found and int(found.group(1)) < len(self.booth.backgrounds):
            return self.booth.backgrounds[int(found.group(1))]
        return None

    def booth_state(self) -> dict:
        return {
            "settings": self.settings,
            "backgrounds": [
                {"name": m.name, "kind": m.kind, "fit": m.fit, "url": f"/media/bg/{i}"}
                for i, m in enumerate(self.booth.backgrounds)
            ],
            "overlay": "/media/overlay" if self.booth.overlay else None,
            "download": self.download_root,
            "local_only": self.public.server_address[0] == "127.0.0.1",
            "warnings": self.booth.warnings,
        }

    def update_settings(self, changes) -> dict:
        with self.lock:
            merged = {**self.settings, **(changes if isinstance(changes, dict) else {})}
            self.settings = config.clean_settings(merged)
            self.store.keep = self.settings["keep_minutes"] * 60
            if self.settings_file:
                write_private(self.settings_file, self.settings)
            return self.settings

    def capture_url(self, code: str) -> str:
        return f"{self.download_root}/p/{code}"

    def describe(self, capture) -> dict:
        expires = self.store.expires(capture)
        return {
            "code": capture.code,
            "kind": capture.kind,
            "url": self.capture_url(capture.code),
            "expires": expires,
            "expires_text": time.strftime("%H:%M", time.localtime(expires)),
        }

    def download_page(self, capture) -> str:
        title = html.escape(self.settings["title"])
        source = f"/p/{capture.code}/file"
        if capture.kind == "photo":
            shown, label = f'<img src="{source}" alt="Your green-screen photo">', "Save photo"
        else:
            shown = f'<video src="{source}" controls playsinline loop muted autoplay></video>'
            label = "Save video"
        until = time.strftime("%H:%M", time.localtime(self.store.expires(capture)))
        return _page(
            self.settings["title"],
            f"<h1>{title}</h1>{shown}"
            f'<a class="save" href="{source}?download=1">{label}</a>'
            f'<p class="note">Kept only on the exhibit computer and deleted at {until}. '
            "Nothing is uploaded to the internet.</p>",
        )

    # ------------------------------------------------------------------ lifecycle
    def start(self):
        for server in (self.public, self.operator):
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.threads.append(thread)
        sweeper = threading.Thread(target=self._sweep, daemon=True)
        sweeper.start()

    def _sweep(self):
        while not self.stop.wait(30):
            self.store.sweep()

    def close(self):
        for server in (self.public, self.operator):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(3)


def open_browser(url: str, kiosk: bool) -> None:
    """Open the booth page; with kiosk, prefer a full-screen Chrome, Chromium or Edge window."""
    if kiosk:
        candidates = [
            "google-chrome",
            "google-chrome-stable",
            "chromium",
            "chromium-browser",
            "microsoft-edge",
        ]
        if sys.platform == "win32":
            candidates = [
                r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
            ]
        for candidate in candidates:
            program = shutil.which(candidate) or (candidate if Path(candidate).is_file() else None)
            if program:
                subprocess.Popen(
                    [program, "--kiosk", "--app=" + url, "--autoplay-policy=no-user-gesture-required"]
                )
                return
    webbrowser.open(url)


def main():
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = cli.add_mutually_exclusive_group(required=True)
    source.add_argument("--project", type=Path, help="exhibit folder, project.oes.json or .oex package")
    source.add_argument("--config", type=Path, help="run file written by Studio")
    cli.add_argument(
        "--bind", default="127.0.0.1", help="LAN address phones download from (default: this computer only)"
    )
    cli.add_argument("--port", type=int, default=8788, help="download port on the LAN address")
    cli.add_argument("--host-port", type=int, default=8789, help="booth page port on 127.0.0.1")
    cli.add_argument(
        "--captures", type=Path, default=Path.home() / ".openexhibit" / "greenscreen" / "captures"
    )
    cli.add_argument(
        "--settings", type=Path, help="keep calibration from the booth's setup panel in this file"
    )
    cli.add_argument("--info", type=Path, help="private file for the Studio launcher")
    cli.add_argument("--open", action="store_true", help="open the booth page in the default browser")
    cli.add_argument(
        "--kiosk", action="store_true", help="open the booth full screen in Chrome/Chromium/Edge"
    )
    options = cli.parse_args()
    unpacked = tempfile.TemporaryDirectory(prefix="openexhibit-booth-")
    try:
        if options.config:
            booth = config.from_config(options.config)
        else:
            booth = config.from_project(options.project, Path(unpacked.name))
        if options.settings and options.settings.is_file():
            saved = json.loads(options.settings.read_text(encoding="utf-8"))
            booth.settings = config.clean_settings(
                {**booth.settings, **(saved if isinstance(saved, dict) else {})}
            )
        store = Store(options.captures, booth.settings["keep_minutes"])
        service = BoothService(booth, store, options.bind, options.port, options.host_port, options.settings)
    except (ValueError, OSError, KeyError) as error:
        if options.info:
            write_private(options.info, {"error": str(error)})
        unpacked.cleanup()
        cli.exit(2, f"{error}\n")
    service.start()
    try:
        info = {"booth": service.booth_url, "download": service.download_root, "warnings": booth.warnings}
        if options.info:
            write_private(options.info, info)
        else:
            print("Booth (open on this computer):", service.booth_url)
            print("Phones download from:", service.download_root, flush=True)
            for warning in booth.warnings:
                print("Warning:", warning, flush=True)
        if options.open or options.kiosk:
            open_browser(service.booth_url, options.kiosk)
        signal.signal(signal.SIGTERM, lambda *_: service.stop.set())
        try:
            service.stop.wait()
        except KeyboardInterrupt:
            pass
    finally:
        service.close()
        unpacked.cleanup()
        if options.info:
            options.info.unlink(missing_ok=True)


if __name__ == "__main__":
    main()

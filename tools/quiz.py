#!/usr/bin/env python3
"""Offline live-audience host (AhaSlides-style polls, quizzes, word clouds, Q&A, ideas, spinner).

Two listeners: the public one serves participants and the projector; the private operator one
(loopback only, bearer token) serves the presenter console and slide editor.
"""

import argparse
import base64
import subprocess
import zipfile
from xml.etree.ElementTree import ParseError
import collections
import functools
import ipaddress
import json
import os
import secrets
import signal
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contest import deck
from contest.room import Room, Conflict, Forbidden, dump
from contest.vendor.qrencoder import QRCode, QRErrorCorrectLevel

ROOT = Path(__file__).resolve().parent
WEB = ROOT / "contest" / "web"
EXAMPLE = ROOT / "contest" / "museum.quiz.json"
LIMIT = 8 * 1024 * 1024
ASSETS = {
    name: mime
    for name, mime in [
        ("app.js", "text/javascript; charset=utf-8"),
        ("present.js", "text/javascript; charset=utf-8"),
        ("editor.js", "text/javascript; charset=utf-8"),
        ("style.css", "text/css; charset=utf-8"),
        ("mono.woff2", "font/woff2"),
        ("bengali.ttf", "font/ttf"),
        ("devanagari.ttf", "font/ttf"),
        ("vendor/wordcloud2.js", "text/javascript; charset=utf-8"),
        ("vendor/confetti.browser.js", "text/javascript; charset=utf-8"),
        ("vendor/Sortable.min.js", "text/javascript; charset=utf-8"),
    ]
}


@functools.lru_cache(maxsize=16)
def qr_svg(url):
    qr = QRCode(None, QRErrorCorrectLevel.M)
    qr.addData(url)
    qr.make()
    n = qr.getModuleCount()
    path = "".join(f"M{x + 4} {y + 4}h1v1h-1z" for y in range(n) for x in range(n) if qr.isDark(y, x))
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{n + 8}" height="{n + 8}" viewBox="0 0 {n + 8} {n + 8}" shape-rendering="crispEdges"><rect width="100%" height="100%" fill="white"/><path d="{path}"/></svg>'


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 256
    allow_reuse_address = True

    def get_request(self):
        conn, addr = super().get_request()
        conn.settimeout(8)
        return conn, addr


class Handler(BaseHTTPRequestHandler):
    server_version = "OpenExhibit/0.3"

    def log_message(self, *_):
        pass

    def reply(self, value, status=200, mime="application/json; charset=utf-8", filename=None, cache=False):
        raw = (
            value
            if isinstance(value, bytes)
            else (dump(value) if mime.startswith("application/json") else value).encode()
        )
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "max-age=300" if cache else "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; connect-src 'self'; script-src 'self'; frame-ancestors 'none'; img-src 'self' data:; font-src 'self'; style-src 'self' 'unsafe-inline'; object-src 'none'; base-uri 'none'",
        )
        if filename:
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.end_headers()
        self.wfile.write(raw)

    def dispatch(self, post=False):
        url = urlsplit(self.path)
        service = self.server.service
        room = service.room
        op = url.path
        auth = self.headers.get("Authorization", "")
        token = auth[7:] if auth.startswith("Bearer ") and len(auth) <= 128 else None
        host = self.server.operator and secrets.compare_digest(
            (token or "").encode(), service.secret.encode()
        )
        if post:
            if not self.server.http_host_ok(self.headers.get("Host", "")):
                raise Forbidden("Unknown host address.")
            origin = self.headers.get("Origin")
            if origin and urlsplit(origin).netloc != self.headers["Host"]:
                raise Forbidden("Origin does not match this room.")
            if self.headers.get_content_type() != "application/json":
                raise deck.Invalid("Send a JSON object.")
            raw_len = self.headers.get("Content-Length", "")
            if not raw_len.isdecimal() or not 2 <= int(raw_len) <= (LIMIT if host else 8192):
                raise deck.Invalid("Request size is outside the accepted limit.")
            data = json.loads(self.rfile.read(int(raw_len)))
            if not isinstance(data, dict):
                raise deck.Invalid("Expected an object.")
            if op == "/api/join":
                service.check_join_rate(self.client_address[0])
                return self.reply(
                    {"token": room.join(data.get("code", ""), data.get("name"), data.get("team"))}
                )
            if op == "/api/practice/next":
                room.practice_next(token, data.get("round"))
            elif op == "/api/react":
                room.react(token, data.get("emoji"))
            elif op == "/api/idea":
                room.idea(token, data.get("round"), data.get("text"))
            elif op == "/api/idea/vote":
                room.idea_vote(token, deck.integer(data.get("id"), 1, 2**31, "Idea"))
            elif op == "/api/answer":
                room.submit(token, data.get("round"), data.get("value"))
            elif op == "/api/ask":
                room.qa(token, "ask", data.get("text"))
            elif op == "/api/vote":
                room.qa(token, "vote", deck.integer(data.get("id"), 1, 2**31, "Question"))
            elif op.startswith("/api/host/") and not host:
                raise Forbidden("Host access is available on the operator computer.")
            elif op == "/api/host/text":
                return self.reply(
                    deck.from_text(data.get("text"), str(data.get("title") or "Imported questions"))
                )
            elif op == "/api/host/moderate-idea":
                room.moderate_idea(deck.integer(data.get("id"), 1, 2**31, "Idea"), data.get("status"))
            elif op == "/api/host/import":
                from contest.slides import convert

                if not isinstance(data.get("file"), str) or not isinstance(data.get("name"), str):
                    raise deck.Invalid("Select a local presentation.")
                if data["name"].lower().endswith(".txt"):
                    raw = base64.b64decode(data["file"], validate=True).decode("utf-8-sig")
                    return self.reply(deck.from_text(raw, Path(data["name"]).stem.replace("_", " ")[:120]))
                try:
                    new = convert(base64.b64decode(data["file"], validate=True), data["name"])
                except (zipfile.BadZipFile, ParseError, subprocess.SubprocessError, KeyError) as error:
                    raise deck.Invalid("The presentation could not be imported.") from error
                return self.reply(new)
            elif op == "/api/host/stop":
                service.stop.set()
            elif op == "/api/host/action":
                room.control(data.get("action"), data.get("phase"), data.get("round"), data.get("deck"))
                state = room.snapshot(None, host=True)  # the presenter continues from the new state at once
                state.update(
                    join_url=service.join_url, audience_url=service.audience_url, join_host=service.join_host
                )
                return self.reply(state)
            elif op == "/api/host/moderate":
                room.moderate(deck.integer(data.get("id"), 1, 2**31, "Question"), data.get("status"))
            else:
                return self.reply({"error": "Unknown request."}, 404)
            return self.reply({"ok": True})
        if op in {"/api/host/state", "/api/host/results", "/api/host/summary"}:
            if not host:
                raise Forbidden("Open the host link on the operator computer.")
            if op.endswith("/results"):
                return self.reply(
                    "\ufeff" + room.export(), mime="text/csv; charset=utf-8", filename="session-answers.csv"
                )
            if op.endswith("/summary"):
                return self.reply(
                    "\ufeff" + room.summary(), mime="text/csv; charset=utf-8", filename="session-summary.csv"
                )
        if op in {"/api/state", "/api/host/state"}:
            query = parse_qs(url.query)
            since = query.get("since", [""])[0]
            if since.isdecimal():
                pulse = query.get("pulse", [""])[0]
                room.wait(int(since), int(pulse) if pulse.isdecimal() else None)
            state = room.snapshot(None if host else token, host=host)
            state.update(
                join_url=service.join_url, audience_url=service.audience_url, join_host=service.join_host
            )
            return self.reply(state)
        if op == "/favicon.ico":
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        if op == "/join.svg":
            return self.reply(qr_svg(service.join_url), mime="image/svg+xml")
        if op in {"/", "/display", "/host", "/edit"}:
            if op in {"/host", "/edit"} and not self.server.operator:
                raise Forbidden("Open the private presenter link on the operator computer.")
            return self.reply((WEB / "index.html").read_bytes(), mime="text/html; charset=utf-8")
        if op[1:] in ASSETS:
            return self.reply((WEB / op[1:]).read_bytes(), mime=ASSETS[op[1:]], cache=True)
        return self.reply({"error": "Page not found."}, 404)

    def handle_request(self, post):
        try:
            self.dispatch(post)
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            return
        except Forbidden as error:
            self.reply({"error": str(error)}, 403)
        except Conflict as error:
            self.reply({"error": str(error)}, 409)
        except (ValueError, TypeError, UnicodeError, KeyError, OverflowError, RecursionError) as error:
            self.reply({"error": str(error)[:240]}, 400)

    def do_GET(self):
        self.handle_request(False)

    def do_POST(self):
        self.handle_request(True)


class Contest:
    def __init__(self, room, address="127.0.0.1", port=8786, operator_port=8787):
        self.room = room
        self.secret = secrets.token_urlsafe(32)
        ip = ipaddress.IPv4Address(address)
        if not (ip.is_private and not ip.is_multicast and not ip.is_unspecified and not ip.is_reserved):
            raise ValueError("Select a local interface address, such as 192.168.1.20.")
        self.lock = threading.Lock()
        self.rates = {}
        self.public = Server((str(ip), port), Handler)
        try:
            self.operator = Server(("127.0.0.1", operator_port), Handler)
        except BaseException:
            self.public.server_close()
            raise
        for srv, private in [(self.public, False), (self.operator, True)]:
            srv.service, srv.operator = self, private
            hostname, bound = srv.server_address
            allowed = {f"{hostname}:{bound}"}
            if hostname == "127.0.0.1":
                allowed.add(f"localhost:{bound}")
            srv.http_host_ok = allowed.__contains__
        root = "http://%s:%d" % self.public.server_address
        self.join_url = root + "/?room=" + room.meta()["code"]
        self.join_host = "%s:%d" % self.public.server_address
        self.audience_url = root + "/display"
        self.host_url = "http://%s:%d/host#%s" % (*self.operator.server_address, self.secret)
        self.threads = []
        self.stop = threading.Event()

    def check_join_rate(self, ip):
        with self.lock:
            now = time.monotonic()
            if len(self.rates) > 1024:
                self.rates = {k: v for k, v in self.rates.items() if v and v[-1] > now - 60}
            times = self.rates.setdefault(ip, collections.deque())
            while times and times[0] < now - 60:
                times.popleft()
            if len(times) >= 90:
                raise Conflict("Too many join attempts. Wait one minute.")
            times.append(now)

    def start(self):
        for srv in (self.public, self.operator):
            thread = threading.Thread(target=srv.serve_forever, daemon=True)
            thread.start()
            self.threads.append(thread)

    def close(self):
        for srv in (self.public, self.operator):
            srv.shutdown()
            srv.server_close()
        for thread in self.threads:
            thread.join(3)


def write_private(path, info):
    path.parent.mkdir(exist_ok=True, parents=True)
    tmp = path.with_name(path.name + "." + secrets.token_hex(6) + ".tmp")
    with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w", encoding="utf-8") as f:
        json.dump(info, f)
    os.replace(tmp, path)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--bind", default="127.0.0.1", help="Visitor LAN IPv4 interface. Defaults to this computer."
    )
    p.add_argument("--port", type=int, default=8786)
    p.add_argument("--host-port", type=int, default=8787)
    p.add_argument("--deck", type=Path, default=EXAMPLE)
    p.add_argument("--db", type=Path, default=Path.home() / ".openexhibit" / "contest.sqlite")
    p.add_argument("--info", type=Path, help="Private local file for the Studio launcher.")
    p.add_argument("--open-host", action="store_true")
    p.add_argument(
        "--self-paced", action="store_true", help="Start a room where participants advance individually."
    )
    p.add_argument("--capacity", type=int, default=400)
    a = p.parse_args()
    try:
        if not 1 <= a.capacity <= 2000:
            raise ValueError("Capacity must be 1–2000.")
        a.db.parent.mkdir(parents=True, exist_ok=True)
        room = Room(a.db, json.loads(a.deck.read_text(encoding="utf-8")), a.capacity, self_paced=a.self_paced)
        service = Contest(room, a.bind, a.port, a.host_port)
    except (ValueError, OSError, KeyError) as exc:
        if a.info:
            write_private(a.info, dict(error=str(exc)))
        p.exit(2, str(exc) + "\n")
    service.start()
    try:
        info = dict(
            host=service.host_url,
            join=service.join_url,
            display=service.audience_url,
            code=room.meta()["code"],
        )
        if a.info:
            write_private(a.info, info)
        else:
            print(
                "Host (private):",
                info["host"],
                "\nAudience:",
                info["display"],
                "\nJoin:",
                info["join"],
                flush=True,
            )
        if a.open_host:
            webbrowser.open(service.host_url)
        stop = service.stop
        signal.signal(signal.SIGTERM, lambda *_: stop.set())
        try:
            stop.wait()
        except KeyboardInterrupt:
            pass
    finally:
        service.close()
        if a.info:
            a.info.unlink(missing_ok=True)


if __name__ == "__main__":
    main()

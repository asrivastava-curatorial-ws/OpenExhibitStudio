"""Shared pieces of the local HTTP services (live audience, green-screen booth)."""

from __future__ import annotations

import functools
import ipaddress
import json
import os
import secrets
from http.server import ThreadingHTTPServer
from pathlib import Path

from contest.vendor.qrencoder import QRCode, QRErrorCorrectLevel


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 256
    allow_reuse_address = True

    def get_request(self):
        conn, addr = super().get_request()
        conn.settimeout(8)
        return conn, addr


def allowed_hosts(server: ThreadingHTTPServer) -> set[str]:
    """Host header values a listener answers to; anything else is refused (DNS rebinding)."""
    hostname, port = server.server_address[:2]
    allowed = {f"{hostname}:{port}"}
    if hostname == "127.0.0.1":
        allowed.add(f"localhost:{port}")
    return allowed


def lan_address(address: str) -> str:
    """Accept only private IPv4 interface addresses (or loopback) for visitor-facing listeners."""
    ip = ipaddress.IPv4Address(address)
    if not (ip.is_private and not ip.is_multicast and not ip.is_unspecified and not ip.is_reserved):
        raise ValueError("Select a local interface address, such as 192.168.1.20.")
    return str(ip)


def write_private(path: Path, data: dict) -> None:
    """Write JSON readable only by this user, replacing the file atomically."""
    path.parent.mkdir(exist_ok=True, parents=True)
    tmp = path.with_name(path.name + "." + secrets.token_hex(6) + ".tmp")
    with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, path)


@functools.lru_cache(maxsize=64)
def qr_svg(text: str) -> str:
    qr = QRCode(None, QRErrorCorrectLevel.M)
    qr.addData(text)
    qr.make()
    n = qr.getModuleCount()
    path = "".join(f"M{x + 4} {y + 4}h1v1h-1z" for y in range(n) for x in range(n) if qr.isDark(y, x))
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{n + 8}" height="{n + 8}" '
        f'viewBox="0 0 {n + 8} {n + 8}" shape-rendering="crispEdges">'
        f'<rect width="100%" height="100%" fill="white"/><path d="{path}"/></svg>'
    )

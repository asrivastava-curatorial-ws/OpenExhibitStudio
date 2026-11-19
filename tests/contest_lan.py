"""Run a contest across two host addresses or an isolated Linux veth pair."""

import argparse
import http.client
import ipaddress
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import quiz


def ip(*args):
    subprocess.run(["ip", *args], check=True)


def wait_for(condition):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.04)
    raise TimeoutError("Contest did not reach the expected state.")


def verify_namespace():
    if subprocess.check_output(["ip", "route", "show", "default"], text=True).strip():
        raise RuntimeError("Start with unshare -Urnm to create an isolated network namespace.")


def visit(folder, client_address, isolated):
    if isolated:
        verify_namespace()
    (folder / "ready").touch()
    wait_for(lambda: (folder / "start.json").is_file())
    if isolated:
        ip("addr", "add", client_address + "/24", "dev", "oes-phone")
        ip("link", "set", "oes-phone", "up")
        ip("link", "set", "lo", "up")
    info = json.loads((folder / "start.json").read_text())
    token = ""

    def request(path, data=None, status=200):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        conn = http.client.HTTPConnection(
            info["host"], info["port"], timeout=3, source_address=(client_address, 0)
        )
        try:
            conn.request(
                "POST" if data is not None else "GET",
                path,
                json.dumps(data).encode() if data is not None else None,
                headers,
            )
            reply = conn.getresponse()
            out = json.loads(reply.read())
            if reply.status != status:
                raise RuntimeError(f"{path} returned {reply.status}: {out}")
            return out
        finally:
            conn.close()

    token = request("/api/join", {"name": "Class A", "team": "Raman", "code": info["code"]})["token"]
    request("/api/host/state", status=403)
    with socket.socket() as sock:
        sock.bind((client_address, 0))
        sock.settimeout(2)
        if sock.connect_ex((info["host"], info["private_port"])) == 0:
            raise RuntimeError("Operator listener is reachable on the audience address.")
    wait_for(lambda: request("/api/state")["phase"] == "open")
    request("/api/answer", {"round": 0, "value": "Neptune"})
    wait_for(lambda: request("/api/state")["phase"] == "reveal")
    result = request("/api/state")
    if result["leaders"][0]["name"] != "Class A" or result["me"]["points"] <= 0:
        raise RuntimeError("Returned leaderboard or individual score was incorrect.")
    if isolated:
        verify_namespace()


def run(host, source, isolated):
    if isolated:
        verify_namespace()
        ip("link", "set", "lo", "up")
        ip("link", "add", "oes-host", "type", "veth", "peer", "name", "oes-phone")
    elif host == source or ipaddress.ip_address(host).is_loopback or ipaddress.ip_address(source).is_loopback:
        raise ValueError("Supply two distinct, assigned, non-loopback IPv4 addresses.")
    with tempfile.TemporaryDirectory() as temp:
        folder = Path(temp)
        args = [sys.executable, __file__, "--visit", temp, "--source", source]
        if isolated:
            args = ["unshare", "-n", *args, "--isolated"]
        process = subprocess.Popen(args)
        room = server = None
        try:
            wait_for(lambda: (folder / "ready").is_file())
            if isolated:
                ip("link", "set", "oes-phone", "netns", str(process.pid))
                ip("addr", "add", host + "/24", "dev", "oes-host")
                ip("link", "set", "oes-host", "up")
            room = quiz.Room(folder / "room.sqlite", json.loads(quiz.EXAMPLE.read_text()))
            server = quiz.Contest(room, host, 0, 0)
            server.start()
            info = {
                "host": host,
                "port": server.public.server_port,
                "private_port": server.operator.server_port,
                "code": room.meta()["code"],
            }
            staging = folder / "prepared.json"
            staging.write_text(json.dumps(info))
            staging.rename(folder / "start.json")
            wait_for(lambda: room.snapshot()["players"] == 1)
            room.control("next", "lobby", -1)
            wait_for(lambda: room.snapshot()["received"] == 1)
            room.control("reveal", "open", 0)
            if process.wait(timeout=10):
                raise RuntimeError("Participant process failed.")
            topology = (
                "two isolated network namespaces with no default route"
                if isolated
                else "two non-loopback addresses on one host"
            )
            print(
                "PASS",
                topology,
                "with separate processes: joined, scored, read ranking, operator paths inaccessible.",
            )
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            if server:
                server.close()
            if room:
                room.db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--isolated", action="store_true", help="Linux iproute2, veth and a new network namespace required."
    )
    parser.add_argument("--host", default="192.168.76.1")
    parser.add_argument("--source", default="192.168.76.2")
    parser.add_argument("--visit", type=Path, help=argparse.SUPPRESS)
    options = parser.parse_args()
    if options.visit:
        visit(options.visit, options.source, options.isolated)
    else:
        run(options.host, options.source, options.isolated)

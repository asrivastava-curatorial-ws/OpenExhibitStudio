import json
import os
import queue
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "gateway"))
from adapters import FirmataInput, osc_scalar
from openexhibit_gateway import Hub, Server, Handler, valid_config


class ProtocolTests(unittest.TestCase):
    def test_firmata_fragmentation(self):
        f = FirmataInput(
            [
                {"pin": 0, "mode": "analog", "channel": "dial"},
                {"pin": 2, "mode": "digital", "channel": "button"},
            ]
        )
        self.assertIn(bytes([0xC0, 1]), f.subscribe())
        self.assertEqual(list(f.feed(b"\xe0\x7f")), [])
        self.assertEqual(list(f.feed(b"\x07")), [("dial", 1023)])
        self.assertEqual(list(f.feed(b"\x90\x04\x00")), [("button", 1)])
        self.assertEqual(list(f.feed(b"\x90\x04\x00")), [])

    def test_osc_scalar(self):
        self.assertEqual(osc_scalar(b"/x\0\0,f\0\0" + struct.pack(">f", 0.75)), ("/x", 0.75))

    def test_legacy_csv_json_ascii(self):
        for protocol, data in [
            ("csv", b"dial,23\n"),
            ("jsonl", b'{"channel":"dial","value":23}\n'),
            ("ascii", b"dial 23\n"),
        ]:
            h = Hub({"devices": [{"id": "sample", "protocol": protocol, "inputs": ["dial"]}]})
            q = queue.Queue()
            h.clients.add(q)
            h.links["sample"].feed(data)
            self.assertEqual(q.get_nowait()["value"], 23)

    def test_profile_conflict(self):
        with self.assertRaises(ValueError):
            valid_config({"devices": [{"id": "a", "port": "x"}, {"id": "b", "port": "x"}]})

    def test_unknown_channel_and_lockout(self):
        h = Hub({"lockout": True, "devices": []})
        with self.assertRaises(ValueError):
            h.command(queue.Queue(), {"op": "arm"})
        with self.assertRaises(ValueError):
            h.command(queue.Queue(), {"op": "out", "channel": "invalid", "value": 1})

    def test_stale_lease(self):
        h = Hub({"devices": []})
        h.owner = queue.Queue()
        h.lease = time.monotonic() - 6
        h.tick()
        self.assertIsNone(h.owner)

    def test_input_filter(self):
        h = Hub(
            {"devices": [{"id": "demo", "inputs": ["dial"], "filters": {"dial": {"scale": 2, "alpha": 0.5}}}]}
        )
        l = h.links["demo"]
        q = queue.Queue()
        h.clients.add(q)
        l.sample("dial", 10)
        l.sample("dial", 20)
        l.sample("dial", float("nan"))
        self.assertEqual([q.get()["value"], q.get()["value"]], [20, 30])
        self.assertTrue(q.empty())


@unittest.skipUnless(os.name == "posix" and shutil.which("g++"), "Requires POSIX PTY and C++ compiler")
class SerialEndToEnd(unittest.TestCase):
    def test_bidirectional_real_tty_and_controller_disconnect(self):
        import pty
        import tty

        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / "board"
            subprocess.run(
                [
                    "g++",
                    "-std=c++17",
                    "-O2",
                    "-I",
                    str(ROOT / "firmware/libraries/OpenExhibitProtocol/src"),
                    str(ROOT / "tests/board_fixture.cpp"),
                    "-o",
                    str(exe),
                ],
                check=True,
            )
            master, slave = pty.openpty()
            tty.setraw(slave)
            board = subprocess.Popen([str(exe)], stdin=master, stdout=master)
            hub = Hub(
                {
                    "devices": [
                        {
                            "id": "uno",
                            "port": os.ttyname(slave),
                            "protocol": "oes1",
                            "inputs": ["dial", "lamp_echo"],
                            "outputs": {"lamp": [0, 1]},
                        }
                    ]
                }
            )
            server = Server(("127.0.0.1", 0), Handler)
            server.hub = hub
            server.token = "integration-test-only-local-token"
            hub.start()
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with socket.create_connection(server.server_address, 2) as sock, sock.makefile("rwb") as f:

                    def send(msg):
                        f.write((json.dumps(msg) + "\n").encode())
                        f.flush()

                    def receive(predicate):
                        end = time.monotonic() + 4
                        while time.monotonic() < end:
                            data = json.loads(f.readline())
                            if predicate(data):
                                return data
                        self.fail("Timed out waiting for gateway reply.")

                    send({"op": "hello", "v": 1, "token": server.token})
                    receive(lambda r: r["op"] == "hello")
                    self.assertEqual(receive(lambda r: r.get("channel") == "dial")["value"], 72)
                    send({"op": "out", "channel": "lamp", "value": 1})
                    receive(lambda r: r["op"] == "error")
                    send({"op": "arm"})
                    receive(lambda r: r.get("armed") is True)
                    send({"op": "out", "channel": "lamp", "value": 1})
                    self.assertEqual(receive(lambda r: r.get("channel") == "lamp_echo")["value"], 1)
                    send({"op": "out", "channel": "lamp", "value": 9})
                    receive(lambda r: r["op"] == "error")
                deadline = time.monotonic() + 2
                while hub.owner is not None and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertIsNone(hub.owner)
                self.assertFalse(hub.links["uno"].armed)
                board.terminate()
                board.wait(timeout=2)
                os.close(master)
                master = -1
                deadline = time.monotonic() + 3
                while hub.links["uno"].ready and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertFalse(hub.links["uno"].ready)
                with socket.create_connection(server.server_address, 1) as bad:
                    bad.sendall(b'{"op":"hello","v":1,"token":"wrong"}\n')
                    self.assertEqual(bad.recv(8), b"")
            finally:
                server.shutdown()
                server.server_close()
                hub.close()
                if board.poll() is None:
                    board.terminate()
                    board.wait(timeout=2)
                if master >= 0:
                    os.close(master)
                os.close(slave)

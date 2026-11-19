#!/usr/bin/env python3
"""OpenExhibit hardware gateway, Python 3.10+. See docs/PROTOCOL.md."""
import argparse
import collections
import csv
import hmac
import json
import math
import os
import queue
import secrets
import socket
import socketserver
import sqlite3
import sys
import threading
import time
from pathlib import Path

import field_io
from adapters import FirmataInput, MQTTAdapter, SerialAdapter, osc_scalar, serial_ports


def valid_config(cfg):
    if not isinstance(cfg.get("devices"), list):
        raise ValueError("devices must be an array.")
    ids, outputs, endpoints = set(), set(), set()
    for d in cfg["devices"]:
        ident = d["id"]
        if not ident.isascii() or not ident.replace("_", "").isalnum() or ident in ids:
            raise ValueError("Duplicate or invalid device ID.")
        ids.add(ident)
        transport = d.get("transport", "serial")
        field_io.validate(d)
        if transport not in ("serial","mqtt","osc","tcp","udp","artnet","sacn","modbus_tcp","modbus_rtu","midi","hid"):
            raise ValueError("Unknown transport.")
        protocol = d.get("protocol", "oes1")
        if protocol not in ("oes1","firmata","jsonl","csv","ascii","osc","binary","artnet","sacn","modbus_tcp","modbus_rtu","midi","hid"):
            raise ValueError("Unknown input protocol.")
        if transport == "osc" and protocol != "osc":
            raise ValueError("OSC transport requires the OSC protocol.")
        endpoint = (transport, str(d.get("host","")), str(d.get("port","")), str(d.get("topic",d["id"]) if transport=="mqtt" else (d.get("vendor"),d.get("product"),d.get("serial_number")) if transport=="hid" else ""))
        if endpoint in endpoints:
            raise ValueError("Two devices claim the same endpoint.")
        endpoints.add(endpoint)
        occupied = set()
        led_channels={}
        digital_pins=set()
        for pin in d.get("pins", []):
            n = pin["pin"]
            mode=pin["mode"]
            if mode not in {"analog","digital","led","led_pwm"}:raise ValueError("Unsupported Firmata pin mode.")
            max_pin = 15 if mode == "analog" else 127
            if mode!="analog":
                if n in digital_pins:raise ValueError("A digital pin has two functions.")
                digital_pins.add(n)
            if mode in {"led","led_pwm"}:
                if pin.get("channel") in led_channels:raise ValueError("Duplicate indicator binding.")
                led_channels[pin["channel"]]=1 if mode=="led" else 255
            if type(n) is not int or not 0 <= n <= max_pin or (pin["mode"], n) in occupied:
                raise ValueError("Conflicting or invalid Firmata pin.")
            occupied.add((pin["mode"], n))
        if protocol=="firmata" and (d.get("outputs") or led_channels):
            if transport!="serial" or set(led_channels)!=set(d.get("outputs",{})) or d.get("purpose")!="indicator_lighting":raise ValueError("Firmata output requires declared indicator pins on a serial board.")
            for channel,bounds in d["outputs"].items():
                if len(bounds)!=2 or bounds[0]!=0 or bounds[1]>led_channels[channel]:raise ValueError("Firmata LED range exceeds its output mode.")
        for channel, limits in d.get("outputs", {}).items():
            if protocol not in ("oes1","firmata","artnet","sacn") or channel in outputs or not channel.replace("_", "").isalnum():
                raise ValueError("Output conflict or unsupported protocol.")
            if not all(isinstance(x, (int, float)) and math.isfinite(x) for x in limits) or len(limits) != 2 or limits[0] > limits[1]:
                raise ValueError("Invalid output range.")
            outputs.add(channel)
    return cfg


class Link:
    def __init__(self, cfg, hub):
        self.cfg, self.hub = cfg, hub
        self.ident = cfg["id"]
        self.protocol = cfg.get("protocol", "oes1")
        self.transport = None
        self.connected = self.ready = self.armed = False
        self.nonce = self.boot = ""
        self.last_seen = self.sent = self.last_probe = 0
        self.sequence = 0
        self.buffer = bytearray()
        self.last_out = {}
        self.pending = {}
        self.filters = {}
        self.firmware = ""
        self.firmata = FirmataInput(cfg.get("pins", []))

    def write(self, line):
        if self.transport and self.connected:
            try:
                self.transport.write((line + "\n").encode("ascii"))
            except (ValueError, OSError, RuntimeError) as exc:
                self.connected = self.ready = self.armed = False
                self.hub.report_error(self.ident + ": " + str(exc))

    def opened(self):
        with self.hub.lock:
            self.hub.disarm()
            self.connected, self.ready = True, False
            self.last_fault=""
            if self.protocol=="firmata":self.firmata=FirmataInput(self.cfg.get("pins",[]))
            self.buffer.clear()
            self.last_seen = time.monotonic()
            if self.protocol == "oes1":
                self.write("PROBE")
            elif self.protocol == "firmata":
                self.transport.write(self.firmata.subscribe())
            self.hub.state()

    def closed(self, reason):
        with self.hub.lock:
            previously_live = self.connected or self.ready
            changed=getattr(self,"last_fault",None)!=reason
            self.last_fault=reason
            self.connected = self.ready = self.armed = False
            if previously_live:
                self.hub.disarm()
            if previously_live or changed:self.hub.report_error(self.ident + ": " + reason)

    def begin(self, boot):
        self.hub.disarm()
        self.ready = False
        self.boot = boot
        self.nonce = secrets.token_hex(6)
        self.sequence = 0
        self.write("OPEN 1 " + self.nonce + " " + boot)

    def feed(self, chunk):
        with self.hub.lock:
            if self.protocol == "firmata":
                previous=self.firmata.version_count
                for channel, value in self.firmata.feed(chunk):
                    if not self.cfg.get("outputs"):self.ready = True
                    self.last_seen = time.monotonic()
                    self.sample(channel, value)
                if previous!=self.firmata.version_count:
                    self.last_seen=time.monotonic()
                    self.ready=not self.cfg.get("outputs") or self.firmata.version >= (2,5)
                    self.firmware="Firmata "+ ".".join(map(str,self.firmata.version))
                return
            self.buffer.extend(chunk)
            if self.protocol=="binary":
                size=self.cfg["frame_bytes"]
                while len(self.buffer)>=size:
                    payload=bytes(self.buffer[:size]);del self.buffer[:size]
                    self.ready,self.last_seen=True,time.monotonic()
                    for channel,value in field_io.fields(payload,self.cfg["fields"]):self.sample(channel,value)
                return
            while b"\n" in self.buffer:
                line, _, self.buffer = self.buffer.partition(b"\n")
                if len(line) <= 512:
                    try:
                        self.line(line.decode().strip())
                    except (ValueError, IndexError, KeyError, UnicodeError, TypeError):
                        self.hub.report_error(self.ident + ": malformed input")
            if len(self.buffer) > 1024:
                self.buffer.clear()
                self.hub.report_error(self.ident + ": input frame too long")

    def line(self, line):
        if not line:
            return
        now = time.monotonic()
        if self.protocol != "oes1":
            if self.protocol == "jsonl":
                msg = json.loads(line)
                key, value = msg["channel"], msg["value"]
            elif self.protocol == "csv":
                key, value = next(csv.reader([line]))
                value = float(value)
            elif self.protocol == "ascii":
                key, value = line.split(maxsplit=1)
                value = float(value)
            else:
                return
            self.ready, self.last_seen = True, now
            self.sample(key, value)
            return
        parts = line.split()
        kind = parts[0]
        if kind == "BOOT" and len(parts) == 2:
            if parts[1] != self.boot or not self.ready:
                self.begin(parts[1])
            return
        if kind == "HELLO" and len(parts) >= 6 and parts[1:4] == ["1", self.ident, self.nonce] and self.nonce:
            self.ready, self.last_seen = True, now
            self.firmware = parts[4]
            self.hub.state()
            return
        if not self.ready or len(parts) < 2 or parts[1] != self.nonce:
            return
        self.last_seen = now
        if kind == "IN" and len(parts) == 4:
            self.sample(parts[2], float(parts[3]))
        elif kind == "ARMED":
            self.armed = self.hub.owner is not None and not self.hub.lockout
            if not self.armed:
                self.write("OFF")
            self.hub.state()
        elif kind == "ACK" and len(parts) == 3:
            self.pending.pop(int(parts[2]), None)
        elif kind == "ERR":
            self.hub.disarm()
            self.hub.report_error(self.ident + ": " + " ".join(parts[2:]))

    def sample(self, channel, value):
        if channel not in self.cfg.get("inputs", []):
            return
        if not isinstance(value, (str, int, float, bool)) or isinstance(value, str) and len(value) > 240:
            return
        if isinstance(value, (int, float)) and not math.isfinite(value):
            return
        opts = self.cfg.get("filters", {}).get(channel, {})
        now = time.monotonic()
        if opts and isinstance(value, (int, float)):
            record = self.filters.setdefault(channel, {"last": None, "at": 0, "average": None, "candidate": None, "since": 0})
            value = value * opts.get("scale", 1) + opts.get("offset", 0)
            alpha = min(1, max(0, float(opts.get("alpha", 1))))
            value = value if record["average"] is None else alpha * value + (1-alpha) * record["average"]
            record["average"] = value
            if record["candidate"] != value:
                record.update(candidate=value, since=now)
            if now - record["since"] < opts.get("debounce_ms", 0)/1000 or now - record["at"] < opts.get("interval_ms", 0)/1000:
                return
            if record["last"] is not None and abs(value-record["last"]) < opts.get("epsilon", 0):
                return
            record.update(last=value, at=now)
        self.hub.broadcast(dict(op="input", device=self.ident, channel=channel, value=value))
        if self.hub.recorder is not None:
            self.hub.recorder.execute("insert into samples values(?,?,?,?)", (time.time(), self.ident, channel, json.dumps(value)))
            self.hub.recorder.commit()

    def output(self, channel, value, now):
        limits = self.cfg["outputs"][channel]
        if not self.ready or not self.armed or isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not limits[0] <= value <= limits[1]:
            raise ValueError("Output rejected by device state or configured limits.")
        if now - self.last_out.get(channel, 0) < 0.05:
            raise ValueError("Output rate limit (20 Hz).")
        self.last_out[channel] = now
        if self.protocol=="firmata":
            pin=next(p for p in self.cfg["pins"] if p["channel"]==channel and p["mode"] in {"led","led_pwm"})
            try:self.transport.write(self.firmata.indicator(pin,int(round(value))))
            except OSError as exc:
                self.closed(str(exc));raise ValueError("Indicator board disconnected.") from exc
            return
        if isinstance(self.transport,field_io.LightingOutput):
            try:self.transport.set_level(channel,value)
            except OSError as exc:
                self.closed(str(exc))
                raise ValueError("Lighting socket failed.") from exc
            return
        self.sequence += 1
        self.pending[self.sequence] = now
        self.write("OUT %s %d %s %d" % (self.nonce, self.sequence, channel, round(value)))


class Hub:
    def __init__(self, cfg):
        self.lock = threading.RLock()
        self.clients = set()
        self.owner, self.lease = None, 0
        self.lockout = cfg.get("lockout", False)
        self.links = {d["id"]: Link(d, self) for d in valid_config(cfg)["devices"]}
        self.recorder = None
        self.threads = []
        self.stopping = threading.Event()

    def broadcast(self, msg, exclude=None):
        for client in tuple(self.clients):
            if client is exclude:
                continue
            try:
                client.put_nowait(msg)
            except queue.Full:
                self.clients.discard(client)
                if self.owner is client:
                    self.disarm()

    def summary(self):
        outputs = [l for l in self.links.values() if l.cfg.get("outputs")]
        return dict(op="state", armed=bool(self.owner and outputs and all(l.armed for l in outputs)),
                    devices={l.ident: ("armed" if l.armed else "ready " + l.firmware if l.ready else "awaiting data" if l.connected else "offline") for l in self.links.values()})

    def state(self):
        self.broadcast(self.summary())

    def report_error(self, reason):
        self.broadcast(dict(op="error", message=reason))

    def disarm(self):
        self.owner = None
        for link in self.links.values():
            link.armed = False
            link.pending.clear()
            if link.protocol == "oes1" and link.connected:
                link.write("OFF")
            elif link.protocol=="firmata" and link.cfg.get("outputs") and link.connected:
                try:link.transport.write(link.firmata.safe())
                except OSError:link.ready=link.connected=False
            elif isinstance(link.transport,field_io.LightingOutput) and link.connected:
                try:link.transport.blackout()
                except OSError:link.ready=link.connected=False
        self.state()

    def command(self, client, msg):
        with self.lock:
            op, now = msg.get("op"), time.monotonic()
            if op == "heartbeat":
                if self.owner is client:
                    self.lease = now
                return self.summary()
            if op == "disarm":
                self.disarm()
            elif op == "arm":
                links = [l for l in self.links.values() if l.cfg.get("outputs")]
                if self.lockout or self.owner not in (None, client) or not links or not all(l.ready and now-l.last_seen < 1.5 for l in links):
                    raise ValueError("Arming requires ready devices, exclusive control and maintenance lockout off.")
                self.owner, self.lease = client, now
                for link in links:
                    if link.protocol=="firmata":
                        try:link.transport.write(link.firmata.safe())
                        except OSError as exc:
                            self.disarm();raise ValueError("Indicator board disconnected.") from exc
                        link.armed=True
                    elif isinstance(link.transport,field_io.LightingOutput):
                        link.transport.blackout()
                        link.armed=True
                    else:link.write("ARM " + link.nonce)
            elif op == "out":
                if self.owner is not client or now-self.lease > 1.5:
                    raise ValueError("Physical outputs are disarmed.")
                channel = msg.get("channel", "")
                for link in self.links.values():
                    if channel in link.cfg.get("outputs", {}):
                        link.output(channel, msg.get("value"), now)
                        return None
                raise ValueError("Unknown output channel.")
            elif op == "inject" and msg.get("channel") in ("page", "motion_x", "motion_y", "presence", "gesture"):
                value = msg.get("value")
                if not isinstance(value,(float,int)) or not math.isfinite(value):
                    raise ValueError("Invalid sensor value.")
                self.broadcast(dict(op="input", device="local-plugin", channel=msg["channel"], value=value), exclude=client)
            else:
                raise ValueError("Unknown command.")
            return self.summary()

    def tick(self):
        now = time.monotonic()
        with self.lock:
            if self.owner is not None and now-self.lease > 1.5:
                self.disarm()
            for l in self.links.values():
                if not l.connected:
                    continue
                if l.protocol == "oes1":
                    if l.ready and (now-l.last_seen > 1.5 or any(now-t > 0.9 for t in l.pending.values())):
                        self.disarm()
                        l.ready = False
                        l.boot = ""
                        self.report_error(l.ident + ": device heartbeat or output acknowledgement expired")
                    if now-l.sent > 0.3:
                        l.write(("HB " + l.nonce) if l.ready else "PROBE")
                        l.sent = now
                elif l.cfg.get("transport") in ("udp","artnet","sacn") and isinstance(l.transport,field_io.Input) and l.ready and now-l.last_seen>2.5:
                    l.ready=False
                    self.state()
                elif l.protocol=="firmata" and l.cfg.get("outputs") and now-l.last_probe>.45:
                    if now-l.last_seen>1.5 and l.ready:
                        self.disarm();l.ready=False;self.report_error(l.ident+": Firmata heartbeat expired")
                    try:l.transport.write(bytes([0xf9]))
                    except OSError as exc:l.closed(str(exc))
                    l.last_probe=now
                elif l.protocol == "firmata" and not l.ready and now-l.last_probe > 2:
                    try:
                        l.transport.write(l.firmata.subscribe())
                    except OSError as exc:
                        l.closed(str(exc))
                    l.last_probe = now

    def start(self):
        for l in self.links.values():
            transport = l.cfg.get("transport", "serial")
            if transport in {"tcp","udp","artnet","sacn","modbus_tcp","modbus_rtu","midi","hid"}:
                l.transport=field_io.LightingOutput(l) if transport in {"artnet","sacn"} and l.cfg.get("outputs") else field_io.Input(l)
                t=threading.Thread(target=l.transport.run,daemon=True)
            elif transport == "osc":
                t = threading.Thread(target=self.osc_loop, args=(l,), daemon=True)
            else:
                adapter = MQTTAdapter if transport == "mqtt" else SerialAdapter
                l.transport = adapter(l.cfg, l.feed, l.opened, l.closed)
                t = threading.Thread(target=l.transport.run, daemon=True)
            t.start()
            self.threads.append(t)
        def clock():
            while not self.stopping.wait(.1):
                self.tick()
        threading.Thread(target=clock, daemon=True).start()

    def osc_loop(self, link):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.bind(("127.0.0.1", int(link.cfg["port"])))
                sock.settimeout(.3)
                with self.lock:
                    link.connected = True
                while not self.stopping.is_set():
                    try:
                        addr, value = osc_scalar(sock.recv(1024))
                        with self.lock:
                            link.ready = True
                            link.sample(link.cfg.get("routes", {}).get(addr), value)
                    except (ValueError, IndexError, UnicodeError, TimeoutError, __import__("struct").error):
                        continue
        except OSError as exc:
            link.closed(str(exc))

    def close(self):
        with self.lock:
            self.disarm()
            self.stopping.set()
            for l in self.links.values():
                if l.transport:
                    l.transport.stop.set()
        for thread in self.threads:
            thread.join(timeout=2)
        if self.recorder:
            self.recorder.close()


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(.10)
        responses = queue.Queue(maxsize=256)
        hub = self.server.hub
        authenticated = False
        buf = bytearray()
        last = time.monotonic()
        try:
            while not hub.stopping.is_set() and time.monotonic()-last < 4:
                try:
                    chunk = self.request.recv(4096)
                    if not chunk:
                        break
                    buf.extend(chunk)
                except socket.timeout:
                    pass
                if len(buf) > 32768:
                    break
                while b"\n" in buf:
                    line, _, buf = buf.partition(b"\n")
                    if len(line) > 4096:
                        return
                    msg = json.loads(line)
                    if not isinstance(msg, dict):
                        return
                    if not authenticated:
                        if msg.get("op") != "hello" or msg.get("v") != 1 or not hmac.compare_digest(str(msg.get("token","")).encode(), self.server.token.encode()):
                            return
                        authenticated = True
                        with hub.lock:
                            hub.clients.add(responses)
                        responses.put_nowait(dict(op="hello", v=1))
                    else:
                        try:
                            reply = hub.command(responses, msg)
                        except (ValueError, KeyError) as exc:
                            reply = dict(op="error", message=str(exc))
                        if reply:
                            responses.put_nowait(reply)
                    last = time.monotonic()
                while not responses.empty():
                    payload = json.dumps(responses.get_nowait(), separators=(",",":")) + "\n"
                    self.request.sendall(payload.encode())
        except (OSError, UnicodeError, ValueError, queue.Full):
            pass
        finally:
            with hub.lock:
                hub.clients.discard(responses)
                if hub.owner is responses:
                    hub.disarm()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--port", type=int, default=18440)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--record", type=Path, help="Opt in to a local SQLite sensor log.")
    args = parser.parse_args()
    if args.list:
        print(json.dumps(serial_ports(), indent=2))
        return
    token = os.getenv("OPENEXHIBIT_TOKEN") or secrets.token_urlsafe(24)
    if len(token) < 16:
        raise SystemExit("Use a gateway token of at least 16 characters.")
    cfg = json.loads(args.config.read_text(encoding="utf-8")) if args.config else {"devices":[]}
    hub = Hub(cfg)
    if args.record:
        hub.recorder = sqlite3.connect(args.record, check_same_thread=False)
        hub.recorder.execute("create table if not exists samples(time real, device text, channel text, value text)")
    with Server(("127.0.0.1", args.port), Handler) as server:
        server.hub, server.token = hub, token
        hub.start()
        print("Gateway on 127.0.0.1:%d" % server.server_address[1], flush=True)
        if not os.getenv("OPENEXHIBIT_TOKEN"):
            print("Local operator token: " + token, flush=True)
        try:
            server.serve_forever(.2)
        except KeyboardInterrupt:
            pass
        finally:
            hub.close()


if __name__ == "__main__":
    main()

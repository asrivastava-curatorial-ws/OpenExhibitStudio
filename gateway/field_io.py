"""Unicast lighting levels and input transports for local exhibit networks."""

import ipaddress
import math
import socket
import struct
import threading
import time
import uuid


def private_address(value):
    address = ipaddress.IPv4Address(value)
    if not address.is_private or address.is_unspecified or address.is_multicast or address.is_reserved:
        raise ValueError("Select an explicit local IPv4 address.")
    return str(address)


def levels_packet(protocol, universe, seq, levels, cid):
    data = bytes(levels)
    if not 1 <= len(data) <= 512:
        raise ValueError("Expected 1–512 DMX levels.")
    if protocol == "artnet":
        if not 0 <= universe <= 32767:
            raise ValueError("Art-Net universe out of range.")
        if len(data) % 2:
            data += b"\0"
        return (
            b"Art-Net\0"
            + struct.pack("<H", 0x5000)
            + struct.pack(">HBB", 14, seq, 0)
            + struct.pack("<H", universe)
            + struct.pack(">H", len(data))
            + data
        )
    if protocol != "sacn" or not 1 <= universe <= 63999 or len(cid) != 16:
        raise ValueError("Invalid sACN source or universe.")

    def pdu(body):
        return struct.pack(">H", 0x7000 | len(body) + 2) + body

    dmp = pdu(struct.pack(">BBHHH", 2, 0xA1, 0, 1, len(data) + 1) + b"\0" + data)
    frame = pdu(struct.pack(">I64sBHBBH", 2, b"OpenExhibit Studio", 100, 0, seq, 0, universe) + dmp)
    return b"\x00\x10\x00\x00ASC-E1.17\x00\x00\x00" + pdu(struct.pack(">I", 4) + cid + frame)


def parse_levels(protocol, packet):
    if protocol == "artnet":
        if (
            len(packet) < 20
            or packet[:10] != b"Art-Net\0\x00\x50"
            or int.from_bytes(packet[10:12], "big") < 14
        ):
            raise ValueError("Unexpected Art-Net frame.")
        length = int.from_bytes(packet[16:18], "big")
        if not 2 <= length <= 512 or length % 2 or len(packet) != 18 + length:
            raise ValueError("Invalid ArtDMX length.")
        return int.from_bytes(packet[14:16], "little"), packet[12], packet[18:]
    if (
        len(packet) < 127
        or packet[:16] != b"\x00\x10\x00\x00ASC-E1.17\0\0\0"
        or packet[18:22] != b"\0\0\0\4"
        or packet[40:44] != b"\0\0\0\2"
    ):
        raise ValueError("Unexpected E1.31 data frame.")
    for idx in (16, 38, 115):
        if int.from_bytes(packet[idx : idx + 2], "big") != (0x7000 | len(packet) - idx):
            raise ValueError("Invalid ACN PDU length.")
    if packet[112] & 0xE0 or packet[117:123] != b"\x02\xa1\x00\x00\x00\x01" or packet[125] != 0:
        raise ValueError("Unsupported sACN options or start code.")
    count = int.from_bytes(packet[123:125], "big")
    if not 2 <= count <= 513 or len(packet) != 125 + count:
        raise ValueError("Invalid sACN slot count.")
    return int.from_bytes(packet[113:115], "big"), packet[111], packet[126:]


FORMATS = {
    "u8": "B",
    "s8": "b",
    "u16le": "<H",
    "u16be": ">H",
    "s16le": "<h",
    "s16be": ">h",
    "f32le": "<f",
    "f32be": ">f",
}


def fields(data, mapping):
    for name, entry in mapping.items():
        offset, kind = entry["offset"], entry["type"]
        if offset + struct.calcsize(FORMATS[kind]) > len(data):
            continue
        value = struct.unpack_from(FORMATS[kind], data, offset)[0]
        if math.isfinite(value):
            yield name, value


class Input:
    def __init__(self, link):
        self.link = link
        self.cfg = link.cfg
        self.stop = threading.Event()

    def emit(self, items):
        with self.link.hub.lock:
            self.link.ready = True
            self.link.last_seen = time.monotonic()
            for name, value in items:
                self.link.sample(name, value)

    def run(self):
        while not self.stop.is_set():
            try:
                typ = self.cfg["transport"]
                getattr(
                    self,
                    {
                        "udp": "network",
                        "tcp": "network",
                        "artnet": "lighting_in",
                        "sacn": "lighting_in",
                        "modbus_tcp": "modbus",
                        "modbus_rtu": "modbus",
                        "midi": "midi",
                        "hid": "hid",
                    }[typ],
                )()
            except Exception as exc:
                self.link.closed(str(exc))
            self.stop.wait(1)

    def opened(self):
        self.link.opened()

    def network(self):
        d = self.cfg
        udp = d["transport"] == "udp"
        host = private_address(d["host"])
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM) as sock:
            sock.settimeout(1)
            if udp:
                sock.bind((host, d["port"]))
            else:
                sock.connect((host, d["port"]))
            self.opened()
            sock.settimeout(0.2)
            while not self.stop.is_set():
                try:
                    if udp:
                        data, source = sock.recvfrom(4096)
                        if source[0] != d["peer"]:
                            continue
                    else:
                        data = sock.recv(4096)
                        if not data:
                            raise OSError("TCP device disconnected.")
                except TimeoutError:
                    continue
                if udp and d["protocol"] == "binary":
                    if len(data) == d["frame_bytes"]:
                        self.emit(fields(data, d["fields"]))
                else:
                    self.link.feed(data + (b"\n" if udp and not data.endswith(b"\n") else b""))

    def lighting_in(self):
        d = self.cfg
        protocol = d["transport"]
        last = None
        last_t = 0
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind((private_address(d["host"]), d["port"]))
            sock.settimeout(0.25)
            self.opened()
            while not self.stop.is_set():
                try:
                    packet, addr = sock.recvfrom(1000)
                except TimeoutError:
                    continue
                if addr[0] != d["peer"]:
                    continue
                try:
                    uni, seq, levels = parse_levels(protocol, packet)
                except ValueError:
                    continue
                if uni != d["universe"]:
                    continue
                now = time.monotonic()
                if (
                    (seq or protocol == "sacn")
                    and last is not None
                    and now - last_t < 2
                    and (seq - last) % 256 not in range(1, 128)
                ):
                    continue
                last, last_t = seq, now
                self.emit(
                    (name, levels[slot - 1]) for name, slot in d["slots"].items() if slot <= len(levels)
                )

    def modbus(self):
        from pymodbus.client import ModbusSerialClient, ModbusTcpClient

        d = self.cfg
        if d['transport'] == 'modbus_tcp':
            client = ModbusTcpClient(private_address(d['host']), port=d['port'], timeout=1, retries=0)
        else:
            client = ModbusSerialClient(port=d['port'], baudrate=d.get('baud', 9600), timeout=0.5, retries=0)
        try:
            if not client.connect():
                raise OSError("Modbus device unavailable.")
            self.opened()
            methods = {
                'holding': 'read_holding_registers',
                'input': 'read_input_registers',
                'coil': 'read_coils',
                'discrete': 'read_discrete_inputs',
            }
            while not self.stop.is_set():
                values = []
                for name, r in d['registers'].items():
                    result = getattr(client, methods[r['bank']])(
                        r['address'], count=1, device_id=d.get('unit', 1)
                    )
                    if result.isError():
                        raise OSError("Modbus read returned an exception.")
                    values.append(
                        (name, (result.bits if r['bank'] in ('coil', 'discrete') else result.registers)[0])
                    )
                self.emit(values)
                self.stop.wait(d.get('interval', 0.25))
        finally:
            client.close()

    def midi(self):
        import mido

        d = self.cfg
        with mido.open_input(d["port"]) as device:
            self.opened()
            while not self.stop.is_set():
                for msg in device.iter_pending():
                    for name, r in d['midi'].items():
                        if getattr(msg, 'channel', -1) != r.get('channel', 0):
                            continue
                        if msg.type == 'control_change' and r['kind'] == 'cc' and msg.control == r['number']:
                            self.emit([(name, msg.value)])
                        if (
                            msg.type in ('note_on', 'note_off')
                            and r['kind'] == 'note'
                            and msg.note == r['number']
                        ):
                            self.emit([(name, 0 if msg.type == 'note_off' else msg.velocity)])
                self.stop.wait(0.01)

    def hid(self):
        import hid

        d = self.cfg
        device = hid.device()
        try:
            device.open(d['vendor'], d['product'], d.get('serial_number'))
            self.opened()
            while not self.stop.is_set():
                x = bytes(device.read(d.get('frame_bytes', 64), 100))
                if x:
                    self.emit(fields(x, d['fields']))
        finally:
            device.close()


class LightingOutput:
    """Dedicated, explicitly armed indicator/dimmer universe. UDP delivery is unconfirmed."""

    def __init__(self, link):
        self.link = link
        self.cfg = link.cfg
        self.stop = threading.Event()
        self.sock = None
        self.levels = bytearray(max(self.cfg['slots'].values()))
        self.seq = 0
        self.cid = uuid.uuid5(uuid.NAMESPACE_DNS, 'openexhibit.' + self.cfg['id']).bytes

    def send(self):
        if self.sock is None:
            return
        d = self.cfg
        typ = d['transport']
        self.seq = (self.seq + 1) % 256
        if typ == 'artnet' and self.seq == 0:
            self.seq = 1
        packet = levels_packet(typ, d['universe'], self.seq, self.levels, self.cid)
        self.sock.sendto(packet, (d['peer'], d['port']))

    def blackout(self):
        self.levels[:] = bytes(len(self.levels))
        self.send()

    def set_level(self, name, value):
        self.levels[self.cfg['slots'][name] - 1] = int(round(value))
        self.send()

    def run(self):
        while not self.stop.is_set():
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                    sock.bind((self.cfg['host'], 0))
                    with self.link.hub.lock:
                        self.sock = sock
                        self.link.opened()
                        self.blackout()
                        self.link.ready = True
                        self.link.firmware = 'lighting sender · receiver unconfirmed'
                    while not self.stop.wait(0.1):
                        with self.link.hub.lock:
                            self.link.last_seen = time.monotonic()
                            if self.link.armed:
                                self.send()
            except OSError as exc:
                self.link.closed(str(exc))
            finally:
                with self.link.hub.lock:
                    self.sock = None
            self.stop.wait(0.5)


def validate(d):
    typ = d.get("transport", "serial")
    protocol = d.get("protocol", "oes1")
    other = {"tcp", "udp", "modbus_tcp", "modbus_rtu", "artnet", "sacn", "midi", "hid"}
    if typ not in other and protocol != "binary":
        return
    if typ in {"udp", "tcp", "modbus_tcp", "artnet", "sacn"}:
        private_address(d['host'])
        if type(d["port"]) is not int or not 1 <= d["port"] <= 65535:
            raise ValueError("Invalid network port.")
    if typ in {"artnet", "sacn", "udp"}:
        private_address(d["peer"])
    if typ in {"artnet", "sacn", "hid", "midi", "modbus_rtu", "modbus_tcp"} and protocol != typ:
        raise ValueError("Select the matching device protocol.")
    if typ in {"tcp", "udp"} and protocol not in {"binary", "ascii", "jsonl", "csv"}:
        raise ValueError("Select an input frame protocol.")
    if protocol == "binary" or typ == "hid":
        if typ not in {"tcp", "udp", "serial", "hid"} or not 1 <= d.get("frame_bytes", 0) <= 512:
            raise ValueError("Invalid binary frame length.")
        for k, v in d["fields"].items():
            if (
                k not in d["inputs"]
                or v["type"] not in FORMATS
                or type(v["offset"]) is not int
                or not 0 <= v["offset"] <= d["frame_bytes"] - struct.calcsize(FORMATS[v["type"]])
            ):
                raise ValueError("Invalid binary field.")
    if typ in {"artnet", "sacn"}:
        lo, hi = (0, 32767) if typ == "artnet" else (1, 63999)
        if type(d['universe']) is not int or not lo <= d['universe'] <= hi:
            raise ValueError("Invalid lighting universe.")
        slots = d['slots']
        outputs = d.get('outputs', {})
        if (
            not slots
            or set(slots) != (set(outputs) if outputs else set(d['inputs']))
            or any(type(v) is not int or not 1 <= v <= 512 for v in slots.values())
            or len(slots) != len(set(slots.values()))
        ):
            raise ValueError("Invalid lighting slot mapping.")
        if outputs and (
            d.get('purpose') != 'indicator_lighting'
            or not d.get('receiver_loss_blackout')
            or any(len(l) != 2 or l[0] != 0 or l[1] > 255 for l in outputs.values())
        ):
            raise ValueError(
                "Use a dedicated indicator-lighting universe with receiver loss blackout and a zero minimum."
            )
    if typ.startswith("modbus_"):
        if not 0.05 <= d.get('interval', 0.25) <= 30 or not 1 <= d.get('unit', 1) <= 247:
            raise ValueError("Invalid Modbus polling settings.")
        for k, v in d['registers'].items():
            if (
                k not in d['inputs']
                or v['bank'] not in ('holding', 'input', 'coil', 'discrete')
                or not 0 <= v['address'] <= 65535
            ):
                raise ValueError("Invalid Modbus register.")
    if typ == 'midi':
        for k, v in d['midi'].items():
            if (
                k not in d['inputs']
                or v['kind'] not in ('cc', 'note')
                or not 0 <= v['number'] <= 127
                or not 0 <= v.get('channel', 0) <= 15
            ):
                raise ValueError("Invalid MIDI mapping.")

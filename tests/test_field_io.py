import queue
import socket
import struct
import sys
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'gateway'))
from openexhibit_gateway import Hub, valid_config
from field_io import levels_packet, parse_levels


def port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def await_state(test, cond):
    end = time.monotonic() + 4
    while not cond() and time.monotonic() < end:
        time.sleep(0.015)
    test.assertTrue(cond())


class FieldTests(unittest.TestCase):
    def lighting(self, typ, pr, output=False):
        result = dict(
            id='dmx',
            transport=typ,
            protocol=typ,
            host='127.0.0.1',
            peer='127.0.0.1',
            port=pr,
            universe=4,
            slots={'lamp': 2},
            inputs=[] if output else ['lamp'],
        )
        if output:
            result.update(
                outputs={'lamp': [0, 80]}, purpose='indicator_lighting', receiver_loss_blackout=True
            )
        return result

    def test_lighting_wire_headers_counts_and_rejection(self):
        cid = bytes(range(16))
        for typ in ('artnet', 'sacn'):
            p = levels_packet(typ, 12, 4, [10, 20, 30, 40], cid)
            self.assertEqual(parse_levels(typ, p), (12, 4, bytes([10, 20, 30, 40])))
            with self.assertRaises(ValueError):
                parse_levels(typ, p[:-1])
            if typ == 'artnet':
                self.assertEqual(p[:18], bytes.fromhex('4172742d4e6574000050000e04000c000004'))
            else:
                self.assertEqual(p[16:22], bytes.fromhex('707200000004'))
                self.assertEqual(p[22:38], cid)
                self.assertEqual(p[117:126], bytes.fromhex('02a100000001000500'))

    def test_lighting_output_lease_disarm_and_limits_on_real_udp(self):
        for typ in ('artnet', 'sacn'):
            with self.subTest(typ=typ), socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
                receiver.bind(('127.0.0.1', 0))
                receiver.settimeout(2)
                cfg = self.lighting(typ, receiver.getsockname()[1], True)
                hub = Hub({'devices': [cfg]})
                hub.start()
                try:
                    q = queue.Queue()
                    await_state(self, lambda: hub.links['dmx'].last_seen > 0)  # noqa: B023 (awaited here)
                    self.assertEqual(parse_levels(typ, receiver.recv(700))[2][1], 0)
                    with self.assertRaises(ValueError):
                        hub.command(q, dict(op='out', channel='lamp', value=45))
                    hub.command(q, {'op': 'arm'})
                    with self.assertRaises(ValueError):
                        hub.command(q, dict(op='out', channel='lamp', value=100))
                    hub.command(q, dict(op='out', channel='lamp', value=45))
                    while parse_levels(typ, receiver.recv(700))[2][1] != 45:
                        pass
                    hub.lease -= 2
                    hub.tick()
                    while parse_levels(typ, receiver.recv(700))[2][1] != 0:
                        pass
                    self.assertFalse(hub.summary()['armed'])
                finally:
                    hub.close()

    def test_artnet_input_filters_universe_and_sequence(self):
        pr = port()
        hub = Hub({'devices': [self.lighting('artnet', pr)]})
        received = queue.Queue()
        hub.clients.add(received)
        hub.start()
        try:
            await_state(self, lambda: hub.links['dmx'].connected)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
                for uni, seq, val in [(3, 1, 87), (4, 255, 42), (4, 254, 13), (4, 1, 44)]:
                    sender.sendto(levels_packet('artnet', uni, seq, [0, val], bytes(16)), ('127.0.0.1', pr))
            values = []
            deadline = time.monotonic() + 2
            while len(values) < 2 and time.monotonic() < deadline:
                v = received.get(timeout=1)
                if v['op'] == 'input':
                    values.append(v['value'])
            self.assertEqual(values, [42, 44])
        finally:
            hub.close()

    def test_binary_frames_through_public_gateway_path(self):
        cfg = dict(
            id='bin',
            transport='serial',
            protocol='binary',
            port='test',
            inputs=['dial', 'temp'],
            frame_bytes=4,
            fields={'dial': {'offset': 0, 'type': 'u16be'}, 'temp': {'offset': 2, 'type': 's16le'}},
        )
        hub = Hub({'devices': [cfg]})
        q = queue.Queue()
        hub.clients.add(q)
        hub.links['bin'].feed(b'\x01')
        hub.links['bin'].feed(b'\x02\xfe\xff')
        self.assertEqual([(q.get()['value']) for _ in range(2)], [258, -2])
        with self.assertRaises(ValueError):
            valid_config({'devices': [{**cfg, 'frame_bytes': 1}]})

    def test_input_only_protocol_rejects_armed_configuration(self):
        d = dict(
            id='midi',
            transport='midi',
            protocol='midi',
            port='virtual',
            inputs=['dial'],
            midi={'dial': dict(kind='cc', number=7)},
            outputs={'lamp': [0, 1]},
        )
        with self.assertRaises(ValueError):
            valid_config({'devices': [d]})

    def test_real_modbus_tcp_reads_register(self):
        try:
            import pymodbus  # noqa: F401 (availability check)
        except ImportError:
            self.skipTest('Install optional pymodbus==3.11.4')
        with socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen()

            def serve():
                with server.accept()[0] as client:
                    req = client.recv(12)
                    self.assertEqual(req[7:], bytes.fromhex('03000a0001'))
                    client.sendall(req[:4] + struct.pack('>H', 5) + req[6:8] + bytes([2, 0x12, 0x34]))
                    time.sleep(0.3)

            thread = threading.Thread(target=serve)
            thread.start()
            hub = Hub(
                {
                    'devices': [
                        dict(
                            id='meter',
                            transport='modbus_tcp',
                            protocol='modbus_tcp',
                            host='127.0.0.1',
                            port=server.getsockname()[1],
                            inputs=['dial'],
                            registers={'dial': dict(bank='holding', address=10)},
                        )
                    ]
                }
            )
            q = queue.Queue()
            hub.clients.add(q)
            hub.start()
            try:
                while True:
                    msg = q.get(timeout=3)
                    if msg['op'] == 'input':
                        self.assertEqual(msg['value'], 4660)
                        break
            finally:
                hub.close()
                thread.join(2)


if __name__ == '__main__':
    unittest.main()


class IndicatorTests(unittest.TestCase):
    def test_version_arm_command_disconnect_sequence(self):
        import json

        cfg = json.loads((ROOT / 'gateway/profiles/firmata-indicator.json').read_text())
        hub = Hub(cfg)
        link = hub.links['uno']

        class Wire:
            def __init__(self):
                self.values = []

            def write(self, msg):
                self.values.append(msg)

        wire = Wire()
        link.transport = wire
        link.opened()
        self.assertIn(bytes([0xF4, 13, 1, 0xF5, 13, 0]), wire.values[-1])
        owner = queue.Queue()
        with self.assertRaises(ValueError):
            hub.command(owner, {'op': 'arm'})
        link.feed(bytes([0xF9, 2, 6]))
        hub.command(owner, {'op': 'arm'})
        hub.command(owner, dict(op='out', channel='lamp', value=1))
        self.assertEqual(wire.values[-1], bytes([0xF5, 13, 1]))
        hub.command(owner, {'op': 'disarm'})
        self.assertEqual(wire.values[-1], bytes([0xF5, 13, 0]))
        link.closed('USB removed')
        link.opened()
        self.assertFalse(link.armed)
        self.assertFalse(link.ready)
        hub.links['uno'].feed(bytes([0xF9, 2, 3]))
        with self.assertRaises(ValueError):
            hub.command(owner, {'op': 'arm'})

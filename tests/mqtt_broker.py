#!/usr/bin/env python3
"""Run the real Paho adapter against authenticated Mosquitto and a native firmware endpoint fixture."""

import argparse
import os
import queue
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
import paho.mqtt.client as mqtt

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'gateway'))
from openexhibit_gateway import Hub


def wait(condition, reason):
    end = time.monotonic() + 8
    while time.monotonic() < end:
        if condition():
            return
        time.sleep(0.03)
    raise AssertionError(reason)


def run(broker, passwd):
    with tempfile.TemporaryDirectory() as t:
        folder = Path(t)
        token = secrets.token_urlsafe(16)
        pwfile = folder / 'passwords'
        for i, user in enumerate(['fixture', 'studio']):
            subprocess.run(
                [passwd, '-b'] + (['-c'] if i == 0 else []) + [str(pwfile), user, token],
                check=True,
                stdout=subprocess.DEVNULL,
            )
        with socket.socket() as free:
            free.bind(('127.0.0.1', 0))
            port = free.getsockname()[1]
        conf = folder / 'broker.conf'
        settings = (
            f'listener {port} 127.0.0.1\nallow_anonymous false\npassword_file {pwfile}\npersistence false\n'
        )
        if hasattr(os, 'geteuid') and os.geteuid() == 0:
            # Started as root, Mosquitto switches to its own account and then cannot read the
            # password file in this private temporary folder. Keep this loopback-only fixture as is.
            settings += 'user root\n'
        conf.write_text(settings)
        program = folder / 'fixture'
        subprocess.run(
            [
                'c++',
                '-std=c++17',
                '-I' + str(ROOT / 'firmware/libraries/OpenExhibitProtocol/src'),
                str(ROOT / 'tests/board_fixture.cpp'),
                '-o',
                str(program),
            ],
            check=True,
        )
        events = queue.Queue()
        proc = None
        sim = None
        client = None
        hub = None
        broker_log = (folder / 'broker.log').open('w')
        try:
            proc = subprocess.Popen([broker, '-c', str(conf)], stdout=broker_log, stderr=subprocess.STDOUT)

            def listening():
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.3):
                        return True
                except OSError:
                    return False

            try:
                wait(listening, 'Broker did not open its local authenticated listener.')
            except AssertionError as error:
                raise AssertionError(f'{error}\n{(folder / "broker.log").read_text()}') from None
            sim = subprocess.Popen(
                [str(program)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1
            )
            client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='board-emulator')
            client.username_pw_set('fixture', token)
            subscribed = threading.Event()
            client.on_connect = lambda c, u, f, rc, p: c.subscribe('oes/bench/down')
            client.on_subscribe = lambda *_: subscribed.set()

            def down(c, u, m):
                if not m.retain and sim.poll() is None:
                    sim.stdin.write(m.payload.decode().strip() + '\n')
                    sim.stdin.flush()

            client.on_message = down
            client.connect('127.0.0.1', port)
            client.loop_start()
            if not subscribed.wait(5):
                raise AssertionError('No subscription acknowledgement.')

            def route():
                for line in sim.stdout:
                    client.publish('oes/bench/up', line.strip(), qos=0, retain=False)

            route_thread = threading.Thread(target=route, daemon=True)
            route_thread.start()
            os.environ['OES_MQTT_BENCH_PASS'] = token
            hub = Hub(
                {
                    'devices': [
                        dict(
                            id='uno',
                            host='127.0.0.1',
                            port=port,
                            transport='mqtt',
                            protocol='oes1',
                            topic='oes/bench',
                            username='studio',
                            password_env='OES_MQTT_BENCH_PASS',
                            inputs=['dial', 'lamp_echo'],
                            outputs={'lamp': [0, 1]},
                        )
                    ]
                }
            )
            hub.clients.add(events)
            hub.start()
            link = hub.links['uno']
            wait(lambda: link.ready, 'Protocol handshake did not finish.')
            owner = queue.Queue()
            hub.command(owner, {'op': 'arm'})
            wait(lambda: link.armed, 'Arm did not acknowledge.')
            hub.command(owner, dict(op='out', channel='lamp', value=1))
            end = time.monotonic() + 4
            seen = {}
            while time.monotonic() < end and (seen.get('lamp_echo') != 1 or seen.get('dial') != 72):
                hub.command(owner, {'op': 'heartbeat'})
                try:
                    evt = events.get(timeout=0.1)
                except queue.Empty:
                    continue
                if evt['op'] == 'input':
                    seen[evt['channel']] = evt['value']
            assert seen.get('lamp_echo') == 1 and seen.get('dial') == 72, seen
            proc.terminate()
            proc.wait(timeout=4)
            wait(lambda: not link.armed and not link.ready, 'Broker loss did not clear output state.')
            print(
                'PASS authenticated Mosquitto + Paho: firmware handshake, input 72, armed indicator, feedback 1 and broker-loss disarm. Board endpoint is a compiled fixture.'
            )
        finally:
            if hub:
                hub.close()
            if client:
                client.disconnect()
                client.loop_stop()
            if sim:
                sim.terminate()
                sim.wait(timeout=4)
            if proc and proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=4)
            broker_log.close()
            os.environ.pop('OES_MQTT_BENCH_PASS', None)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mosquitto', default='mosquitto')
    p.add_argument('--passwd', default='mosquitto_passwd')
    args = p.parse_args()
    run(args.mosquitto, args.passwd)

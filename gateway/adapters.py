"""Local transport adapters. The host selects endpoints in its own configuration."""

import glob
import os
import select
import struct
import threading


def serial_ports():
    try:
        from serial.tools import list_ports

        return [
            dict(path=p.device, name=p.description, serial=p.serial_number) for p in list_ports.comports()
        ]
    except ImportError:
        if os.name == "nt":
            raise RuntimeError("Install pyserial on Windows to discover serial ports.")
        paths = sorted(
            set(glob.glob("/dev/serial/by-id/*") + glob.glob("/dev/ttyACM*") + glob.glob("/dev/ttyUSB*"))
        )
        return [dict(path=p, name=os.path.basename(p)) for p in paths]


class SerialPort:
    def __init__(self, path, baud):
        self.fd = None
        self.serial = None
        try:
            import serial
        except ImportError:
            if os.name == "nt":
                raise RuntimeError("The Windows serial adapter requires pyserial.")
            import termios
            import tty

            speed = getattr(termios, "B" + str(baud))
            fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
            try:
                tty.setraw(fd)
                attrs = termios.tcgetattr(fd)
                attrs[4] = attrs[5] = speed
                attrs[2] |= termios.CLOCAL | termios.CREAD
                termios.tcsetattr(fd, termios.TCSANOW, attrs)
            except BaseException:
                os.close(fd)
                raise
            self.fd = fd
        else:
            self.serial = serial.Serial(path, baud, timeout=0.1, write_timeout=0.3)

    def read(self):
        if self.serial is not None:
            return self.serial.read(max(1, min(4096, self.serial.in_waiting)))
        if not select.select([self.fd], [], [], 0.1)[0]:
            return b""
        data = os.read(self.fd, 4096)
        if not data:
            raise OSError("Serial device disconnected.")
        return data

    def write(self, value):
        if self.serial is not None:
            if self.serial.write(value) != len(value):
                raise OSError("Incomplete serial write.")
        elif os.write(self.fd, value) != len(value):
            raise OSError("Incomplete serial write.")

    def close(self):
        if self.serial is not None:
            self.serial.close()
        elif self.fd is not None:
            os.close(self.fd)


class SerialAdapter:
    def __init__(self, config, on_data, on_open, on_close):
        self.cfg = config
        self.callbacks = (on_data, on_open, on_close)
        self.stop = threading.Event()
        self.port = None
        self.write_lock = threading.Lock()

    def run(self):
        data, opened, closed = self.callbacks
        while not self.stop.is_set():
            try:
                self.port = SerialPort(self.cfg["port"], self.cfg.get("baud", 115200))
                opened()
                while not self.stop.is_set():
                    chunk = self.port.read()
                    if chunk:
                        data(chunk)
            except (OSError, ValueError, RuntimeError) as exc:
                closed(str(exc))
            finally:
                with self.write_lock:
                    if self.port:
                        self.port.close()
                    self.port = None
            self.stop.wait(1.0)

    def write(self, payload):
        with self.write_lock:
            if not self.port:
                raise OSError("Serial port is offline.")
            self.port.write(payload)


class MQTTAdapter:
    """One account and exact pair of topics per configured device."""

    def __init__(self, config, on_data, on_open, on_close):
        import paho.mqtt.client as mqtt

        self.cfg = config
        self.stop = threading.Event()
        self.online = False
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="oes-gw-" + config["id"])
        self.prefix = config.get("topic", "oes/" + config["id"])
        user = config["username"]
        self.client.username_pw_set(user, os.environ[config["password_env"]])
        if config.get("ca_file"):
            self.client.tls_set(ca_certs=config["ca_file"])
        self.client.on_connect = self._connected
        self.client.on_subscribe = lambda *args: on_open() if self.online else None
        self.client.on_disconnect = lambda *args: self._lost(on_close)
        self.client.on_message = lambda c, u, m: (
            on_data(m.payload.rstrip(b"\r\n") + b"\n") if not m.retain and len(m.payload) < 512 else None
        )

    def _connected(self, client, userdata, flags, reason, props):
        self.online = reason == 0
        if self.online:
            client.subscribe(self.prefix + "/up", qos=0)

    def _lost(self, closed):
        self.online = False
        closed("MQTT disconnected.")

    def run(self):
        self.client.connect_async(self.cfg["host"], int(self.cfg.get("port", 1883)), 10)
        self.client.loop_start()
        self.stop.wait()
        self.client.disconnect()
        self.client.loop_stop()

    def write(self, payload):
        if not self.online:
            raise OSError("MQTT offline.")
        info = self.client.publish(self.prefix + "/down", payload.strip(), qos=0, retain=False)
        if info.rc:
            raise OSError("MQTT publish failed.")


class FirmataInput:
    """Standard reports and explicitly configured noncritical indicator pins."""

    def __init__(self, pins):
        self.pins = pins
        self.command = None
        self.data = []
        self.sysex = False
        self.last = {}
        self.version = None
        self.version_count = 0

    @staticmethod
    def indicator(pin, value):
        n = pin["pin"]
        if pin["mode"] == "led":
            return bytes([0xF5, n, int(value != 0)])
        if n < 16:
            return bytes([0xE0 | n, value & 127, (value >> 7) & 127])
        return bytes([0xF0, 0x6F, n, value & 127, (value >> 7) & 127, 0xF7])

    def safe(self):
        return b"".join(self.indicator(pin, 0) for pin in self.pins if pin["mode"] in {"led", "led_pwm"})

    def subscribe(self):
        result = bytearray([0xF9])
        for pin in self.pins:
            n = pin["pin"]
            if pin["mode"] in {"led", "led_pwm"}:
                result.extend([0xF4, n, 1 if pin["mode"] == "led" else 3])
                result.extend(self.indicator(pin, 0))
            elif pin["mode"] == "analog":
                result.extend([0xC0 | n, 1])
            else:
                result.extend([0xF4, n, 0x0B if pin.get("pullup") else 0x00, 0xD0 | (n >> 3), 1])
        return bytes(result)

    def feed(self, payload):
        for byte in payload:
            if byte == 0xF0:
                self.sysex = True
            elif byte == 0xF7:
                self.sysex = False
            elif not self.sysex and byte & 0x80:
                self.command, self.data = byte, []
            elif not self.sysex and self.command == 0xF9:
                self.data.append(byte)
                if len(self.data) == 2:
                    self.version = tuple(self.data)
                    self.version_count += 1
                    self.command = None
                    self.data = []
            elif not self.sysex and self.command is not None and self.command & 0xF0 in (0xE0, 0x90):
                self.data.append(byte)
                if len(self.data) != 2:
                    continue
                value = self.data[0] | self.data[1] << 7
                group, channel = self.command & 0xF0, self.command & 15
                self.data = []
                for pin in self.pins:
                    n = pin["pin"]
                    if group == 0xE0 and pin["mode"] == "analog" and n == channel:
                        yield pin["channel"], value
                    if group == 0x90 and pin["mode"] == "digital" and n >> 3 == channel:
                        bit = (value >> (n % 8)) & 1
                        if self.last.get(n) != bit:
                            self.last[n] = bit
                            yield pin["channel"], bit ^ int(pin.get("invert", False))


def osc_scalar(data):
    """Decode a single OSC 1.0 message with one scalar argument."""

    def string_at(pos):
        end = data.index(0, pos)
        return data[pos:end].decode("utf-8"), (end + 4) & ~3

    address, pos = string_at(0)
    tags, pos = string_at(pos)
    if not address.startswith("/") or tags not in (",i", ",f", ",s", ",T", ",F"):
        raise ValueError("Expected one scalar OSC argument.")
    if tags == ",s":
        return address, string_at(pos)[0]
    if tags in (",T", ",F"):
        return address, tags == ",T"
    return address, struct.unpack_from(">i" if tags == ",i" else ">f", data, pos)[0]

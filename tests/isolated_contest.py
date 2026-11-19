"""Exercise both contest roles over private IPv4 addresses without an internet route."""
import fcntl
from pathlib import Path
import socket
import struct
import subprocess
import sys

# Linux network-interface ioctls defined in linux/sockios.h.
SIOCSIFADDR = 0x8916
SIOCGIFFLAGS = 0x8913
SIOCSIFFLAGS = 0x8914
IFF_UP = 0x1
HERE = Path(__file__).resolve()
NAMESPACE = Path("/proc/self/ns/net")


def configure(namespace_before):
    if str(NAMESPACE.readlink()) == namespace_before:
        raise RuntimeError("A separate network namespace is required.")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as control:
        for label, address in [("lo", "127.0.0.1"), ("lo:oeshost", "192.168.76.1"), ("lo:oesguest", "192.168.76.2")]:
            name = label.encode().ljust(16, b"\x00")
            address_request = name + struct.pack("H", socket.AF_INET) + b"\x00\x00" + socket.inet_aton(address) + b"\x00"*16
            fcntl.ioctl(control.fileno(), SIOCSIFADDR, address_request)
            if label == "lo":
                current = fcntl.ioctl(control.fileno(), SIOCGIFFLAGS, name + b"\x00"*24)
                flags = struct.unpack("H", current[16:18])[0] | IFF_UP
                fcntl.ioctl(control.fileno(), SIOCSIFFLAGS, name + struct.pack("H",flags) + b"\x00"*22)
    if any(row.split()[1] == "00000000" for row in Path("/proc/net/route").read_text().splitlines()[1:]):
        raise RuntimeError("Unexpected default route in the isolated network namespace.")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        subprocess.run(["unshare", "-Urn", sys.executable, str(HERE), str(NAMESPACE.readlink())], check=True)
    elif len(sys.argv) == 2:
        configure(sys.argv[1])
        print("Isolated namespace with two private IPv4 aliases on loopback and no default route.", flush=True)
        subprocess.run([sys.executable, str(HERE.with_name("contest_lan.py"))], check=True)
    else:
        raise SystemExit("Run python3 tests/isolated_contest.py")

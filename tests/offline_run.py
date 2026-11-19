#!/usr/bin/env python3
"""Linux QA launcher. Denies creation of IPv4 and IPv6 sockets before starting the app."""

import ctypes
import ctypes.util
import errno
import os
import socket
import sys


class ArgCmp(ctypes.Structure):
    _fields_ = [
        ("arg", ctypes.c_uint),
        ("op", ctypes.c_uint),
        ("datum_a", ctypes.c_uint64),
        ("datum_b", ctypes.c_uint64),
    ]


def main():
    if len(sys.argv) < 2:
        raise SystemExit("Supply a headless executable and its arguments.")
    name = ctypes.util.find_library("seccomp")
    if not name:
        raise SystemExit("libseccomp is required for this Linux-only QA check.")
    lib = ctypes.CDLL(name)
    lib.seccomp_init.argtypes = [ctypes.c_uint32]
    lib.seccomp_init.restype = ctypes.c_void_p
    lib.seccomp_syscall_resolve_name.argtypes = [ctypes.c_char_p]
    lib.seccomp_syscall_resolve_name.restype = ctypes.c_int
    lib.seccomp_rule_add_array.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_int,
        ctypes.c_uint,
        ctypes.POINTER(ArgCmp),
    ]
    lib.seccomp_load.argtypes = [ctypes.c_void_p]
    lib.seccomp_release.argtypes = [ctypes.c_void_p]
    ctx = lib.seccomp_init(0x7FFF0000)
    nr = lib.seccomp_syscall_resolve_name(b"socket")
    for family in (socket.AF_INET, socket.AF_INET6):
        cond = ArgCmp(0, 4, family, 0)
        if lib.seccomp_rule_add_array(ctx, 0x00050000 | errno.ENETDOWN, nr, 1, ctypes.byref(cond)):
            raise RuntimeError("Could not set offline test mode.")
    if lib.seccomp_load(ctx):
        raise RuntimeError("Could not activate offline test mode.")
    lib.seccomp_release(ctx)
    try:
        socket.socket(socket.AF_INET)
    except OSError as exc:
        if exc.errno != errno.ENETDOWN:
            raise
    else:
        raise RuntimeError("Offline guard was inactive.")
    print("Verified IPv4/IPv6 socket creation disabled for this process tree.", flush=True)
    os.execvp(sys.argv[1], sys.argv[1:])


if __name__ == "__main__":
    main()

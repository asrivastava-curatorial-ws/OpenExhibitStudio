#!/usr/bin/env python3
"""Invoke Arduino CLI with explicit arguments and preserve all diagnostics."""
import argparse
import shutil
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BOARDS={"uno":"arduino:avr:uno","nano":"arduino:avr:nano","mega":"arduino:avr:mega","esp32":"esp32:esp32:esp32"}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("action",choices=["list","cores","libraries","install-core","install-library","compile","upload"])
    p.add_argument("--board",choices=BOARDS,default="uno");p.add_argument("--port");p.add_argument("--name")
    p.add_argument("--fqbn",help="Override the board FQBN, including processor options.")
    args=p.parse_args()
    cli=shutil.which("arduino-cli")
    if not cli:p.error("Install Arduino CLI and the board toolchain. See docs/HARDWARE.md.")
    fqbn=args.fqbn or BOARDS[args.board]
    sketch=ROOT/"firmware"/("ExhibitESP32" if args.board=="esp32" else "ExhibitUno")
    if args.action=="list": cmd=["board","list"]
    elif args.action=="cores":cmd=["core","list"]
    elif args.action=="libraries":cmd=["lib","list"]
    elif args.action in ("install-core","install-library"):
        if not args.name:p.error("An explicit package or library --name is required.")
        cmd=["core" if args.action=="install-core" else "lib","install",args.name]
    else:
        cmd=["compile","--fqbn",fqbn,"--libraries",str(ROOT/"firmware/libraries"),str(sketch)]
        if args.action=="upload":
            if not args.port:p.error("Specify the target --port.")
            cmd.extend(["--upload","--port",args.port])
    raise SystemExit(subprocess.call([cli,*cmd]))
if __name__=="__main__":main()

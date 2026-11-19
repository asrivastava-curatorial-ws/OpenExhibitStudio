#!/bin/bash
# Start two X11 test displays in an isolated temporary configuration.
set -eu
root=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
num=${OES_XDISPLAY:-$((120 + RANDOM % 350))}
export DISPLAY="127.0.0.1:$num"
export XAUTHORITY="$tmp/authority"
export LIBGL_ALWAYS_SOFTWARE=1
python3 - "$XAUTHORITY" "$num" <<'PY'
import sys,os,secrets,struct
with open(sys.argv[1],"wb") as f:
    f.write(struct.pack(">H",65535)+b"".join(struct.pack(">H",len(x))+x for x in (b"",sys.argv[2].encode(),b"MIT-MAGIC-COOKIE-1",secrets.token_bytes(16))))
os.chmod(sys.argv[1],0o600)
PY
/usr/lib/xorg/Xorg ":$num" -config "$root/xorg-dummy.conf" -logfile "$tmp/xorg.log" -nolisten unix -nolisten local -listen tcp -auth "$XAUTHORITY" -noreset > "$tmp/screen.log" 2>&1 &
pid=$!
cleanup(){ kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT
for _ in {1..80}; do
  if xrandr --current >/dev/null 2>&1; then
    xrandr --addmode DUMMY1 1024x768
    xrandr --output DUMMY0 --mode 1280x720 --output DUMMY1 --mode 1024x768 --right-of DUMMY0
    xrandr --listactivemonitors
    "$@"
    exit $?
  fi
  sleep .2
done
cat "$tmp/screen.log" >&2
exit 1

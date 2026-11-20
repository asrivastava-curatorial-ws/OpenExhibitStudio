#!/bin/bash
# shellcheck disable=SC2329  # functions run indirectly (through run() or the EXIT trap)
# Run every automated check this machine can run and print a PASS / FAIL / SKIP summary.
#
#   bash tests/run_all.sh [--godot PATH] [--chrome PATH] [--log FILE] [--engine-only]
#
# Needs Godot (bin/godot after setup.sh) and Python 3.10+. Suites whose optional tools are
# missing are reported as SKIP with the reason: Xorg dummy driver + xrandr (display tests),
# NumPy/OpenCV, Chrome or Chromium + Playwright, Node, g++, Mosquitto + paho-mqtt, unshare.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
godot="$root/bin/godot"
chrome=""
log=""
engine_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --godot) godot=$(realpath "$2"); shift 2 ;;
    --chrome) chrome=$2; shift 2 ;;
    --log) log=$(realpath -m "$2"); shift 2 ;;
    --engine-only) engine_only=1; shift ;;
    -h | --help) sed -n 2,8p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -x "$godot" ] || { echo "Godot not found at $godot (run setup.sh or pass --godot)." >&2; exit 2; }

work=$(mktemp -d)
cleanup() { pkill -f "$work/clock" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
mkdir -p "$work/bin"
ln -s "$godot" "$work/bin/godot" # tests that start Godot themselves look it up on PATH
export PATH="$work/bin:$PATH"
export XDG_DATA_HOME="$work/data" # keep test exhibits and settings out of the user profile
log=${log:-$work/run.log}
: > "$log"
cd "$root" || exit 2

results=()
failed=0
note() { printf '%s\n' "$*" | tee -a "$log"; }
run() { # run NAME COMMAND... — PASS when the command exits with status 0
  local name=$1 start status
  shift
  start=$(date +%s)
  printf '\n===== %s\n$ %s\n' "$name" "$*" >> "$log"
  "$@" > "$work/out" 2>&1
  status=$?
  cat "$work/out" >> "$log"
  if [ "$status" -eq 0 ]; then
    results+=("PASS  $name ($(($(date +%s) - start)) s)")
  else
    results+=("FAIL  $name (exit $status) — see log")
    failed=1
  fi
  printf '%-5s %s\n' "$([ "$status" -eq 0 ] && echo PASS || echo FAIL)" "$name"
}
skip() {
  results+=("SKIP  $1 — $2")
  printf 'SKIP  %s — %s\n' "$1" "$2"
  printf '\n===== %s\nSKIPPED: %s\n' "$1" "$2" >> "$log"
}
has_py() { python3 -c "import $1" 2>/dev/null; }

note "OpenExhibit Studio checks — $(date -u '+%Y-%m-%d %H:%M UTC')"
note "Godot $("$godot" --version) · $(python3 --version) · $(uname -srm)"

if [ ! -d app/.godot/imported ]; then
  run "Import project" "$godot" --headless --path app --editor --import
fi

parse_all() {
  local script bad=0
  while IFS= read -r script; do
    if ! "$godot" --headless --path app --check-only --script "res://${script#app/}" > "$work/parse" 2>&1 ||
      grep -q "SCRIPT ERROR\|Parse Error" "$work/parse"; then
      echo "FAILED: $script"
      cat "$work/parse"
      bad=1
    fi
  done < <(find app -name '*.gd' -not -path '*/.godot/*' | sort)
  echo "Parsed $(find app -name '*.gd' -not -path '*/.godot/*' | wc -l) scripts."
  return "$bad"
}
run "GDScript parse check" parse_all
run "Core project and rule suite" "$godot" --headless --path app --script res://qa/check_core.gd

offline=()
if [ "$(uname)" = Linux ] && python3 -c "import ctypes.util,sys; sys.exit(not ctypes.util.find_library('seccomp'))"; then
  offline=(python3 tests/offline_run.py)
fi
run "Integration, headless${offline:+, IPv4/IPv6 sockets denied}" "${offline[@]}" \
  "$godot" --headless --path app --script res://qa/check_integration.gd -- --examples "$root/examples"

clock_check() {
  local publisher status
  OES_CLOCK_KEY=$(python3 -c "import secrets; print(secrets.token_hex(16))")
  export OES_CLOCK_KEY
  cp tools/show_clock.py "$work/clock.py"
  python3 "$work/clock.py" --timeline sequence --duration 15 --repeat --port 18442 &
  publisher=$!
  sleep 0.5
  "$godot" --headless --path app --script res://qa/check_clock.gd
  status=$?
  kill "$publisher" 2> /dev/null
  return "$status"
}
run "LAN timeline clock (Godot follower + Python publisher)" clock_check
run "Studio runs the green-screen booth service" "$godot" --headless --path app \
  --script res://qa/check_greenscreen.gd -- --examples "$root/examples" \
  --project "$root/examples/16-green-screen/project.oes.json"

on_two_heads() { bash tests/dual_display.sh "$@"; }
if [ -x /usr/lib/xorg/Xorg ] && command -v xrandr > /dev/null &&
  ls /usr/lib/xorg/modules/drivers/dummy_drv.so > /dev/null 2>&1; then
  run "Integration on two X11 heads" on_two_heads "$godot" --audio-driver Dummy --path app \
    --script res://qa/check_integration.gd -- --examples "$root/examples"
  run "Every example launches in the Player" on_two_heads "$godot" --audio-driver Dummy --path app \
    --script res://qa/check_examples.gd -- --examples "$root/examples"
  run "UV-mapped mesh rendering" on_two_heads "$godot" --audio-driver Dummy --path app \
    --script res://qa/check_mesh.gd -- --examples "$root/examples"
  if has_py numpy; then
    run "Rendered mapping pixels vs independent model" on_two_heads python3 tests/projector_pixels.py --godot "$godot"
  else
    skip "Rendered mapping pixels" "NumPy not installed"
  fi
  run "Player live-audience board against a real service" on_two_heads python3 tests/contest_native.py
else
  skip "Display tests (5 suites)" "needs Xorg with the dummy driver and xrandr (apt install xserver-xorg-video-dummy x11-xserver-utils)"
fi

if [ "$engine_only" -eq 0 ]; then
  run "Python unit and integration tests" python3 -m unittest discover -s tests -v
  if [ -n "$chrome" ] && has_py playwright; then
    run "Live audience in Chrome (editor, presenter, projector, two phones)" \
      python3 tests/audience_browser.py --chromium "$chrome"
  else
    skip "Live audience in Chrome" "pass --chrome PATH and install playwright"
  fi
  if [ -n "$chrome" ] && has_py playwright && has_py numpy && command -v ffprobe > /dev/null; then
    run "Green-screen booth in Chrome (simulated camera, keying, photo, video)" \
      python3 tests/greenscreen_browser.py --chromium "$chrome"
  else
    skip "Green-screen booth in Chrome" "needs --chrome PATH, playwright, NumPy and FFmpeg"
  fi
  if command -v unshare > /dev/null && unshare -Urn true 2> /dev/null; then
    run "Live audience across an isolated network namespace" python3 tests/isolated_contest.py
  else
    skip "Isolated network namespace" "unprivileged user namespaces unavailable"
  fi
  if has_py numpy && has_py cv2; then
    run "Structured-light calibration at Full HD and UHD" python3 tests/calibration_native_sizes.py
  else
    skip "Structured-light calibration at native sizes" "NumPy and OpenCV not installed"
  fi
  if command -v mosquitto > /dev/null && command -v g++ > /dev/null && has_py paho.mqtt; then
    run "MQTT: Mosquitto + gateway + firmware endpoint" python3 tests/mqtt_broker.py
  else
    skip "MQTT broker exchange" "needs mosquitto, g++ and paho-mqtt"
  fi
  if command -v ruff > /dev/null; then
    run "Python lint (ruff check)" ruff check .
    run "Python formatting (ruff format --check)" ruff format --check .
  else
    skip "Python lint" "ruff not installed"
  fi
fi

note ""
note "Summary"
for line in "${results[@]}"; do note "  $line"; done
note "Full log: $log"
exit $failed

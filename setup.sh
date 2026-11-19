#!/usr/bin/env bash
# OpenExhibit Studio — one-command setup for Ubuntu / Kubuntu / Debian (x86_64 or arm64).
#
#   bash setup.sh                 # download the engine, prepare the app (needs internet once)
#   bash setup.sh --offline       # use files already in ./downloads (copied from a USB stick)
#   bash setup.sh --hardware      # also create .venv with pyserial + paho-mqtt for Arduino/ESP32
#   bash setup.sh --desktop       # also add Studio/Player entries to the KDE/GNOME app menu
#   bash setup.sh --check         # only report what is installed
#
# The official Godot engine archive is checked against a pinned SHA-512 before it is used.
# Everything is installed inside this folder; nothing is written to system directories.
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

GODOT_VERSION="${OPENEXHIBIT_GODOT_VERSION:-4.7.1}"
DOWNLOADS="${OPENEXHIBIT_DOWNLOADS:-$ROOT/downloads}"
OFFLINE=0 HARDWARE=0 DESKTOP=0 CHECK=0
for arg in "$@"; do
  case "$arg" in
    --offline) OFFLINE=1 ;;
    --hardware) HARDWARE=1 ;;
    --desktop) DESKTOP=1 ;;
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "Unsupported CPU $(uname -m). Install Godot $GODOT_VERSION yourself and set OPENEXHIBIT_GODOT." ;;
esac
ZIP="Godot_v${GODOT_VERSION}-stable_linux.${ARCH}.zip"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${ZIP}"

# Official digests copied from the release's SHA512-SUMS.txt. Other versions are checked
# against that file instead, downloaded over HTTPS from the same release.
pinned_sha512() {
  case "$1" in
    Godot_v4.7.1-stable_linux.x86_64.zip) echo 4ccdab7a48eeccbe8819a2fc1f6262f8d72065d98601bcb3743fcbd7ebd39f373758a788ee3293a05ec5b2c48538266c437404312e372225cd2df273945a2de9 ;;
    Godot_v4.7.1-stable_linux.arm64.zip)  echo de64efe4d936ac0403769e078a73d961a9c647cab04168c5fb5a7fe33728e200a67324ed99368eeb27964e205e72a61e48efb63b52d5de34d12dd6a95ca0fc45 ;;
    Godot_v4.6.3-stable_linux.x86_64.zip) echo a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c ;;
    Godot_v4.6.3-stable_linux.arm64.zip)  echo 447381de9ccc68aa02f37e279322289f7ddf88ce9b839ed88a97c73e01cdcda46e026897e5d88722e08491f71b3d74f72dfeb22ec7e3add6fd3e9bfbbdad6751 ;;
    *) echo "" ;;
  esac
}

fetch() { # fetch URL DEST
  local tmp="$2.part"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 20 -o "$tmp" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress --tries=3 -O "$tmp" "$1"
  else
    die "Neither curl nor wget is installed: sudo apt install curl"
  fi
  mv "$tmp" "$2"
}

engine_version() { "$1" --headless --version 2>/dev/null | head -n1 || true; }

usable_engine() { # path -> 0 when it is Godot 4.6 or newer
  [ -x "$1" ] || return 1
  local v; v=$(engine_version "$1")
  case "$v" in 4.[6-9].*|4.[1-9][0-9].*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------- report only
if [ "$CHECK" = 1 ]; then
  if usable_engine "$ROOT/bin/godot"; then ok "Engine: $(engine_version "$ROOT/bin/godot")"; else warn "Engine: not installed (run: bash setup.sh)"; fi
  if [ -d "$ROOT/app/.godot/imported" ]; then ok "App: imported"; else warn "App: not imported yet"; fi
  if command -v python3 >/dev/null; then ok "Python: $(python3 --version)"; else warn "Python 3: missing (live audience and hardware need it)"; fi
  if [ -x "$ROOT/.venv/bin/python" ]; then ok "Hardware Python environment: .venv"; else say "Hardware extras: not installed (optional: bash setup.sh --hardware)"; fi
  exit 0
fi

mkdir -p "$ROOT/bin" "$DOWNLOADS"

# ---------------------------------------------------------------- engine
ENGINE=""
if [ -n "${OPENEXHIBIT_GODOT:-}" ]; then
  usable_engine "$OPENEXHIBIT_GODOT" || die "OPENEXHIBIT_GODOT=$OPENEXHIBIT_GODOT is not Godot 4.6 or newer."
  ENGINE="$OPENEXHIBIT_GODOT"
  ok "Using your engine: $(engine_version "$ENGINE")"
elif usable_engine "$ROOT/bin/godot" && engine_version "$ROOT/bin/godot" | grep -q "^${GODOT_VERSION}\.stable"; then
  ENGINE="$ROOT/bin/godot"
  ok "Engine already installed: $(engine_version "$ENGINE")"
else
  if [ ! -f "$DOWNLOADS/$ZIP" ]; then
    [ "$OFFLINE" = 1 ] && die "Offline mode: copy $ZIP into $DOWNLOADS first (from $URL)."
    say "Downloading Godot $GODOT_VERSION ($ARCH) from github.com/godotengine …"
    fetch "$URL" "$DOWNLOADS/$ZIP"
  fi
  expected=$(pinned_sha512 "$ZIP")
  if [ -z "$expected" ]; then
    sums="$DOWNLOADS/SHA512-SUMS-${GODOT_VERSION}.txt"
    if [ ! -f "$sums" ]; then
      [ "$OFFLINE" = 1 ] && die "Offline mode: also copy SHA512-SUMS.txt of Godot $GODOT_VERSION as $sums"
      fetch "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/SHA512-SUMS.txt" "$sums"
    fi
    expected=$(awk -v f="$ZIP" '$2==f || $2=="*"f {print $1}' "$sums")
    [ -n "$expected" ] || die "No published checksum for $ZIP."
  fi
  actual=$(sha512sum "$DOWNLOADS/$ZIP" | cut -d' ' -f1)
  if [ "$actual" != "$expected" ]; then
    rm -f "$DOWNLOADS/$ZIP"
    die "Checksum mismatch for $ZIP — the download was deleted. Run setup again."
  fi
  ok "SHA-512 verified: $ZIP"
  command -v unzip >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || die "Install unzip: sudo apt install unzip"
  tmpdir=$(mktemp -d)
  if command -v unzip >/dev/null 2>&1; then unzip -q -o "$DOWNLOADS/$ZIP" -d "$tmpdir"
  else python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$DOWNLOADS/$ZIP" "$tmpdir"; fi
  bin=$(find "$tmpdir" -maxdepth 1 -type f -name 'Godot_v*' | head -n1)
  [ -n "$bin" ] || die "Unexpected archive layout in $ZIP"
  install -m 0755 "$bin" "$ROOT/bin/godot"
  rm -rf "$tmpdir"
  ENGINE="$ROOT/bin/godot"
  ok "Installed engine: $(engine_version "$ENGINE")"
fi
engine_version "$ENGINE" > "$ROOT/bin/ENGINE_VERSION"

# ---------------------------------------------------------------- import + packs
say "Preparing the application (first run takes about half a minute) …"
"$ENGINE" --headless --editor --import --path "$ROOT/app" >"$ROOT/bin/import.log" 2>&1 || {
  tail -n 30 "$ROOT/bin/import.log" >&2; die "Godot could not import the app (log: bin/import.log)."; }
[ -d "$ROOT/app/.godot/imported" ] || die "Import produced no cache (log: bin/import.log)."
ok "App imported"

if command -v python3 >/dev/null 2>&1; then
  if python3 "$ROOT/tools/build.py" --godot "$ENGINE" --mode packs --out "$ROOT/bin" >"$ROOT/bin/build.log" 2>&1; then
    ok "Standalone Player and Studio packs built with this engine (bin/*.pck)"
  else
    warn "Pack build failed (log: bin/build.log). Studio still runs from source."
  fi
  pyver=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')
  if python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,10) else 1)'; then ok "Python $pyver — live audience and hardware services available"
  else warn "Python $pyver is older than 3.10; live audience and hardware services need 3.10+"; fi
else
  warn "python3 not found: sudo apt install python3  (needed for live audience and hardware)"
fi

# ---------------------------------------------------------------- optional extras
if [ "$HARDWARE" = 1 ]; then
  say "Creating .venv for Arduino/ESP32 support (pyserial, paho-mqtt) …"
  python3 -m venv "$ROOT/.venv" || die "Install venv support: sudo apt install python3-venv"
  wheels="$DOWNLOADS/wheels"; mkdir -p "$wheels"
  if [ "$OFFLINE" = 1 ]; then
    "$ROOT/.venv/bin/pip" install --no-index --find-links "$wheels" -r "$ROOT/gateway/requirements-optional.txt"
  else
    "$ROOT/.venv/bin/pip" download -q -d "$wheels" -r "$ROOT/gateway/requirements-optional.txt" || true
    "$ROOT/.venv/bin/pip" install -q -r "$ROOT/gateway/requirements-optional.txt"
  fi
  ok "Hardware extras installed (wheels cached in downloads/wheels for offline machines)"
  if ! id -nG "$USER" | grep -qw dialout; then
    warn "To open USB serial boards without sudo run once:  sudo usermod -aG dialout $USER  (then log out and in)"
  fi
fi

if [ "$DESKTOP" = 1 ]; then
  apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$apps"
  for role in studio player; do
    name="OpenExhibit $(tr '[:lower:]' '[:upper:]' <<<"${role:0:1}")${role:1}"
    cat >"$apps/openexhibit-$role.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=Offline interactive exhibits, projection mapping and live audience quizzes
Exec=bash "$ROOT/$role.sh" %f
Icon=$ROOT/app/assets/icon.svg
Terminal=false
Categories=Education;
MimeType=application/x-openexhibit;
EOF
  done
  command -v update-desktop-database >/dev/null && update-desktop-database "$apps" >/dev/null 2>&1 || true
  ok "Menu entries added: OpenExhibit Studio, OpenExhibit Player"
fi

echo
ok "Setup complete.  Start Studio:  bash studio.sh     Play an exhibit:  bash player.sh <project or .oex>"

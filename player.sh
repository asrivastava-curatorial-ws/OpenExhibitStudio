#!/bin/sh
# Play an exhibit.   bash player.sh [project.oes.json | exhibit.oex] [--fullscreen] [--kiosk]
# Works from the full folder (runs setup on first start) or a player-only copy with bin/player.pck.
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
engine="${OPENEXHIBIT_GODOT:-$base/bin/godot}"
if [ ! -x "$engine" ] || { [ -f "$base/app/project.godot" ] && [ ! -d "$base/app/.godot/imported" ]; }; then
  if [ -f "$base/setup.sh" ]; then
    echo "First start: preparing OpenExhibit Player …"
    bash "$base/setup.sh"
    engine="${OPENEXHIBIT_GODOT:-$base/bin/godot}"
  elif ! command -v godot >/dev/null 2>&1; then
    echo "Godot engine missing: copy bin/godot from a Studio installation." >&2; exit 1
  else engine=godot; fi
fi
if [ "$#" -ge 1 ] && [ -f "$1" ]; then
  exhibit=$(realpath -- "$1"); shift
  set -- --project "$exhibit" "$@"
fi
set -- -- --examples "$base/examples" "$@"
if [ -n "${OPENEXHIBIT_AUDIO_DRIVER:-}" ]; then set -- --audio-driver "$OPENEXHIBIT_AUDIO_DRIVER" "$@"; fi
if [ -f "$base/bin/player.pck" ] && [ ! -f "$base/app/project.godot" ]; then
  exec "$engine" --main-pack "$base/bin/player.pck" "$@"
fi
exec "$engine" --path "$base/app" res://player/player.tscn "$@"

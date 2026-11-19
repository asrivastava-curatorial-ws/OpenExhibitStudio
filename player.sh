#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
engine="${OPENEXHIBIT_GODOT:-$base/bin/godot}"
if [ ! -x "$engine" ]; then engine=godot; fi
if [ "$#" -ge 1 ] && [ -f "$1" ]; then
  exhibit=$(realpath -- "$1")
  shift
  set -- --project "$exhibit" "$@"
fi
set -- -- --examples "$base/examples" "$@"
if [ -n "${OPENEXHIBIT_AUDIO_DRIVER:-}" ]; then
  set -- --audio-driver "$OPENEXHIBIT_AUDIO_DRIVER" "$@"
fi
if [ -f "$base/bin/player.pck" ]; then
  exec "$engine" --main-pack "$base/bin/player.pck" "$@"
fi
exec "$engine" --path "$base/app" res://player/player.tscn "$@"

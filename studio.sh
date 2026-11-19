#!/bin/sh
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
engine="${OPENEXHIBIT_GODOT:-$base/bin/godot}"
if [ ! -x "$engine" ]; then engine=godot; fi
set -- -- --examples "$base/examples" "$@"
if [ -n "${OPENEXHIBIT_AUDIO_DRIVER:-}" ]; then
  set -- --audio-driver "$OPENEXHIBIT_AUDIO_DRIVER" "$@"
fi
if [ -f "$base/bin/studio.pck" ]; then
  exec "$engine" --main-pack "$base/bin/studio.pck" "$@"
fi
exec "$engine" --path "$base/app" "$@"

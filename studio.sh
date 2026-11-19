#!/bin/sh
# Start OpenExhibit Studio.   bash studio.sh [project.oes.json | exhibit.oex]
# The first start runs setup.sh, which downloads and verifies the Godot engine once.
set -eu
base=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
engine="${OPENEXHIBIT_GODOT:-$base/bin/godot}"
if [ ! -x "$engine" ] || { [ -f "$base/app/project.godot" ] && [ ! -d "$base/app/.godot/imported" ]; }; then
  echo "First start: preparing OpenExhibit Studio …"
  bash "$base/setup.sh"
  engine="${OPENEXHIBIT_GODOT:-$base/bin/godot}"
fi
if [ "$#" -ge 1 ] && [ -f "$1" ]; then
  project=$(realpath -- "$1"); shift
  set -- --project "$project" "$@"
fi
set -- -- --examples "$base/examples" "$@"
if [ -n "${OPENEXHIBIT_AUDIO_DRIVER:-}" ]; then set -- --audio-driver "$OPENEXHIBIT_AUDIO_DRIVER" "$@"; fi
if [ -f "$base/app/project.godot" ]; then exec "$engine" --path "$base/app" "$@"; fi
exec "$engine" --main-pack "$base/bin/studio.pck" "$@"

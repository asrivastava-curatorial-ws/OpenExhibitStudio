#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="${1:-$root/dist}"
mkdir -p "$out"
tempdir=$(mktemp -d)
trap 'rm -rf -- "$tempdir"' EXIT HUP INT TERM
appdir="$tempdir/usr/lib/openexhibit"
mkdir -p "$appdir/bin" "$tempdir/DEBIAN" "$tempdir/usr/bin" "$tempdir/usr/share/applications" "$tempdir/usr/share/icons/hicolor/scalable/apps"
for f in bin/godot bin/studio.pck bin/player.pck; do test -f "$root/$f" || { echo "Run python3 tools/build.py --mode portable first"; exit 1; }; done
cp "$root/bin/godot" "$root/bin/studio.pck" "$root/bin/player.pck" "$appdir/bin/"
cp -R "$root/examples" "$root/docs" "$root/licenses" "$root/gateway" "$root/firmware" "$root/tools" "$appdir/"
find "$appdir" -type d -name __pycache__ -prune -exec rm -r {} +
mkdir -p "$appdir/tests"
cp -R "$root/tests/results" "$appdir/tests/"
mkdir -p "$appdir/packaging" "$tempdir/usr/lib/systemd/user"
cp "$root/packaging/openexhibit-player.service" "$appdir/packaging/"
cp "$root/packaging/openexhibit-player.service" "$tempdir/usr/lib/systemd/user/"
cp "$root/README.md" "$root/LICENSE" "$root/studio.sh" "$root/player.sh" "$appdir/"
chmod 755 "$appdir/bin/godot" "$appdir/studio.sh" "$appdir/player.sh"
for role in studio player; do
  cat > "$tempdir/usr/bin/openexhibit-$role" <<EOF
#!/bin/sh
exec /usr/lib/openexhibit/$role.sh "\$@"
EOF
  chmod 755 "$tempdir/usr/bin/openexhibit-$role"
  cat > "$tempdir/usr/share/applications/openexhibit-$role.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OpenExhibit $role
Exec=openexhibit-$role
Icon=openexhibit
Categories=Education;AudioVideo;
Terminal=false
EOF
done
cp "$root/app/assets/icon.svg" "$tempdir/usr/share/icons/hicolor/scalable/apps/openexhibit.svg"
cat > "$tempdir/DEBIAN/control" <<'EOF'
Package: openexhibit-studio
Version: 0.2.0
Section: education
Priority: optional
Architecture: amd64
Maintainer: OpenExhibit Studio contributors <maintainers@openexhibit.invalid>
Depends: python3 (>= 3.10), libc6, libstdc++6, libx11-6, libxcursor1, libxi6, libxinerama1, libxrandr2, libgl1, libasound2 | libasound2t64
Recommends: libglx-mesa0, libgl1-mesa-dri
Suggests: python3-opencv, python3-pil, python3-tk, ffmpeg, poppler-utils, mosquitto
Description: Offline exhibit authoring and playback
 Native scene editor, calibrated outputs, hardware gateway live contests and fourteen examples.
EOF
dpkg-deb --root-owner-group -Zxz -z4 --build "$tempdir" "$out/OpenExhibit-Studio-0.2.0-linux-amd64.deb"

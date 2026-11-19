# Build and test

Reference engine: **Godot 4.7.1 stable** (official build, OpenGL Compatibility renderer). Godot
4.6.3 is also tested. Python 3.10 or newer runs the services and most tests.

## Prepare a development checkout

```sh
bash setup.sh                     # engine → bin/godot, import app/, build bin/*.pck
export PATH="$PWD/bin:$PATH"      # so the commands below find `godot`
```

Packs only (for example after changing GDScript, before making a player-only copy):

```sh
python3 tools/build.py --godot bin/godot --mode packs --out bin
python3 tools/build.py --godot bin/godot --platform windows --mode packs --out bin/windows
```

Native single-file executables need the matching official export templates
(`Godot_v4.7.1-stable_export_templates.tpz`) installed first:
`python3 tools/build.py --mode native --platform linux --out dist/linux`.

## Test suites

One command runs every suite this computer can run and prints PASS, FAIL or SKIP (with the
missing tool) for each:

```sh
bash tests/run_all.sh --chrome /usr/bin/google-chrome --log run.log
```

`--godot PATH` tests another engine build; `--engine-only` runs just the Godot suites. The
individual commands are:

| Command | What it checks | Needs |
| --- | --- | --- |
| `godot --headless --path app --script res://qa/check_core.gd` | Project model, saving, packages, rules, recovery | Godot |
| `godot --headless --path app --script res://qa/check_integration.gd -- --examples "$PWD/examples"` | All 15 examples round-trip; Studio editing, undo, workspaces; mapping maths; session behaviour | Godot |
| `bash tests/dual_display.sh godot --audio-driver Dummy --path app --script res://qa/check_integration.gd -- --examples "$PWD/examples"` | The same plus real windows on two X11 heads | Xorg dummy driver, xrandr |
| `bash tests/dual_display.sh godot --audio-driver Dummy --path app --script res://qa/check_examples.gd -- --examples "$PWD/examples"` | Every example launches in the Player | as above |
| `bash tests/dual_display.sh python3 tests/projector_pixels.py` | Rendered warp/blend/gamma/sphere/cylinder/dome pixels against an independent implementation | as above, NumPy |
| `bash tests/dual_display.sh python3 tests/contest_native.py` | Player's live-audience board against a real service | as above |
| `python3 -m unittest discover -s tests` | Gateway, protocols, calibration maths, deployment, live-audience engine, firmware generator (C++ compile) | NumPy, OpenCV, jsonschema, Node, g++ for some tests |
| `python3 tests/audience_browser.py --chromium /usr/bin/google-chrome` | Editor, presenter, projector and two phones through every slide type in real Chrome | Playwright, Chrome/Chromium |
| `python3 tests/calibration_native_sizes.py` | Structured-light solve at Full HD and UHD | NumPy, OpenCV |
| `python3 tests/mqtt_broker.py --mosquitto … --passwd …` | Authenticated MQTT exchange with the firmware endpoint | Mosquitto |
| `python3 tools/soak.py --seconds 28800 --report eight-hours.json` | Memory/descriptor growth over a long run | Godot |

On Ubuntu the display harness needs `sudo apt install xserver-xorg-video-dummy x11-xserver-utils`.
Run Godot suites with a throw-away data folder (`XDG_DATA_HOME=$(mktemp -d)`) to keep test files
out of your user profile.

## Formatting and lint

```sh
pip install "gdtoolkit==4.*" ruff
ruff format . && ruff check .
npx prettier@3 --write "tools/contest/web/*.{js,css,html}" "firmware/blockly/*.{js,css,html}"
gdformat --line-length 120 app/path/to/file.gd && python3 tools/dev/fix_lambdas.py app/path/to/file.gd
```

gdformat moves multi-line lambda arguments onto their own lines, which Godot cannot parse;
`tools/dev/fix_lambdas.py` re-attaches them. Check every changed script with
`godot --headless --path app --check-only --script res://path/to/file.gd`.

## Firmware

```sh
arduino-cli core install arduino:avr@1.8.6
arduino-cli core install esp32:esp32@3.1.3 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli lib install PubSubClient@2.8 ESP32Servo@3.0.6
python3 tools/firmware.py compile --board uno
python3 tools/firmware.py upload --board uno --port /dev/ttyACM0
```

Compilation works offline once the cores and libraries are installed.

## Packages

| Command | Output (in `dist/`) | Needs on the build machine |
| --- | --- | --- |
| `python3 packaging/build_appimage.py` | `OpenExhibit-Studio-0.3.0-x86_64.AppImage` | squashfs-tools |
| `python3 packaging/build_windows_installer.py` | `OpenExhibit-Studio-0.3.0-Windows-x64-Setup.exe` | NSIS 3 (`sudo apt install nsis`); runs on Linux or Windows |
| `python3 tools/release.py` | `OpenExhibit-Studio-0.3.0-source.zip` | — |
| `bash packaging/build-deb.sh dist` | Debian package (needs `bin/` from `setup.sh`; not rebuilt for 0.3.0) | dpkg-deb |

Both package builders export the packs with the pinned Godot 4.7.1 Linux engine and take every
third-party file from `packaging/runtimes.py`, which downloads it once into `downloads/` and checks
its pinned SHA-512 or SHA-256 before use: the Godot engines, CPython 3.12.13 for Windows
(python-build-standalone) and the pyserial and paho-mqtt wheels. Run
`python3 packaging/runtimes.py` on a connected machine, then build anywhere with `--offline`.
The AppImage runtime is published only as a rolling build, so it is not pinned; the builder prints
its SHA-256, and `--runtime FILE` uses a copy you keep. `--appdir DIR` / `--stage DIR` keep the
assembled files for inspection.

The AppImage is assembled with `mksquashfs` and the runtime directly, so no downloaded build tool
runs. Check a build on an X11 display with
`python3 tests/window_smoke.py "Orbital atlas" -- ./OpenExhibit-Studio-0.3.0-x86_64.AppImage`.

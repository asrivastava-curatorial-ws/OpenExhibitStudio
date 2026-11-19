# Build and test 0.2.0

The native engine reference is Godot 4.6.3 standard, using the OpenGL Compatibility renderer. From the repository root on Ubuntu run the commands below. `--offline` requires the two original pinned Windows archives in the named cache. Omit it once on the build computer to populate that cache.

```sh
python3 tools/build.py --mode portable
python3 tools/build.py --platform windows --out bin/windows
python3 tools/windows_runtime.py --cache ../offline-cache --offline
python3 tools/release.py --out dist/OpenExhibit-Studio-0.2.0.zip
python3 tools/release.py --source --out dist/OpenExhibit-Studio-0.2.0-source.zip
bash packaging/build-deb.sh
python3 packaging/build_windows_installer.py
```

The Windows installer build needs NSIS 3 with its Unicode stubs. Use `--makensis PATH` if its compiler is outside PATH. `tools/release.py --windows` builds a Windows-only portable distribution when needed. The source archive includes the independently built player and studio packs for each OS. It omits runtime executables. Builds pin engine and embedded interpreter versions and archive checksums. Tool and file timestamps can change final archive hashes between builds.

## Reproduce acceptance checks

```sh
godot --headless --path app --editor --import
godot --headless --path app --script res://qa/check_core.gd
python3 tests/offline_run.py godot --headless --path app --script res://qa/check_integration.gd -- --examples "$PWD/examples"
bash tests/dual_display.sh godot --audio-driver Dummy --path app --script res://qa/check_integration.gd
bash tests/dual_display.sh godot --audio-driver Dummy --path app --script res://qa/check_examples.gd
python3 tests/calibration_native_sizes.py
bash tests/dual_display.sh python3 tests/projector_pixels.py
bash tests/dual_display.sh python3 tests/contest_native.py
python3 -m unittest discover -s tests -v
python3 tests/contest_browser.py --chromium /path/to/chromium
python3 tests/isolated_contest.py
python3 tests/mqtt_broker.py --mosquitto /path/to/mosquitto --passwd /path/to/mosquitto_passwd
python3 tools/soak.py --seconds 172800 --display --report field-48-hours.json
```

Install NumPy, Pillow, OpenCV, jsonschema and the optional gateway packages for the full Python suite. PDF tests additionally use Poppler and ReportLab. The browser test needs Playwright, Chromium and OpenCV for actual QR decoding. Gateway protocol tests use a C++17 compiler. The dual-display harness needs Xorg, the dummy video driver, Mesa software OpenGL and xrandr. Install hardware-specific wheels once on a connected machine, then use a local wheelhouse with `pip install --no-index --find-links`. On Windows, build the native data packs with the same Godot version. Use the native Windows installer, or extract the full ZIP and run Studio.cmd.

## Compile the four supplied board targets

These versions built the release sketches under Arduino CLI 1.3.1. Prepare the cores and libraries once on a computer with internet access. The compile commands then run offline, and no board is needed to compile.

```sh
arduino-cli core install arduino:avr@1.8.6
arduino-cli core install esp32:esp32@3.1.3 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli lib install PubSubClient@2.8 ESP32Servo@3.0.6
for board in uno nano mega; do
  arduino-cli compile --fqbn "arduino:avr:$board" --libraries firmware/libraries firmware/ExhibitUno || exit 1
done
arduino-cli compile --fqbn esp32:esp32:esp32 --libraries firmware/libraries firmware/ExhibitESP32
```

**Isolated quiz test.** The Linux runner creates a disposable user/network namespace and adds two private IPv4 aliases. It tests visitor TCP and the private operator boundary without a default route. On a Linux test host that allows nested net namespaces and veth creation, use `unshare -Urnm python3 tests/contest_lan.py --isolated` to repeat the exercise across a virtual Ethernet pair.

## Additional build notes

## Prerequisites

The delivered Linux archive includes Godot, compiled data packs, all example assets and fonts. The operating system must supply the standard graphics, windowing and audio libraries. The verified reference engine is **4.6.3.stable.official.7d41c59c4**, standard edition. The default rendering method is OpenGL Compatibility.

Source builds require Godot 4.6.3 and Python 3.10 or newer. The core needs no Python packages. Qt, Electron, Node, Docker, Rust, internet services and AI models are optional or unused. Optional Python/Node libraries apply only to the tools that select them. Check **docs/DEPENDENCIES.md** before redistributing optional software.

## Source and pack builds

From the repository root on Linux:

```sh
godot --headless --editor --path app --import
godot --path app -- --examples "$(pwd)/examples"
python3 tools/build.py --mode portable --out bin
bash studio.sh
bash player.sh examples/06-digital-book/project.oes.json
bash packaging/build-deb.sh dist
```

In Windows PowerShell with the standard executable available, set OPENEXHIBIT_GODOT to the extracted file and run:

```powershell
$env:OPENEXHIBIT_GODOT = 'C:\Tools\Godot\Godot_v4.6.3-stable_win64.exe'
py -3 tools\build.py --godot $env:OPENEXHIBIT_GODOT --platform windows --mode packs --out bin
.\Setup-Windows.cmd -Engine $env:OPENEXHIBIT_GODOT
```

To create native template-based Linux or Windows executables, install the official matching **4.6.3 standard export templates**, then run **python3 tools/build.py --mode native --platform linux --out dist/linux** or **--platform windows --out dist/windows**. The builder stages only the appropriate modules for each role before import and export. Copy the desired examples, licences and operator guides beside the executable. No export templates were installed in the reference build environment. The delivered compiled releases therefore use data packs and a platform engine. [Godot export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)

Save the official engine ZIP, templates and any optional trusted dependencies on removable storage for subsequent offline installs. Keep tool versions fixed when reproducing results. Godot import IDs, archive timestamps and compiler versions can affect binary hashes. The source build steps are repeatable; this release does not assert bit-for-bit reproducibility across systems.

## Prepare media and books

```sh
ffmpeg -i source.mp4 -c:v libtheora -q:v 7 -c:a libvorbis exhibit.ogv
python3 tools/import_pdf.py original-book.pdf new-book-folder
python3 tools/render.py examples/11-mixed/project.oes.json out_2 feed.avi --fps 24 --frames 240
python3 tools/render.py examples/03-earth/project.oes.json out_1 frame.png --fps 24 --frames 48
```

The render utility requires a graphics display and writes frames at the selected output’s pixel size. AVI encoding uses an installed FFmpeg executable with FFV1. The exported image sequence and AVI contain the visual feed. They have no audio track. A later mux operation can add a separate audio master. Poppler’s pdftoppm is only needed to import PDFs.

Existing sample masters are included. To regenerate the project JSON and vector art, run **python3 tools/make_examples.py**. The optional media_masters.py script rebuilds both Theora clips and the Earth texture if supplied with WGS84 polygon GeoJSON. Original geography provenance is in **licenses/**. The preset catalogue can be regenerated with **godot --headless --path app --script res://qa/preset_catalog.gd -- /absolute/path/to/tools/data/layouts.json**.

## Test commands

```sh
godot --headless --editor --path app --import
godot --headless --path app --script res://qa/check_core.gd
godot --headless --path app --script res://qa/check_integration.gd -- --examples "$(pwd)/examples"
godot --audio-driver Dummy --path app --script res://qa/check_integration.gd -- --examples "$(pwd)/examples"
python3 -m unittest discover -s tests -v
g++ -std=c++17 -Ifirmware/libraries/OpenExhibitProtocol/src tests/endpoint.cpp -o /tmp/oes-protocol-check
/tmp/oes-protocol-check
python3 tools/soak.py --seconds 28800 --report eight-hours.json
```

Use a separate operating-system test account or point XDG_DATA_HOME to an empty temporary directory. The native integration suite creates temporary test projects under the OpenExhibit application-data checks folder. Install jsonschema for the schema test. POSIX pseudo-terminal tests use a C++17 compiler. The eight-hour soak command supports --display and checks memory and descriptor growth against its warmup readings. On Windows install psutil for resource readings. A single soak is an observation over that run length, not a general leak guarantee.

For a silent Linux installation, set **OPENEXHIBIT_AUDIO_DRIVER=Dummy** before running either launcher. To isolate the headless suite from IP networking on Linux, prefix its command with **python3 tests/offline_run.py**.

Build the Windows-target packs with **--platform windows --mode packs --out bin/windows**. Then **python3 tools/release.py** packages the complete source and both portable desktop runtimes. Use **--windows --out dist/OpenExhibit-Windows.zip** for the smaller Windows setup distribution. ZIP releases include a SHA256SUMS.txt inventory.

With a running X11 display and xwininfo installed, **OPENEXHIBIT_AUDIO_DRIVER=Dummy python3 tests/package_smoke.py /absolute/path/to/release** checks the actual Linux launchers and a player-only directory. A .deb can first be inspected with dpkg-deb --info and extracted with dpkg-deb --extract. A payload launch does not substitute for a fresh operating-system installation.

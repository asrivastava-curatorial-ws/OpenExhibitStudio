# Dependencies, alternatives and licensing

| Dependency | Decision and distribution |
| --- | --- |
| Godot 4.7.1 (4.6.3 also supported) | Native authoring and runtime engine, OpenGL Compatibility, text shaping, native controls, GLB import, Theora, audio, textures and native output windows. Downloaded by setup.sh / Setup-Windows.cmd from the official GitHub release and checked against a pinned SHA-512; MIT plus its third-party notices. Complete engine notices are in licenses/Godot-and-third-parties.txt. [Godot licensing](https://godotengine.org/license/) |
| JetBrains Mono Regular | Bundled offline WOFF2 from the official Godot editor font resource. Preserve its SIL Open Font License and attribution when redistributing. See licenses/JetBrains-Mono-OFL.txt. [JetBrains Mono](https://www.jetbrains.com/lp/mono/) |
| Noto Sans Bengali / Devanagari | Bundled regular fonts for Indic fallback and shaping. See licenses/Noto.txt for copyright and OFL terms. [Noto fonts](https://notofonts.github.io/) |
| Natural Earth | Earth bitmap uses public-domain geographic data from QGIS’s processed world_map.gpkg. Only land shapes and a generated graticule are drawn. See licenses/Natural-Earth-QGIS.md. [Natural Earth terms](https://www.naturalearthdata.com/about/terms-of-use/) |
| Python standard library | Hardware service, file updates, clock service, CLI integration and test harness. The available runtime allowed direct tests of serial I/O, local sockets, SQLite and recovery. This release substitutes Python for the preferred Rust service. Ubuntu supplies Python. The complete Windows distribution includes the embedded interpreter for the quiz. Desktop Python with optional packages is installed separately for camera and gateway tools. [Python licence](https://docs.python.org/3/license.html) |
| pyserial / Paho MQTT | External optional dependencies for Windows serial and MQTT. Versions are pinned in gateway/requirements-optional.txt. PySerial uses BSD terms. Paho uses EPL/EDL terms. [pyserial](https://github.com/pyserial/pyserial) · [Paho](https://github.com/eclipse-paho/paho.mqtt.python) |
| Eclipse Mosquitto | External MQTT broker for an isolated LAN. Use accounts and per-device ACLs. EPL/EDL. No broker binary bundled. [Mosquitto](https://mosquitto.org/) |
| ConfigurableFirmata | The host adapter accepts digital and analog input reports. ConfigurableFirmata 2.5 or newer can also receive armed, bounded digital or PWM indicator commands on configured pins. Preserve the chosen release’s licence and bundled library notices when distributing firmware. [Upstream repository](https://github.com/firmata/ConfigurableFirmata) |
| Arduino CLI, board cores, PubSubClient, ESP32Servo | Installed separately. The CLI and imported firmware libraries retain their individual licences. Pin the core, toolchain and library versions validated on the site bench. No upstream firmware code is copied into the sample sketches. [Arduino CLI](https://github.com/arduino/arduino-cli) · [PubSubClient](https://github.com/knolleary/pubsubclient) · [ESP32Servo](https://github.com/madhephaestus/ESP32Servo) |
| Blockly 12.5.1 | Vendored in firmware/blockly/vendor (blockly_compressed.js, blocks_compressed.js, msg/en.js, media) so the firmware block editor works offline. Apache-2.0, see licenses/Blockly-Apache-2.0.txt. Block definitions and the sketch generator are original source. [Blockly](https://github.com/RaspberryPiFoundation/blockly) |
| OpenCV / NumPy | External camera, ArUco and planar calibration dependencies. Modern OpenCV releases use Apache 2.0. NumPy and binary distributions have additional notices. [OpenCV licensing](https://opencv.org/license/) · [OpenCV marker detection](https://docs.opencv.org/4.x/d5/dae/tutorial_aruco_detection.html) |
| FFmpeg / Poppler | Optional external command-line programs for preprocessing and export. FFmpeg obligations vary with build configuration. Poppler uses GPL terms. No executables from these projects are bundled. Encoded sample clips are original wave simulations. [FFmpeg legal](https://ffmpeg.org/legal.html) · [Poppler](https://poppler.freedesktop.org/) |
| Splash | Evaluated for camera calibration, blending and UV-mapped object projection. The application is GPLv3. This release implements its own documented calibration JSON and uses Godot for projector views. There is no tested Splash importer/exporter or bundled Splash code. [Splash documentation](https://sat-mtl.gitlab.io/documentation/splash/en/) |
| Qt / GStreamer | Considered as alternatives for desktop UI and wider media decoding. A single Godot scene renderer keeps editor and player behaviour consistent. On-demand offline conversion to Theora limits runtime dependencies. Native arbitrary-codec playback remains open. [Godot runtime file loading](https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html) |
| Optional local AI, speech executables and models | Installed by the operator. The app sends explicitly requested local work to already running services. Check each tool, node pack, voice and model’s licence before redistribution. |

Original project code, original firmware, example graphics and generated simulation movies use the MIT licence in the root. Redistribution of the full archive must retain the applicable notices for each shipped item. A software licence does not grant rights to unrelated museum photographs, narration, models or imported media.


## Components added in 0.2

| Component | Distribution and terms |
| --- | --- |
| CPython 3.14.10 Windows embeddable x64 (0.2 only) | 0.3 setup uses an installed Python (winget offered) instead. The 0.2 Windows and complete archives carried the official application-local interpreter and its bundled dependency notices. Preserve bin/windows/python/LICENSE.txt or bin/python/LICENSE.txt. A second copy is kept in licenses/CPython-Windows.txt. The build script pins the downloaded archive digest. [Python Windows distribution](https://docs.python.org/3/using/windows.html) |
| QR encoder | The independent MIT-licensed Python QR encoder by Kazuhiko Arase, Sam Curren and Open End AB is included from the ReportLab distribution. Notices remain in tools/contest/vendor/qrencoder.py, licenses/QR-encoder-MIT.txt and licenses/ReportLab.txt. |
| NumPy, Pillow and OpenCV | Optional calibration and image processing. Install from the operating system or transfer wheels for the chosen platform. NumPy is BSD-3-Clause, Pillow is HPND and modern OpenCV is Apache-2.0. Binary packages may include additional third-party notices. |
| PyModbus, Mido, RtMidi and hidapi | Optional field transports installed separately. PyModbus uses BSD-3-Clause and Mido and python-rtmidi use MIT. Consult the selected hidapi binding and native backend distribution for its licence choices. |
| NSIS 3 | Installer build tool. The generated installer provides the OpenExhibit and bundled component notices. Retain the notices packaged with NSIS if redistributing its compiler or plugins. [NSIS licence](https://nsis.sourceforge.io/License) |
| Open-source verification tools | The release lab used Chromium, Playwright, Mosquitto and a clean Ubuntu userland. These test tools and the operating-system image are provisioned separately. |

The quiz implementation contains original code and a locally served user interface. All AhaSlides product names are used to identify design references.


## Components added in 0.3

| Component | Distribution and terms |
| --- | --- |
| wordcloud2.js 1.2.3 | Vendored in tools/contest/web/vendor; MIT, licence file alongside. Word-cloud layout on the projector. |
| canvas-confetti 1.9.4 | Vendored; ISC, licence file alongside. Celebration effects. |
| SortableJS 1.15.7 | Vendored; MIT, licence file alongside. Touch reordering on phones and in the slide editor. |
| gdtoolkit, ruff, Prettier | Development-only formatters/linters used to format the source; not shipped. |

See [REUSE.md](REUSE.md) for the open-source projects evaluated (Claper, ClassQuiz, Rahoot, Fuiz, Splash, Chataigne and others) and why each was bundled, integrated by protocol, or left out.

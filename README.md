# OpenExhibit Studio 0.3.0

Free, offline software for building museum and science-centre exhibits: touchscreen kiosks,
projection-mapped installations, digital and physical flipbooks, Arduino/ESP32 interactives, and
AhaSlides-style live audience sessions (polls, quizzes, word clouds, Q&A) on visitors' phones.

Everything runs on your own computers. There are no accounts, no cloud services and no
telemetry. Studio authors exhibits; the standalone Player runs them on exhibit computers.

## Install and start

**Ubuntu / Kubuntu / Debian (x86-64; ARM64 is supported by setup but untested)** — from the extracted folder:

```sh
bash setup.sh          # once: downloads Godot 4.7.1 from GitHub, checks its SHA-512, prepares the app
bash studio.sh         # start Studio (runs setup by itself the first time)
bash player.sh examples/06-digital-book/project.oes.json
```

Optional: `bash setup.sh --hardware` adds pyserial and paho-mqtt for USB and Wi-Fi boards, and
`bash setup.sh --desktop` adds Studio and Player to the application menu.

**Windows 10/11** — double-click `Setup-Windows.cmd` once, then `Studio.cmd`. Setup downloads the
engine with the same checksum check and offers to install Python 3.12 with winget if it is missing
(Python is needed only for live audience sessions and USB hardware). Add `-Shortcuts` for
Start-menu and desktop shortcuts.

**Offline computers** — on a connected machine, fetch the engine into `downloads/`:

```sh
mkdir -p downloads && curl -L -o downloads/Godot_v4.7.1-stable_linux.x86_64.zip \
  https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip
# Windows: …/4.7.1-stable/Godot_v4.7.1-stable_win64.exe.zip
```

Copy the folder to the offline computer and run `bash setup.sh --offline` (or
`Setup-Windows.cmd -Offline`). Godot 4.6.3 also works: set `OPENEXHIBIT_GODOT_VERSION=4.6.3`.

## A five-minute tour

1. Studio opens with a **start screen**: pick *Touchscreen kiosk* (or any template), or a blank
   exhibit. Templates open as read-only examples — **File → Save as** into an empty folder to
   make your own copy.
2. **Screens**: click any layer and edit it in the Inspector; changes apply as you type. Select a
   button and choose what happens **When pressed** — go to a scene, set a variable, play a
   timeline, switch a device output, turn a page.
3. **Interactions** builds richer rules that read as sentences:
   *When button “Mars” is pressed → set planet to “Mars”; go to scene “Mars facts”.*
4. Press **F5 (Try it)** to use the exhibit as a visitor; F5 again returns to editing.
5. **Publish → Export .oex package**, then on the exhibit computer:
   `bash player.sh exhibit.oex --kiosk` (Windows: `Player.cmd exhibit.oex --kiosk`).

## Live audience sessions (AhaSlides-style)

Open the *Live audience talk* template, go to **Live audience**, choose your Wi-Fi or LAN under
**Who can join**, and press **Start session and present**. The presenter console opens in the
browser; press **F** there for the projector window. Visitors scan the QR code and answer on their
phones. Slide types: content, pick one / several, type an answer, number, correct order, match,
categorise, poll, word cloud, rating scale, ranking, open-ended ideas with voting, audience Q&A
and a spinner wheel — with leaderboards, team play, emoji reactions and CSV exports.
→ [Live audience guide](docs/LIVE-AUDIENCE.md)

## Hardware

**Hardware → Try it without hardware** gives virtual sliders and lamps for every channel. To use a
real board, pick a board profile and its USB port and press **Start hardware service**; Studio
runs the local gateway and connects to it. Outputs never switch on until you **Arm** them.
The firmware block editor (Blockly, works offline) writes Arduino sketches for you.
→ [Hardware guide](docs/HARDWARE.md)

## Documentation

| I want to… | Read |
| --- | --- |
| Learn Studio step by step | [User manual](docs/USER-MANUAL.md) |
| Run polls, quizzes and Q&A | [Live audience](docs/LIVE-AUDIENCE.md) |
| Set up projectors, a dome, a sphere or a book | [Installation and mapping](docs/MAPPING.md) · [Calibration](docs/CALIBRATION.md) |
| Connect Arduino, ESP32, OSC, DMX, Modbus | [Hardware](docs/HARDWARE.md) · [Field devices](docs/FIELD-IO.md) · [Protocol](docs/PROTOCOL.md) |
| Run exhibits unattended | [Deployment](docs/DEPLOYMENT.md) |
| Know exactly what works and what does not | [Capabilities and limits](docs/CAPABILITIES.md) · [Test results](docs/TEST-RESULTS.md) |
| See what changed from 0.2.0 | [Changelog](CHANGELOG.md) |
| Understand which open-source projects were reused or evaluated | [Reuse](docs/REUSE.md) · [Dependencies and licences](docs/DEPENDENCIES.md) |
| Build, test or extend it | [Build](docs/BUILD.md) · [Architecture](docs/ARCHITECTURE.md) · [File format](docs/FORMAT.md) · [Plugins](docs/PLUGINS.md) |

## Repository layout

| Folder | Contents |
| --- | --- |
| `app/` | Godot project. `core/` is shared by Studio and Player (project model, session engine, renderer, mapping); `studio/` is the authoring shell; `player/` the runtime; `qa/` native test suites. |
| `tools/` | Python services and utilities: `quiz.py` + `contest/` (live audience), calibration, PDF import, packaging, deployment. |
| `gateway/` | Hardware service: serial, Firmata, MQTT, OSC, Art-Net/sACN, Modbus, MIDI, HID adapters and board profiles. |
| `firmware/` | Arduino and ESP32 sketches, the shared protocol library and the offline block editor. |
| `examples/` | Fifteen ready-to-run exhibits with their own assets. |
| `tests/` | Python, browser and protocol tests; `tests/results/` holds recorded runs. |

Licence: MIT for the project's own code and example content. Bundled third-party components keep
their licences — see [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) and `licenses/`.

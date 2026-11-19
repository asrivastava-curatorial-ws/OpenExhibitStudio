# Release verification 0.3.0

Everything below was run on 19 November 2026 for this release; the logs are in `tests/results/`.
Nothing physical was attached to the test machine: no microcontroller, sensor, actuator, webcam,
projector, phone or Windows computer. Results for those are listed under *Not tested*.

**Test machine.** x86-64 Linux container (kernel 6.18, 2 CPU cores), Python 3.13.18, official
Godot 4.7.1 (a13da4feb) and 4.6.3 (7d41c59c4) Linux builds, Mesa llvmpipe (software OpenGL 4.5)
on Xorg dummy displays, Google Chrome for Testing 153 with Playwright 1.63, Node 22, g++ 13.3,
Mosquitto 2.0.18 with paho-mqtt 2.1.0, NumPy 2.5 and OpenCV 5.0.

**Reproduce.** `bash tests/run_all.sh --chrome /usr/bin/google-chrome --log run.log` runs every
suite below that the computer supports ([build guide](BUILD.md)).

## Automated suites on Godot 4.7.1

Log: `tests/results/verification-0.3.txt`.

| Suite | Observed result |
| --- | --- |
| GDScript parse check | All 37 scripts parse. |
| Core project and rule suite | 12 checks passed. |
| Integration, headless, with IPv4 and IPv6 socket creation denied | 116 checks passed: all 15 examples pass checksum/schema, asset relocation and package round trip; canvas editing, undo and redo; every Studio workspace opens; all 24 installation presets validate; homography, mesh warp, cylinder and sphere mapping; a measured camera report applies to the right output, undoes, and a wrong-size report is rejected; session, rule and output-arming behaviour. |
| Integration on two X11 heads (1280 × 720 and 1024 × 768) | 118 checks passed — the 116 above plus rendered exhibit colours in the scene texture and a calibrated second window showing the live projector feed. |
| Every example launches in the Player | 15 of 15: one feed per configured output, every scene object instantiated, images loaded and videos playing. |
| UV-mapped mesh rendering | Sampled exhibit content rendered on an OBJ mesh through a perspective projector. |
| Rendered mapping pixels vs an independent model | 17 rendered rasters, 8,523 RGB probes; largest deviation 1.02/255, summed blend overlap within 0.60/255. Cases: plain, corner pin, mask and gain, left and right blend, mesh, sphere, rotated sphere, cylinder, cylinder seam, fulldome and six cubemap faces. |
| Player live-audience board against a real service | The Player rendered lobby, open question, reveal and standings from a running `tools/quiz.py`. |
| LAN timeline clock | Godot follower and Python publisher exchanged authenticated replies; timeline running (round trip 7 ms on loopback). |
| Python unit and integration tests | 59 tests: 58 passed, 1 skipped (Modbus TCP needs the optional pymodbus). Includes the 11 new live-audience engine tests (clicker-style advance, back-navigation review, auto-close race, long-poll wake-up, ideas/voting/moderation, ranking (Borda) and scale, reactions, spinner, anonymous join, Aiken import, 0.2 deck compatibility) and the firmware block generator, whose sketch compiled with g++ against an Arduino API stub. |
| Live audience in Chrome | Editor (gallery, Aiken paste, autosave), presenter keyboard control, projector updating without reload, and two phone-sized clients (one with a Bengali name) through poll, word cloud, quiz, multiple answers, number, pause, scale, ranking, ideas, Q&A and spinner; back-navigation review, podium and summary CSV. Zero JavaScript exceptions. |
| Live audience across an isolated network namespace | Host and participant processes exchanged real TCP traffic between two private IPv4 addresses with no default route; the participant joined, scored and read the ranking; the operator port was unreachable from the audience address. |
| Structured-light calibration at native sizes | 1920 × 1080 projector with 1920 × 1200 camera: corner error 0.145 px, spatial p95 0.489 px, independent p95 0.181 px. 3840 × 2160 projector with 1920 × 1080 camera: 0.040 px, 0.481 px, 0.501 px. Synthetic captures. |
| MQTT | Authenticated Mosquitto + Paho with the shared firmware protocol compiled as a native fixture: handshake, input 72 reached the gateway, an armed indicator returned feedback 1, and losing the broker disarmed the link. |
| Lint and formatting | `ruff check` and `ruff format --check` clean (Python); ShellCheck 0.11 clean for setup, launchers and test scripts; Prettier 3.10 `--check` clean for the web pages and block editor; GDScript formatted with gdtoolkit 4.5 (`tools/dev/fix_lambdas.py` then re-attaches multi-line lambdas, which gdformat splits in a way Godot cannot parse). |

## Engine suites on Godot 4.6.3

Log: `tests/results/verification-0.3-godot-4.6.3.txt`. Run on a separate copy of the tree, imported
with 4.6.3. All engine suites passed with the same counts: parse check (37 scripts), core suite (12),
headless integration (116), LAN clock, two-head integration (118), all 15 example launches, mesh
rendering, mapping pixels (17 rasters, 8,523 probes, 1.02/255) and the live-audience board.

## Regression found in 0.2.0

The unmodified 0.2.0 code, run on Godot 4.7.1, finished the headless integration suite with 113
checks and 13 failures: the package round trip failed for 13 of the 14 examples, because Godot 4.7
writes folder entries into zip files. 0.3.0 ignores them (see the [changelog](../CHANGELOG.md)).

## Installation

The archive made by `tools/release.py --source` (no duplicate entries, no engine or build output)
was extracted into an empty folder. `bash setup.sh` downloaded `Godot_v4.7.1-stable_linux.x86_64.zip`
(72.5 MB) from the GitHub release, verified its pinned SHA-512, imported the app and built both
packs in 23 seconds. In that folder `tests/package_smoke.py` then opened native X11 windows for
Studio (`studio.sh`, showing *Orbital atlas*) and the Player (`player.sh`, *Travelling waves*), and
a player-only copy holding just `bin/godot`, `bin/player.pck` and `player.sh` opened an exported
book package before and after its process was killed.

## Not tested

- **Physical hardware.** No Arduino, ESP32, sensor or actuator was connected. Serial was exercised
  through an OS pseudo-terminal and MQTT through a compiled firmware fixture. Board-target builds
  with Arduino CLI were not repeated for 0.3.0 (the board toolchains could not be downloaded here).
- **Phones and venue networks.** Phone pages were tested in desktop Chrome at phone viewport sizes,
  not on Android or iOS devices, and not over Wi-Fi.
- **Projectors and cameras.** Mapping and calibration were verified against rendered pixels and
  synthetic captures only; optical alignment needs the installed projectors.
- **Windows.** No Windows execution. PowerShell 7 on Linux ran the download, SHA-512 check and
  extraction steps of `Setup-Windows.ps1`, which then stops where it starts the Windows engine.
- **Other platforms and packages.** ARM64 Linux, the `.deb` package and native single-file exports
  were not built or installed for 0.3.0.
- **Long runs.** The resource soak (`tools/soak.py`) was not repeated for 0.3.0.
- **People.** Studio's usability changes were reviewed through screenshots of every workspace, not
  with museum staff or visitors. Screen-reader accessibility was not assessed.

Earlier reports: [0.2.0](TEST-RESULTS-0.2.md) · [0.1.0](TEST-RESULTS-0.1.md).

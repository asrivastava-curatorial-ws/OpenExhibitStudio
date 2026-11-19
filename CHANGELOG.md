# Changelog

## 0.3.0 — 2026-11-19

Rework of the 0.2.0 code base (generated with ChatGPT) to make it install, run and be usable by
non-programmers. Everything that worked and was tested in 0.2.0 is kept; the project format is
unchanged, so 0.2 exhibits and slide decks open as they are.

### Fixed

- **Did not start from the source archive.** The launchers needed a Godot binary that the archive
  did not contain, at exactly version 4.6.3. `setup.sh` / `Setup-Windows.cmd` now download the
  official engine (pinned SHA-512), import the app and build the Player/Studio packs with that same
  engine; the launchers run setup automatically on first start. Offline installs use `--offline`.
- **Exported packages could not be reopened on Godot 4.7.** Godot 4.7 adds folder entries to
  zip files, which the package reader rejected (13 of 14 examples failed the round-trip test).
  Both the Godot and Python readers now ignore folder entries.
- **Board planner button did nothing**: its helper object was freed as soon as the workspace was
  drawn. It is now kept alive.
- **Player operator panel unusable** unless an environment variable was set. The first use now
  sets a password (salted hash stored locally); the variable still works for managed sites.
- **Background services kept running after Studio closed**, blocking ports 8786/8787 at the next
  start. Studio now stops the live-audience and hardware services when it quits.
- Closing Studio with unsaved changes now asks to save (it previously saved only a recovery copy).
- The version label said 0.1.0.
- Firmware block editor required `npm install` (internet) — Blockly is now vendored.
- The source archive contained a stale `SHA256SUMS.txt` from 0.2.0 and the release script wrote a
  second one next to it; the archive now carries one freshly computed inventory and no build output.

### Studio

- Workspace rail with names and groups (Design · Behaviour · Install · Run) instead of icons only.
- Start screen with templates, recent exhibits and open; *Save as* into a folder makes a template
  your own.
- Inspector edits apply immediately (no *Apply* button), with colour pickers, alignment, hidden and
  locked flags, and coalesced undo for quick repeated edits.
- **When pressed** on buttons: pick an action (scene, variable, timeline, output, page, reset)
  without typing event names.
- **Interactions** (rule builder) shows every rule as a sentence and edits it with pickers for
  buttons, sliders, sensors, scenes, variables, timelines and outputs; variables have a table
  editor instead of JSON.
- **Hardware**: virtual sliders and lamps for every channel; *Start hardware service* picks a board
  profile and USB port, starts the gateway with a fresh token and connects — no terminal or token
  copying. New profile for any sketch that prints “name value” lines.
- Scene list with reorder, duplicate and delete (references to a deleted scene are cleaned up).
- Help menu, command palette runs the first match on Enter, more shortcuts (Ctrl+N/E/Q).
- Code rewritten for readability: the shell is split into `main.gd`, `logic_space.gd`,
  `hardware_space.gd`, `audience_space.gd`, `workspaces.gd`, `welcome.gd`, `rule_text.gd`; all
  GDScript is formatted (gdtoolkit), Python with ruff, web code with Prettier; ruff lint is clean.

### Live audience (AhaSlides-style)

- Instant updates: phones, projector and presenter receive changes by long-polling instead of
  polling every second (answers appear on the projector within a fraction of a second).
- Presenter console: current slide and next-slide previews, presenter notes, one **Next** that does
  the right thing (start → reveal → leaderboard → next), **Back** to review earlier slides,
  clicker/keyboard control, Q&A, idea and people panels, exports.
- Full-screen 16:9 projector view: large join banner and QR, coloured answer tiles, animated bars,
  word cloud, histogram with average, idea cards, Q&A board, spinner wheel, animated leaderboard
  and podium, floating emoji reactions; dark (GitHub) or light theme.
- Slide editor: slide list with drag reorder, slide gallery, live preview, per-type forms (tick the
  correct options), automatic picture resizing, session settings, Aiken question paste/import.
- New slide types: open-ended ideas (with voting and moderation), audience Q&A slide, spinner wheel
  (participants or custom entries, optional remove-winner), ranking poll (Borda score), rating
  scale up to 10 with end labels, content slides with body text and layouts. Opinion slides can be
  untimed.
- Questions close automatically when everyone has answered; emoji reactions; anonymous joining;
  leaderboard after each question, at the end or never.
- Summary export (poll counts, word frequencies, ideas, spinner results, Q&A) besides the
  per-answer CSV.
- Studio integration: *Edit slides*, *Start session and present*, *Save slides into this exhibit*,
  resume a saved session; network choice in plain words.
- New example 15: an interactive science talk using every slide type.

### Packages

- **Linux AppImage** (x86-64): Studio and Player in one file — `player` opens the Player, `desktop`
  adds both to the application menu. The serial and MQTT libraries are bundled; the live-audience
  and hardware services use the computer's python3.
- **Windows installer** (x64): per-user install without administrator rights, Start-menu entries,
  optional desktop shortcuts and `.oex` double-click to play, and an uninstaller that removes only
  what it installed. Bundles CPython 3.12.13 with pyserial and paho-mqtt.
- `packaging/runtimes.py` pins every bundled third-party file by SHA-512 or SHA-256. It replaces
  `tools/windows_runtime.py`, whose embedded-Python digest could not be verified;
  `tools/release.py` now builds only the source archive.
- `gateway/requirements-field.txt` pinned paho-mqtt 2.2.0 against the tested 2.1.0 in
  `requirements-optional.txt`; both now use 2.1.0. Desktop entries use one menu category.

### Tests

- `bash tests/run_all.sh` runs every suite the computer supports and reports PASS, FAIL or SKIP
  (with the missing tool) for each.
- New: `tests/test_audience.py` (11 engine tests), `tests/audience_browser.py` (Chrome: editor,
  presenter, projector and two phones through every slide type), `tests/test_firmware_blocks.py`
  (block-editor sketches compile with g++ against an Arduino API stub).
- `tests/mqtt_broker.py` also runs as root now: Mosquitto drops privileges when started as root and
  then could not read the test password file.
- Results: [docs/TEST-RESULTS.md](docs/TEST-RESULTS.md). Every automated suite passes on Godot
  4.7.1, and the engine suites also pass on 4.6.3. Arduino CLI board builds, the .deb install,
  Windows execution and physical hardware were not re-tested for this release.

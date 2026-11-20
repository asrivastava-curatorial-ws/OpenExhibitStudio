# Reuse: what was taken from existing open-source work, and why

OpenExhibit Studio is meant to run offline on ordinary exhibit computers, installed by museum
staff, from one folder. That requirement decided most reuse questions: a component is bundled
when it is small, permissively licensed and works without a server; larger tools are supported
through the open protocols they already speak rather than merged in.

## Bundled in 0.3.0

| Component | Licence | Used for |
| --- | --- | --- |
| [Godot Engine 4.7.1](https://godotengine.org) | MIT | Studio, Player, rendering, mapping shaders, native windows. Downloaded and SHA-512-checked by setup, not stored in the source archive. |
| [Blockly 12.5.1](https://github.com/google/blockly) | Apache-2.0 | Offline firmware block editor (`firmware/blockly/vendor`). Previously it required `npm install`, so it did not work offline out of the box. |
| [wordcloud2.js 1.2.3](https://github.com/timdream/wordcloud2.js) | MIT | Word-cloud layout on the projector. |
| [canvas-confetti 1.9.4](https://github.com/catdad/canvas-confetti) | ISC | Podium and spinner celebrations (worker disabled to respect the page's content security policy). |
| [SortableJS 1.15.7](https://github.com/SortableJS/Sortable) | MIT | Touch drag-and-drop for ordering/ranking answers on phones and reordering slides in the editor. |
| QR encoder (Kazuhiko Arase et al., via ReportLab) | MIT | Join QR codes (carried over from 0.2). |
| JetBrains Mono, Noto Sans Bengali/Devanagari | OFL | Interface font and Indic shaping. |

## Formats reused

- **Moodle Aiken** question format for pasting question banks into the live-audience editor.
- **ASCII “name value” lines** over serial, the convention most existing Arduino sketches already
  use; the block editor generates it and the gateway reads it.
- **Firmata / ConfigurableFirmata**, **MQTT** (Mosquitto), **OSC**, **Art-Net/sACN**,
  **Modbus**, **MIDI** and **HID** through the gateway adapters (from 0.2).

## Evaluated and not bundled

These were reviewed from their published documentation, licence and technology stack; none was
installed and benchmarked here.

| Project | What it offers | Decision |
| --- | --- | --- |
| [Claper](https://github.com/ClaperCo/Claper) (GPL-3.0) | Self-hosted interactive presentations: polls, Q&A, quizzes over imported PowerPoint/PDF. | Needs Elixir/Phoenix, PostgreSQL, Node, Ghostscript and LibreOffice — a server stack, not a one-folder offline tool, and no projection-mapping path. Its presenter flow (imported slides + interactions) informed the slide editor. |
| ClassQuiz (MPL-2.0), [Rahoot](https://github.com/Ralex91/Rahoot) (MIT), [Fuiz](https://github.com/fuiz/game-backend) (AGPL-3.0), Huddle (MIT) | Kahoot/Mentimeter-style live quizzes. | Each is a separate web stack (Python + Redis/Postgres, Node, Rust services or Docker). They cover quizzes well but not the museum constraints: no-internet LAN use from Studio, Windows desktops without Docker, and rendering results through projector calibration. The existing standard-library Python service was kept and extended instead (about 1,600 lines of Python plus the browser pages, with no runtime dependencies beyond Python 3.10). |
| [Splash](https://gitlab.com/splashmapper/splash) (GPL-3.0) | Multi-projector mapping with semi-automatic geometric, blending and colour calibration for domes and 3D surfaces. | Recommended alongside OpenExhibit for large domes and complex surfaces that need its camera-based calibration. Not bundled (GPL application with a large native toolchain); there is no tested Splash import/export yet. |
| [Chataigne](https://github.com/benkuper/Chataigne) (GPL-3.0) | Show control with state machines and timelines over OSC, MIDI, DMX, serial, HTTP. | Complementary: for shows that need more than OpenExhibit's rules and timelines, Chataigne can drive or listen to exhibits through the gateway's OSC adapter (profile `osc.json`). |
| QLC+ (Apache-2.0) | DMX lighting desks and virtual consoles. | Use it for full lighting design; OpenExhibit sends Art-Net/sACN levels for exhibit-linked lighting. |
| Open Stage Control (GPL-3.0) | Browser-based OSC control surfaces. | A ready-made option for custom operator panels talking OSC to the gateway. |
| Linux Show Player (GPL-3.0) | QLab-style cue lists for audio/video. | Not merged; OpenExhibit's timeline covers exhibit-scale cueing. |
| MapMap (GPL-3.0) | Simple quad/mesh projection mapping. | Overlaps with the built-in corner-pin and mesh warp. |
| [OBS Studio](https://obsproject.com) (GPL-2.0) | Live production with a chroma-key filter (CbCr distance, similarity, smoothness, spill). | A good choice for broadcast-style green screens, but no visitor takeaway (QR photos and videos), no exhibit packaging and a large desktop install. The booth's keyer uses the same standard technique, written independently; no OBS code is included. |

## Original in this project

The project format, session engine, mapping shaders and calibration solver, Studio interface,
live-audience server and pages, green-screen booth (service, keyer and pages), gateway and firmware are
original code under the MIT licence.
“AhaSlides”, “Kahoot” and similar names identify the products whose public feature lists were
used as references; no code or assets from them are included.

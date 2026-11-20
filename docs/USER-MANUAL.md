# OpenExhibit Studio — user manual

This guide assumes no programming. Keys in **bold**; menus as *File → Save as*.

## 1. Start

Run `bash studio.sh` (Linux) or `Studio.cmd` (Windows). The first start downloads the Godot engine
once and prepares the app (about half a minute).

The **start screen** offers:

- **Blank exhibit** — one empty scene at 1280 × 720.
- **Templates** — the sixteen bundled examples (kiosk, flipbook, live talk, green-screen booth, video show, Arduino,
  projection panorama, sphere, cyclorama, immersive room, physical book, and more).
- **Recent** exhibits and **Open** for a project (`project.oes.json`) or package (`.oex`).

Templates open read-only. Use *File → Save as* and choose an **empty folder**: Studio writes
`project.oes.json` there and copies every image, sound and video into `assets/`.

## 2. The window

| Area | Purpose |
| --- | --- |
| Left rail | Workspaces, grouped as Design (Screens, Flipbook, Science, Media), Behaviour (Interactions, Timeline, Hardware), Install (Installation, 3D view, Projection) and Run (Try it, Live audience, Publish). Hover for a description. |
| Scenes | Pages of the exhibit. ★ marks the first scene. Buttons below reorder, duplicate and delete. |
| Layers | Objects on the current scene, front-most at the top. Buttons below change stacking, duplicate and delete. |
| Centre | The selected workspace — on Screens, the canvas. |
| Inspector | Properties of the selected layer, or of the scene when nothing is selected. |

## 3. Design a screen

- **Add component** opens a menu: text, button, panel, image, video, sound, 3D model, slider,
  text box, drawing pad, gauge, live chart, solar system, particles, fractal, live audience board.
  You can also drag image, sound, video and 3D files onto the window.
- Click an object to select it. **Drag** to move; drag the bottom-right handle to resize. Moves snap
  to 8 px; hold **Alt** for single pixels.
- The **Inspector** applies changes as you type (press **Enter** or click elsewhere). Colours
  open a colour picker. Several quick edits to the same field count as one undo step.
- Text can show live values: `Visitors pressed {score} times` displays the variable `score`.
- **Hidden** layers are not drawn; **Locked** layers cannot be clicked on the canvas.
- Video must be Ogg Theora. Convert with
  `ffmpeg -i input.mp4 -c:v libtheora -q:v 7 -c:a libvorbis output.ogv`.

## 4. Make it interactive

### Buttons — When pressed

Select a button and choose an action under **When pressed**: go to a scene, set or add to a
variable, play a timeline, send a value to a device output, next/previous page, or reset the visit.
That is all a simple navigation kiosk needs.

### Interactions

For anything richer, open **Interactions**. Every rule reads as a sentence:

> When button “Mars” is pressed → set planet to “Mars”; set days to 686.98; go to scene “Mars facts”.

**+ New interaction** opens three steps:

1. **When** — pick from everything that can happen: each button, slider and text box (by name),
   each sensor channel, each scene opening, a new visit starting, next/previous page — or type a
   custom event name.
2. **If** (optional) — compare the incoming value or a variable with a value.
3. **Do** — one or more actions, in order. The target adapts to the action: a scene list, a
   timeline list, a variable name (with suggestions under **…**), an output channel.

The sentence at the bottom updates as you edit. **Variables…** sets starting values for each visit.
**Try an event** sends any event by hand; the *Variables now* and *Event trace* panels show what
happened. **● Break** pauses the visitor session when a rule fires, so you can inspect it;
**Resume after breakpoint** continues. **Graph view** shows rules as connected nodes.

### Try it

Press **F5** or **▶ Try it** to use the exhibit as a visitor — buttons work, timelines play and the
idle reset runs. **F5** returns to editing. **Reset visit** starts over.

## 5. Timelines

A timeline runs actions at set times (cues) and animates layers (keys) — for attract loops,
narrated shows or synchronised effects. In **Timeline**: **+ New timeline**, drag the scrubber,
then **+ Cue at playhead** or **+ Animation key at playhead**. Two keys on the same property animate
between them (linear, smooth or step). Scrubbing never replays device outputs: it switches them
off. *View → Exhibit settings* can start a timeline automatically and reset idle visitors.

## 6. Flipbooks

Each scene is a page. In **Flipbook**, add blank pages or pages from images, arrange the scenes,
and press **Build page navigation**: it adds ‹ › buttons, arrow-key and swipe turning, and rules
for a page sensor (RFID, markers) that sends a page number. Run it again after adding pages.
Whole PDFs: `python3 tools/import_pdf.py book.pdf my-book` (needs Poppler).

## 7. Hardware

Open **Hardware**.

- **Try it without hardware** — a slider and a *Pulse* button for every input channel, and lamps
  for every output. Tick **Arm virtual outputs** to see outputs switch.
- **Connect a board** — pick the board or protocol, plug the board in, press **Refresh**, choose
  its port and press **Start hardware service**. The status line shows the connection. Press
  **Arm outputs** before anything can switch on; unplugging, restarting or reconnecting always
  switches outputs off again.
- **Firmware and wiring** — the board pin planner, the offline **block editor** (drag sensor
  blocks, export an Arduino sketch), wiring drawings, and the exact Arduino CLI commands.

On Linux, allow your user to open USB serial devices once:
`sudo usermod -aG dialout $USER` (then log out and in). Install the USB extras with
`bash setup.sh --hardware`.

A software stop is not an emergency stop. Anything that moves, heats or uses mains power needs a
hard-wired emergency stop and suitable drivers — see [HARDWARE.md](HARDWARE.md).

## 8. Live audience

Polls, quizzes, word clouds, idea boards, Q&A and a spinner wheel on visitors' phones. See
[LIVE-AUDIENCE.md](LIVE-AUDIENCE.md).

## 9. Green screen

A camera photo booth. Visitors stand in front of a green cloth, appear in your background videos or
pictures, and take a photo or a short video home by scanning a QR code (local network only).
**Green screen → Add video or picture…**, then **Start booth**; calibrate on the booth with
**Ctrl+Shift+S**. See [GREEN-SCREEN.md](GREEN-SCREEN.md).

## 10. Screens and projectors

**Installation** chooses a layout preset (kiosk, video wall, panorama, cyclorama, 360° ring,
sphere, dome, immersive room, CAVE, physical book, Pepper's ghost …) with real dimensions in
metres. Content scenes are kept, so the same exhibit can move to a different room.

**Projection** previews each output with exhibit content, an alignment grid or colour bars. Drag
the four corners (or a 3 × 3 mesh) until the grid lines up with the surface. **Output settings**
sets the screen number, resolution, which scene it shows, gamma, black lift and edge-blend widths.
Calibration profiles can be saved and reused. The camera wizard and measured reports are described
in [CALIBRATION.md](CALIBRATION.md).

## 11. Publish and run

**Publish → Export .oex package** writes one file containing the project and all media, with
checksums. On the exhibit computer:

```sh
bash player.sh exhibit.oex --kiosk      # Linux
Player.cmd exhibit.oex --kiosk          # Windows
```

| Player key | Action |
| --- | --- |
| F11 | Full screen on/off |
| F2 | Cycle test patterns |
| F5 | Reset the visitor session |
| F10 | Operator panel (password) |
| F12 | Switch all device outputs off immediately |
| ← → | Previous / next page |

In kiosk mode Escape, F11, F2 and F5 do nothing, so visitors cannot leave or reset the exhibit;
use the operator panel.

The first time someone opens the **operator panel (F10)** on a computer, they choose its password
(stored only as a salted hash on that computer). A site can instead provide
`OPENEXHIBIT_OPERATOR_KEY` through its service manager. Start-at-login, offline updates and
rollback are in [DEPLOYMENT.md](DEPLOYMENT.md).

## 12. Saving and recovery

**Ctrl+S** saves; the previous version is kept as `project.oes.json.bak`. Unsaved edits are
copied to a recovery file within a second; after a crash, Studio offers to restore them. Closing
with unsaved changes asks whether to save. Media files are checked by SHA-256 when an exhibit
opens or is exported.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Ctrl+N / Ctrl+O / Ctrl+S / Ctrl+Shift+S | New / open / save / save as |
| Ctrl+E | Export .oex package |
| Ctrl+Z / Ctrl+Shift+Z (or Ctrl+Y) | Undo / redo |
| Ctrl+D / Delete | Duplicate / delete the selected layer |
| Ctrl+P | Command palette (type to search, Enter runs the first match) |
| F5 | Try it / back to editing |
| Ctrl+Q | Quit |

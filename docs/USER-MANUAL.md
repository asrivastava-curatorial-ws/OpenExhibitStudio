# Create your first exhibit

For phone-based museum competitions, start with **View → Live quiz contest** and the [contest operator guide](LIVE-QUIZ.md). For structured-light capture, choose **Mapping → Camera calibration wizard** and use the [projection commissioning guide](CALIBRATION.md). The [field adapter guide](FIELD-IO.md) covers external meters, indicators and input devices.


## Make a working copy

1. Start Studio and open **File → Examples → Orbital atlas**.
2. Choose **File → Save as**. Create a new folder, open it and save **project.oes.json**. Studio copies the artwork with the project.
3. Click **Test exhibit** and press **Mars** on the exhibit. The card should show **686.98 Earth days**. Click **Test exhibit** again to return to the canvas.

## Edit the visitor screen

Choose an object in **Layers**, or click it directly on the canvas. The Inspector shows its name, content, colour and rectangle. Change a value and choose **Apply changes**. Drag the selected object to move it. Drag its bottom-right handle to resize it. Snap uses eight logical pixels. Hold Alt during a drag for single-pixel positioning.

Use **+ Object** for buttons, text, panels, images, video, audio, sliders, charts, drawing pads, text entry or scientific objects. Files dropped on the Studio window import as new components. Use the layer arrows to move an object in front of or behind another object. **Copy** creates a new object ID. A duplicate button retains its original event binding, so either button can operate the same action.

Layers are local to their scene. Use **New scene** for a new visitor page. With no layer selected, edit the scene name, background and transition in the Inspector. Select **View → Global settings** for the exhibit title, first scene, logical dimensions, idle reset or startup timeline.

## Connect a button without writing code

1. Add a **Button** and change its text to **Add one**. In its **On press** field enter **tap.count** and apply the change.
2. Add **Text**, set its text to **Visitors pressed {score} times**, and apply.
3. Open **Logic** from the left rail or command palette. Choose **Variables** and enter `{"score":0}`.
4. Choose **When–If–Do rule**. Enter **tap.count** for When and choose **always**. For Do choose **add**, set the target to **score** and the value to **1**. Save the rule.
5. Test the exhibit. Every press increments the number. Reset visit restores the starting value.

A rule can have several actions. Open an existing rule and choose **Edit all actions**. Choose **Node graph** to view event-to-action connections. Drag an event output onto another action to add a copy to that event’s sequence. The trace lists executed events and the variable watch shows their resulting values. A breakpoint holds actions until **Resume breakpoint**.

## Choose an installation

Open **Installation**, select a preset and choose **Apply installation layout**. The physical layout can change while you keep the visitor scenes. Set each output’s display index and resolution in **Mapping → Output settings**. Choose **@live** to follow the visitor’s current page or select a fixed scene for a dedicated projection. A surface can therefore show the same variable as the touchscreen with a different design.

For a first optical check, project the alignment grid and adjust corner or mesh handles. Use the Mapping guide for sphere, room and cylinder conventions. Save a calibration profile to reuse an installation with another exhibit.

## Multimedia and books

Import PNG, JPEG, WebP or SVG artwork. Use embedded GLB/glTF or triangulatable OBJ files for 3D objects. Use WAV, MP3 or Ogg Vorbis audio and Ogg Theora (.ogv) video. A movie can be converted before import with the command in the build guide. A scene starts its media on entry. The first scene stream owns audio in a multi-output player to avoid duplicate playback.

The **Flipbook** workspace treats scenes as pages. Import page images, arrange the scenes in the desired project order, then choose **Build page navigation**. This creates on-screen navigation, arrow-key actions and numbered page-input rules. The supplied book has three illustrated geology pages. Horizontal touch swipes turn linked pages. **tools/import_pdf.py** rasterizes a PDF into a standalone book project using Poppler. Complex original PDF interactions do not survive rasterization.

## Play a timed show

Open **Timeline** and create a timeline. **Add cue** places a scene change, state update or output request at a time in seconds. **Add animation key** sets an object’s x, y, rotation or opacity at that time. Add a second key to interpolate between the two. Choose linear, smooth or step interpolation. **Edit tracks** exposes duration, looping and the complete cue and key lists.

Scrubbing moves the visual playhead and samples scene navigation and animation. It disarms outputs. General rules, old actuator pulses and visitor submissions are never replayed during a seek. Independent audio/video decoder positions are not chase-locked to the show clock. Try **Travelling waves** for a two-film sequence with slide and fade transitions.

## Test a physical interaction on a desk

Open **Reef finder → Hardware**. Choose **dial**, enter **70**, arm virtual outputs and inject the sample. The watched rock becomes **Sandstone**. Virtual **lamp** and **light** become 1. In Deployment choose **Launch standalone preview** to open both display windows. Drag the kiosk slider to change the projection. Each Studio workspace edit rebuilds the preview session, so arm only after editing.

Hardware includes a board/pin planner and an authenticated gateway connection. A planned channel is a description. The site gateway profile and matching firmware determine what a physical pin actually does. The hardware guide walks through a complete Arduino bench setup.

## Save, recover and hand over

**Save** writes the project and maintains a .bak copy of the previous file. A short delay after an edit creates a separate recovery journal. Reopen Studio after an interruption and choose **Restore**, inspect the changes and save. A changed-on-disk manifest triggers a Save As request. Use one Studio editing session per workstation for recovery journal isolation.

**File → Export package** creates a .oex containing the project and all referenced assets. The player verifies its checksums before playback. To edit a package, open it and use Save As. A package carries the logical hardware channels. Site secrets and local serial-device paths are configured on the playback computer.

| Shortcut | Action |
| --- | --- |
| Ctrl+S / Ctrl+Shift+S | Save / Save As |
| Ctrl+O / Ctrl+P | Open project / search commands |
| Ctrl+Z / Ctrl+Shift+Z or Ctrl+Y | Undo / redo |
| Ctrl+D / Delete | Duplicate / remove selected layer |
| F5 in Studio | Enter or leave visitor test |
| F2 / F5 / F11 in normal Player | Calibration patterns / reset visit / full screen |
| F10 / F12 in Player | Password-protected operator controls / immediate software disarm |
| Left / right arrow in a linked book | Previous / next page |

Use the splitter handles to resize panels. The Inspector can detach into a separate native window and dock again. Standard buttons and inputs participate in keyboard focus navigation. Test the actual visitor touch controller, keyboard, contrast, font size and reach at the installation.

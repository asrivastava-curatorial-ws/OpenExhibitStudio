# Architecture and implementation plan

OpenExhibit Studio stores the exhibition as data. Native Godot controls author that data. A separate Godot player loads the same files without the Studio scripts. The default renderer uses OpenGL Compatibility. Desktop, virtual device and sample playback work offline.

| Layer | Ownership and contract |
| --- | --- |
| Content | Scenes own ordered components in logical pixel coordinates. Stable object IDs connect design, logic and animation. Assets are local relative files with SHA-256 digests. |
| Interaction | One session owns visitor variables, event processing and a monotonic show clock. Views subscribe to the session. Presentation changes and device output requests take separate paths. |
| Installation | Surfaces describe physical dimensions in metres. Outputs bind a scene or the live session to a surface, display, pixel resolution, view and calibration. Installations can be exchanged independently of content. |
| Devices | Project channels describe exhibit intent. A separately configured loopback gateway owns ports, broker credentials, arming and connection lifetimes. A virtual device runs directly in the session. |
| Runtime | One or more output windows sample live scene textures. No authoring controls are loaded by the player build. Power-up creates a fresh visitor session and disarmed outputs. |
| Trust | Projects contain data. They cannot run commands or select a serial port, SMTP account or broker on their own. Optional extensions and external tools run only when installed by an operator. |

## Build order and gates

1. Load, validate, save and reopen data. Play a scene in the standalone runner. Add canvas selection, object editing, asset import and recovery. Gate on a portable project round trip and real input-to-state changes.
2. Connect virtual and serial/MQTT inputs to the same event path. Gate the software path on transport and disconnection tests. Reserve physical acceptance for a bench.
3. Reuse the scene renderer across outputs. Gate planar mapping on point correspondences, blend overlap and independent window dimensions.
4. Add metre-based curved surfaces, installation preview and spherical reference checks. Reserve optical calibration for the installed projectors.
5. Integrate timed cues, books, multimedia and advanced inputs on the common event path. Exercise seek, navigation and session reset.
6. Add supported calibration or scientific extensions with explicit dependency checks.
7. Assemble separate player and Studio releases. Verify the distributed entry points and record measured results and remaining acceptance work.

## Release gates after this milestone

| Next gate | Dependencies and evidence needed |
| --- | --- |
| Physical I/O | Commission Uno and ESP32 test rigs, fix any firmware/core incompatibilities and record measured watchdog latency and restart behaviour. |
| Optics | Validate a planar pair, a measured cylinder, a four-projector sphere and a physical book. Use these measurements to prioritize camera-solved and structured-light calibration. |
| Production edit and playback | Add the remaining media/layout/graph/protocol features against published schema migrations. Exercise old example projects on every change. |
| Field release | Validate on fresh Ubuntu and Windows, produce signed native installers, run loaded multi-shift soak tests and complete electrical, accessibility and optical acceptance at the installation. |


## Contest and calibration services in 0.2

The Python quiz service owns the room state and clock. SQLite transactions serialize answers and phase transitions. The private operator listener authenticates management commands. Audience browsers receive public round data from a separate listener. The Godot contest scene component uses the public state shape and feeds its native rendering into the existing mapping shader.

Structured-light acquisition stores raw images. A separate calibration process estimates geometry and measures holdouts. Studio imports a measured solution into one chosen output with normal validation and undo. The same shader produces live output and exported pixels. Numerical projection tests compare rendered output with an independent implementation.

# Historical verification · 0.1.0

Test environment: Linux x86-64, Debian 13, Godot 4.6.3 official build 7d41c59c4. Graphical runs used Xorg with the dummy display driver and Mesa llvmpipe OpenGL. The two display heads were configured as 1280 × 720 and 1024 × 768. Native controls, real viewport textures, files, sockets and processes were exercised. Audio playback used Godot’s Dummy audio driver on this host.

| Executed check | Observed result |
| --- | --- |
| Core project and event checks | **12 passed.** Includes save/reopen, package integrity, metadata preservation, interrupted-save backup recovery, unsupported version rejection and recursive timeline protection. |
| Offline integration suite | **106 passed.** A Linux process filter denied creation of IPv4 and IPv6 sockets. Project relocation, all thirteen package round trips, Studio workspaces, editing, undo/redo, input, time and mapping checks completed. |
| Graphical integration suite | **108 passed.** Two native output windows used different resolutions. Pixel readback confirmed distinct exhibit colours in the rendered content and calibrated output. A pointer event sent through the output feed reached a native exhibit button. |
| Example launch sweep | **13 of 13 passed.** Each example opened all assigned windows. The test instantiated its scene nodes, checked loaded textures and verified native video playback state where applicable. |
| Python unit/integration suite | **16 passed.** Includes schema validation, update/rollback, corrupted archive handling, serial/firmware integration, Firmata input reports, OSC, token rejection, disconnected outputs, clock authentication, rotated page symbols, the Blockly sketch generator and two-page PDF import with Poppler. |
| Shared firmware core | Compiled with the host C++17 compiler. Assertions passed for identity handshake, disarmed boot, explicit arm, command duplication, bounded outputs, timeout and stale-session rejection. No Arduino board core was used in this test. |
| Serial round trip | The real gateway opened an OS pseudo-terminal connected to a separate compiled device-fixture process running the shared endpoint code. A dial value reached an authenticated TCP client, an armed output command reached the endpoint, its feedback returned, and controller/device disconnects cleared output state. |
| LAN show clock | A native Godot follower accepted a nonce-bound HMAC response from the Python publisher on loopback, selected the expected timeline and entered playback. Observed round-trip estimate was 1 ms in this run. Separate physical computers and network load remain untested. |
| Hardware-to-views fan-out | One logical dial sample updated both the kiosk and projection render trees and requested two independent virtual indicators. |
| Geometry | Tests passed for corner correspondences, a displaced interior mesh control, cylinder seam/height, rotated equirectangular longitude and an uncovered pole. A real UV-mapped OBJ rendered from a perspective projector. Centre and background pixels were independently checked. |
| Warped feed export | Rendered a 12-frame FFV1 AVI at 12 fps from the second Reef finder output. ffprobe reported **1024 × 768** and **12 frames**. |
| Resource observation | A headless two-output run completed **600.99 seconds**. The last engine sample contained **17,982** input events. At the first post-warmup and final host readings, RSS was **76,204 KiB** and the process held **4 file descriptors**. Differential readings were zero; peak post-warmup RSS was **76,308 KiB**. An independent 30,000-event stress test kept trace/history lengths bounded. |
| Packaged applications | Linux Studio and the film project opened through the distributed launchers. A player-only directory containing the engine, player pack, launcher and one .oex opened the book twice, including a restart after terminating the first process. Separate Linux and Windows-target data packs were generated. The .deb was inspected and extracted. Studio, the film project and the isolated player-only book all launched again from its payload. |

Captured output is in **tests/results/verification.txt**. The full resource time series is in **tests/results/soak-linux.json**. The build guide gives the commands. Ten minutes is a smoke soak. It cannot establish multi-day stability under real HD video, USB, Wi-Fi and projector load.

## Physical and release acceptance still required

| Test bench | Procedure and pass condition |
| --- | --- |
| Clean Ubuntu and Windows | Start on fresh supported OS images. Install using the .deb or Windows setup, take the computer offline and run all thirteen projects. Check graphics driver, video/audio, Indic text input, touch and multi-monitor placement. Windows binaries were not executed here. |
| Arduino board | Flash the sample after board identification. Vary A0, rotate the encoder, press the switch, arm and observe the LED. Disconnect USB during an active command, power-cycle and reconnect. The real output must stay inactive until a fresh deliberate arm. |
| ESP32 and Mosquitto | Isolate the wireless LAN from the internet. Commission accounts and wiring. Exercise the LED and servo inside site-specific bounds. Measure fail-safe timing for controller loss, broker loss, Wi-Fi loss and MCU reset. |
| Projector installation | Measure radius/height/throw, physically identify projectors, project the grid and align every corner and seam. Inspect polar gaps, image direction, brightness, optical black level and shadows. Save profiles, restart and repeat. |
| Physical book and camera | Print supplied markers. Test page corners, ambient light, occlusion, curved paper and lost/ambiguous detection. Confirm manual page selection always remains available. Optical calibration is unverified. |
| Continuous operation and power cut | Run the supplied eight-hour test and a multi-day pilot with actual content and signal rates. Interrupt power during playback, update and save operations. Confirm rollback, operator control and cold-boot disarming with instruments at the output. |

Native Windows installation, physical MCU and projector verification, real audio levels, a fresh Ubuntu installation and extended museum-floor stability are outstanding.

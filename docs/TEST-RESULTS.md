# Release verification 0.2.0

The tests below ran on x86-64 Linux with Godot 4.6.3. The render tests used Mesa llvmpipe and Xorg. The audience clients ran in genuine headless Chromium with independent browser storage. No physical microcontroller, webcam or projector was attached to this machine.

| Executed test | Observed result |
| --- | --- |
| Core project and rule suite | 12 checks passed. |
| Offline integration | 113 checks passed with IPv4 and IPv6 socket creation denied. All 14 examples round-tripped through packaging. Studio applied a measured planar report, undid the change and rejected a wrong-size report. |
| Native display integration | 115 checks passed on two X11 virtual heads, 1280 × 720 and 1024 × 768. All 14 example projects launched. The UV-mapped OBJ test rendered sampled exhibit content on the actual mesh. |
| Browser contest | The host edited a deck. Two independently stored clients joined at phone viewport sizes, one with a Bengali name. The browser-displayed QR decoded to the actual room URL. The test submitted, reloaded a client, moderated and upvoted a question, paused/resumed, revealed, ranked, advanced to multiple-answer play, finished and downloaded the four expected CSV rows. Zero JavaScript exceptions. |
| Concurrent room | 64 independent HTTP participants joined and submitted over loopback. All 64 answers counted exactly once. The fixed-clock test produced 64,000 team points. Idempotent retries, stale rounds, protected host actions, ties and restart recovery had separate regression tests. |
| Isolated contest network | A host and a separate participant process exchanged real TCP requests through two private IPv4 addresses in a disposable Linux network namespace with no default route. The participant joined, scored and read the ranking. Operator access was refused on the audience listener. Both addresses were assigned to the local loopback device. Venue Wi-Fi and phones require a site check. |
| Native scoreboard | The standalone Godot Player polled the live server, rendered its join QR and moved through lobby, open round, reveal and standings. Readback from the output confirmed rendered content. |
| Structured-light calibration | Full integer decoding tested on a 131 × 69 raster. Separate spatial tiles and separately generated dot captures were held out at five resolutions, including a separate native-size fixture with independently generated stripe and dot images at Full HD and UHD. The runner rejected moved-camera marks, dark/unsupported regions, reversed bit planes, missing independent checks, changing camera resolution and invalid corner order. |
| Metric pose and photometry | A surveyed synthetic 3D fixture gave 0.0920 px held-out p95 and a 1.14 mm projector-centre error. A known luminance response was recovered, and bad withheld readings were rejected. A separate synthetic physical-target record detected a deliberate 3 mm shift. |
| Actual rendered calibration | 17 native GPU-pipeline rasters and 8,523 independently evaluated RGB probes. Cases covered perspective, mesh, mask, gain, gamma, black lift, non-linear overlap, rotated sphere, cylinder height and wrap, fisheye and all six cubemap faces. Largest channel deviation was 1.02 on a 0–255 scale. The summed overlap’s maximum error was 0.60/255. |
| Additional hardware paths | Authenticated Mosquitto 2.0.18 and Paho exchanged real broker traffic with a native C++ fixture running the shared firmware endpoint. An input of 72 reached the gateway, an armed indicator command returned feedback of 1, and loss of the broker disarmed the link. Actual UDP ArtDMX and E1.31 packets exercised limits and blackout. A separate TCP responder verified a Modbus holding-register read. USB serial was exercised through an OS pseudo-terminal. |
| Board-target firmware compilation | Arduino CLI 1.3.1 compiled the complete shipped sketches for the Uno, classic Nano, Mega 2560 and classic ESP32 Dev Module. AVR 1.8.6 produced 7,402 / 7,402 / 8,798 flash bytes. ESP32 3.1.3 with PubSubClient 2.8 and ESP32Servo 3.0.6 produced 902,528 flash bytes and 46,228 static RAM bytes. Physical flashing and actuation still require the boards. |
| Python integration tests | 46 tests passed, including participant race conditions, independent self-paced progression, live poll privacy, slide imports, protocol checks and numerical calibration. |
| Stability observation | Two-output mixed exhibit ran headless for 1,802.8 seconds and processed 53,514 sensor events. First and final post-warmup readings showed a change of 0 KiB RSS and 0 file descriptors. The full time series is included. |

## Synthetic projector measurements

Each row used a distinct synthetic camera warp with resampling, sensor noise and finite contrast. Each independent dot statistic comes from 20 separately rendered observations.

| Projector raster | Maximum four-corner location error | Spatial holdout p95 | Independent dots p95 |
| --- | ---: | ---: | ---: |
| 193 × 127 | 0.0900 px | 0.4737 px | 0.2942 px |
| 257 × 149 | 0.0184 px | 0.4752 px | 0.2489 px |
| 109 × 163 | 0.0078 px | 0.4742 px | 0.1720 px |
| 1920 × 1080 | 0.0769 px | 0.4816 px | 0.1865 px |
| 3840 × 2160 | 0.0149 px | 0.4784 px | 0.4751 px |

The two larger fixtures used different camera and projector rasters. They applied spatially varying illumination, subpixel perspective resampling and sensor noise. The independently implemented producer generated its own stripe runs and check spots.

## Installation and field status

A fresh Ubuntu 24.04.5 amd64 userspace installed the .deb with dpkg and passed a package database audit. Its installed player opened all fourteen examples headless. The installed Studio and Player launchers also created native X11 windows. This was an Ubuntu userland running on the Linux host kernel and an external X server. See **tests/results/package-0.2.txt**. The official Windows engine archive passed its published SHA-512 check. The embedded Windows CPython ZIP is pinned by its release-build digest. The extracted Windows installer payload passed a 7-Zip integrity check and byte-for-byte comparison of all 183 packaged files. Native Windows installation and playback await a Windows system. Wine 9 in the Linux test container aborted during its initial interpreter startup, so no Windows execution pass was recorded.

Real Arduino/ESP32 electrical operation, isolated Wi-Fi reliability, USB reconnects, hardware timing, camera/projector focus, surface measurements, true genlock, power interruption and multi-day operation require suitable physical equipment. The commissioning program records measured millimetre residuals against a site-defined limit. It does not turn a synthetic fixture into physical verification. The [field instructions](CALIBRATION.md) describe the required inputs.

Detailed output is in **tests/results/verification-0.2.txt**. Earlier evidence is preserved in [the 0.1 report](TEST-RESULTS-0.1.md). The [capability matrix](CAPABILITIES.md) lists the remaining software scope. The [build guide](BUILD.md) gives reproducible commands.

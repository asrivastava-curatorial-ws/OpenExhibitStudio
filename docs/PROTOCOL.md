# Device protocol v1

## Local client and gateway

The gateway accepts UTF-8 JSON Lines on TCP **127.0.0.1:18440**. Every message ends in LF. Authenticate each connection with **{"op":"hello","v":1,"token":"…"}**. The server returns **{"op":"hello","v":1}** on success and closes an invalid connection. Send **{"op":"heartbeat"}** at least twice per second. The normal player sends it every 350 ms. A single authenticated controller can own the physical output lease.

| Client operation | Payload or effect |
| --- | --- |
| heartbeat | Returns device states and arming status. The owner renews its lease. |
| arm | Requires online output-capable endpoints and unlocked maintenance policy. Each device must confirm. |
| disarm | Clears the gateway lease, pending outputs and endpoint arming. |
| out | Example **{"op":"out","channel":"servo","value":90}**. Requires the owning live controller; out-of-bounds or excessive requests receive an error. |
| inject | Trusted local camera adapter with a whitelisted numeric page, motion_x, motion_y, presence or gesture channel. |

Server events include **state** with a devices dictionary and an armed flag, **input** with device/channel/value, and **error** with a message. Inputs can be numbers, short strings or Boolean values depending on the adapter. Every client receives accepted input. Physical output requests have one configured endpoint per channel. Put repeatable services on distinct local ports. The protocol does not execute remote commands, accept arbitrary file paths or flash firmware.

## Lightweight MCU frames

USB serial uses 115200 baud for the included firmware, with one ASCII frame per line. MQTT carries one identical frame per message on **oes/DEVICE/up** and **oes/DEVICE/down**. Boards consume down messages, and the gateway consumes up messages. The board parser accepts at most 95 characters per frame. The version, device ID, capability list, firmware revision, session token and command sequence are explicit. The token is a connection-scoped freshness value. Broker access control provides network authentication.

| Direction | Frame | Meaning |
| --- | --- | --- |
| Host → device | PROBE | Request boot/session identity |
| Device → host | BOOT boot_id | Board boot challenge |
| Host → device | OPEN 1 token boot_id | Establish a fresh 12-hex-character session and clear outputs |
| Device → host | HELLO 1 device_id token firmware capabilities | Advertise identity, firmware revision and comma-separated channel names |
| Host → device | HB token | Refresh the local watchdog |
| Device → host | ALIVE token | Confirm link health |
| Device → host | IN token channel value | Send an integer sensor value |
| Host → device | ARM token | Authorize bounded future output commands |
| Device → host | ARMED token | Confirm armed state |
| Host → device | OUT token sequence channel integer | Request one output change |
| Device → host | ACK token sequence | Confirm receipt, including repeated sequences |
| Device → host | ERR token reason | Reject an invalid command and disarm |
| Host → device | OFF | Immediately invoke the local safe-state callback |

Fresh sessions start with sequence zero and outputs inactive. Outgoing commands increment the sequence. The endpoint acknowledges old sequences without repeating the physical operation. A watchdog expiry changes the boot challenge and invalidates the prior token. A link failure or stale output acknowledgement clears the host lease. The supplied sketches do not remotely reassign pins. Physical pin changes and fail-safe semantics require local configuration or a deliberate firmware update.

## Transport coverage

The gateway implements USB serial, ASCII, CSV, JSON Lines, the compact v1 frames, Firmata input reports, MQTT and single-scalar OSC over loopback UDP. The authenticated controller protocol uses TCP. The stand-alone clock uses authenticated UDP. WebSocket, arbitrary binary frame codecs, generic HTTP I/O, MIDI, USB HID, Modbus RTU/TCP, Art-Net and sACN require additional adapters in this release.

For a new adapter, produce typed channel samples through the input interface. Actuator adapters additionally need independent safe-state handling, endpoint watchdogs and acknowledgements. A generic text writer is insufficient for an actuator output.

The [0.2 field adapter guide](FIELD-IO.md) supplements the original controller and wiring instructions below.

# Physical computing

Hardware status for 0.3.0: the gateway, protocol adapters, block editor and firmware were exercised
with software fixtures, simulated serial devices and compilers. No physical board, sensor or actuator
was connected during the 0.3.0 tests ([TEST-RESULTS.md](TEST-RESULTS.md)). Commission every
installation on the bench before opening it to visitors.

## Quick start from Studio

Open **Hardware** in Studio's left rail.

1. **Try it without hardware.** Drag the virtual sliders or press **Pulse** to feed input channels.
   The lamps show what the exhibit would switch; **Arm virtual outputs** lets them light.
2. **Connect a board.** Under *Board or protocol* choose what is plugged in:
   - *Arduino Uno / Nano / Mega — OpenExhibit firmware* for the supplied sketch (firmware/ExhibitUno);
   - *Any Arduino or ESP32 sketch that prints “name value” lines* for your own sketch or one exported
     from the block editor;
   - *Arduino with StandardFirmata / ConfigurableFirmata* for stock Firmata.

   Plug the board in, press **Refresh**, pick its USB serial port and press **Start hardware service**.
   Studio writes the site configuration to `hardware/site.json` in its data folder
   (`~/.local/share/OpenExhibitStudio` on Linux, `%APPDATA%\OpenExhibitStudio` on Windows), starts
   the gateway on 127.0.0.1 with a fresh access token and connects to it. A “name value” sketch may
   report any input channel the exhibit uses.
3. **Arm outputs** only after checking the wiring. Outputs disarm after every disconnection, restart
   or unplug, and must be armed again.
4. **Firmware and wiring** holds the pin planner (**Board pins and components…**), the offline block
   editor, the wiring drawings and the raw channel definitions.

Network profiles (ESP32 over MQTT, OSC, Modbus TCP, Art-Net/sACN) start the same way once their
addresses and topics are filled in under gateway/profiles/. The Player and kiosks start the gateway
from the command line, as described below.

## Pin planner

**Board pins and components…** opens the pin planner. Select a board, click a pin, choose a
component, give its channel a name and save the assignment. The planner checks duplicate pins and
names and the supported analog or input-only pins. An AVR input plan can export a Firmata gateway
configuration. Check the site pinout and the serial port before connecting.

## Classic Arduino bench

The supplied sketch supports a classic 5 V Uno, Nano or Mega 2560. Its v1 device ID is **uno** on all three targets. Use the correct FQBN for the physical board. Potentiometer end terminals go to the board’s 5 V and GND, wiper to A0. D2 uses an internal pull-up with a momentary button to GND. D3 reads the encoder’s A edge by interrupt, D4 reads B. Use a 5 V-compatible, debounced or conditioned encoder for reliable counting. The only output is LED_BUILTIN. The firmware samples the dial at 10 Hz, debounces the push button and sends only changed encoder counts. [Official Uno pinout](https://content.arduino.cc/assets/Pinout-UNOrev3_latest.pdf)

1. Install Arduino CLI, the AVR core and any required USB driver on a setup computer. **python3 tools/firmware.py list** queries actual detected boards. **cores** and **libraries** show the installed toolchains. Use **--fqbn** for alternate Nano bootloaders. [Arduino CLI guide](https://arduino.github.io/arduino-cli/latest/getting-started/)
2. Compile with **python3 tools/firmware.py compile --board uno**. When you have positively identified the target, upload with **python3 tools/firmware.py upload --board uno --port /dev/ttyACM0**. Windows ports use names such as COM3. Compilation and upload can run offline after installing the board core and required libraries.
3. (Studio's **Start hardware service** does steps 3 and 4 for you.) For the Player or a kiosk, copy **gateway/profiles/uno.json**, set its port and run **python3 gateway/openexhibit_gateway.py --config your-uno.json**. The Linux POSIX serial adapter uses the standard library. Windows uses pyserial. **--list** discovers ports. Stable Linux by-id paths help reconnect the same board.
4. The gateway prints a local operator token if one was not supplied in OPENEXHIBIT_TOKEN. Enter it in Studio’s Hardware workspace and choose **Connect**. For the standalone player set OPENEXHIBIT_TOKEN and OPENEXHIBIT_OPERATOR_KEY before launch. Use F10 to arm from the operator panel. Project files carry neither credential.
5. Open **Build a signal**. A real dial should update its gauge and live plot. Press the push button to send the indicator request. The physical LED changes only after the gateway and firmware confirm arming. Disconnect USB and verify the visible device status, safe LED state and requirement to rearm after reconnection.

## ConfigurableFirmata and existing firmware

Install ConfigurableFirmata separately and upload a configuration that includes the analog and digital input features. Use **gateway/profiles/firmata.json**. Set its baud rate to the firmware’s actual value. This adapter subscribes to analog channels and digital input ports and can enable pull-ups. Version 0.2 also supports explicitly configured indicators on Firmata 2.5 or newer. Stock Firmata lacks the OES1 device-side watchdog. Use the [field adapter guide](FIELD-IO.md) for the supported output modes. [ConfigurableFirmata](https://github.com/firmata/ConfigurableFirmata)

For existing programs set **protocol** to **ascii**, **csv** or **jsonl** in a serial gateway device, provide its baud, port and allowed **inputs**. The accepted messages are **dial 72**, **dial,72**, or a line containing **{"channel":"dial","value":72}**. End each report with a newline. Several serial and MQTT devices can coexist in the same devices array. Duplicate endpoints or output channel names are rejected. CSV/ASCII accept numeric values. JSON Lines also accepts short text.

## ESP32 and local MQTT

The sketch targets a classic ESP32 DevKit. Install its ESP32 Arduino core, PubSubClient and ESP32Servo before going offline. Fill firmware/ExhibitESP32/settings.h with the isolated wireless LAN and broker credentials. The sample uses GPIO25 for a resistor-limited indicator, GPIO26 for a **servo control signal**, and GPIO27 as a pull-up input. Use a separate correctly rated servo supply and common signal ground. Check travel mechanically before arming, and narrow the limits to suit the mechanism. Detaching the servo removes pulses and does not guarantee holding torque. [Servo power guidance](https://docs.arduino.cc/learn/electronics/servo-motors/)

Use a Mosquitto broker on that LAN. Create distinct board and gateway accounts, with permissions limited to their device topics. A minimal site configuration follows. Replace the example address and file paths with addresses and readable password/ACL files on the broker host.

```conf
listener 1883 192.168.1.10
allow_anonymous false
password_file /etc/mosquitto/exhibit.passwd
acl_file /etc/mosquitto/exhibit.acl
persistence false
```

Create the first account with **mosquitto_passwd -c /etc/mosquitto/exhibit.passwd exhibit-gateway**; add **exhibit-board** with the same command without -c. Copy **gateway/mosquitto.acl** to the configured acl_file path. Set **host** in the ESP32 gateway profile to the same bound LAN address. Set OES_MQTT_PASSWORD in the gateway environment and install paho-mqtt 2.1.0. Firmware and gateway use exact up/down topics and publish unretained messages. A WPA-isolated commissioning network is assumed for this plaintext MQTT sketch. The host adapter accepts a CA file for TLS. Encrypted board-side transport requires a compatible WiFiClientSecure firmware variant. [Mosquitto access control](https://mosquitto.org/documentation/authentication-methods/)

## Firmware blocks and other components

**Open block editor (Blockly)** in Studio, or firmware/blockly/index.html in any desktop browser, creates an Arduino input sketch with genuine Blockly 12.5.1. Blockly is included in firmware/blockly/vendor, so the editor works offline without npm. Choose Uno, Nano or Mega, drag analog-input, push-button, switch or ultrasonic-distance blocks, give each a unique channel name and press **Export sketch (.ino)**. The sketch prints “name value” lines at 115200 baud; connect it with the *“name value” lines* profile (gateway/profiles/serial-text.json). The block editor covers classic AVR inputs; the ESP32 actuator example uses the supplied handwritten firmware. The compiler helper accepts **install-core --name** and **install-library --name** for deliberate package installation.

The planner’s component taxonomy includes switches, Hall/reed sensors, encoders, RFID/NFC, proximity, load/pressure, environmental sensors, displays, lighting and externally driven actuators. A named component is not a device driver. I²C, SPI, UART peripherals and driver-specific motor control require matching site firmware or another external controller. Use **docs/PLUGINS.md** for the input interface. Optional per-channel **scale**, **offset**, **alpha**, **epsilon**, **interval_ms** and **debounce_ms** implement linear calibration, exponential smoothing, deadband, rate limiting and stable-value filtering. Use debounce on discrete signals. Keep the analog sampling cadence in firmware.

## Webcam and book commissioning

Print **examples/07-physical-book/print-markers.svg** on matte white paper. Keep the white margin, mount one corresponding marker per spread outside the visitor artwork and in the webcam’s view, and leave only one marker visible. Install the optional **opencv-contrib-python** and **numpy** packages and use **python3 tools/vision.py book** with the loopback gateway token. Three consistent observations commit a page. Ambiguous or lost detections retain the last page. Arrow keys, touch navigation, a manually injected page number or another page sensor can take over.

For OpenCV’s ArUco DICT_4X4_50 family use **python3 tools/vision.py markers --out ./printed-markers** and **book --family aruco**. Motion mode estimates a frame-difference centroid. Presence mode reports motion occupancy. Face mode uses a local Haar cascade for face presence. It reports counts as presence and does not identify people. Each camera process accepts **--camera**, **--zone** and an optional floor **--homography**. The adapter keeps frames in memory. **--preview** is a local operator display.

For planar calibration collect four or more corresponding, non-collinear normalized camera and content points in JSON arrays named **camera** and **content**. Run **python3 tools/vision.py calibrate --pairs points.json --out calibration.json**, then supply that file with **--homography** to the motion adapter. This estimates the camera-to-interaction transform. Projector warp calibration remains independently adjustable. [OpenCV homography](https://docs.opencv.org/4.x/d9/dab/tutorial_homography.html)

## Output limits and fault behaviour

The v1 samples boot with outputs inactive. The gateway requires a fresh device identity handshake, a live controller lease, an explicit arm and an acknowledgement before output commands. A firmware heartbeat timeout of 1.2 seconds invokes the local fail-safe. Loss of controller heartbeat, device connection or command acknowledgement disarms all outputs. A maintenance configuration may set **lockout: true**. Per-channel bounds are checked both on the host and the supplied firmware. A disconnection, app restart or firmware reboot requires manual rearming.

The software stop is an operational command. Hazardous kinetic or mains equipment requires suitable drivers, electrical isolation, independent hardwired emergency stops, interlocks and specialist commissioning. GPIO must not power motors, relays, solenoids, bass shakers or mains loads directly. The included output tests cover a low-voltage indicator and a bounded hobby-servo signal. A stalled processor, severed cable, welded relay or gravity-loaded mechanism requires independent hardware protection.

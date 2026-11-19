# Field protocol adapters

Declare each device in the gateway JSON. The Studio hardware workspace connects to the existing local gateway. Named inputs feed ordinary When–If–Do rules. Outputs use its authenticated controller, arming and lockout controls.

| Transport or protocol | Configuration and supported operation |
| --- | --- |
| USB serial, TCP client, UDP receiver | ASCII, CSV, JSON Lines and fixed binary input. For TCP/UDP supply a local IPv4 `host` and `port`. UDP also requires the permitted sender `peer`. A TCP or serial binary stream starts on a frame boundary. A UDP datagram contains exactly one frame. |
| Binary / HID input reports | Supply `frame_bytes` and a `fields` map from input channel to zero-based `offset` and `type`. Types include u8, s8, u16le/be, s16le/be and f32le/be. HID also needs numeric USB `vendor` and `product` IDs and optional `serial_number`. |
| MIDI input | Install mido and a local RtMidi backend. Supply the exact input port name and `midi` mappings such as `{"dial":{"kind":"cc","number":7,"channel":0}}`. The adapter maps CC values and note on/off velocity. |
| Modbus TCP / RTU | Install pymodbus 3.11.4 and pyserial for RTU. Set `unit`, `interval` and `registers`. Each channel maps to a zero-based address and one of holding, input, coil or discrete. Use an explicit host and port for TCP, a serial port and baud rate for RTU. The adapter polls inputs. |
| Art-Net ArtDMX / sACN E1.31 | Unicast level inputs or a dedicated indicator-lighting output universe. Configure `host`, `peer`, UDP `port`, `universe` and named one-based `slots`. Independent input filters validate frame lengths, universes and sequence numbers. Use 6454 for Art-Net or 5568 for sACN where the receiver expects its standard port. |
| ConfigurableFirmata | Serial analog and digital inputs, plus digital and PWM indicator outputs on boards reporting Firmata 2.5 or newer. Choose supported pins for the actual board. The sample uses Uno D13 for an indicator and A0 for input. |
| MQTT / OES1 | Paho exchanges capability, heartbeat and acknowledged commands with the exhibit firmware over a local broker. Supply user credentials through the gateway configuration and environment. |

**Examples.** See `gateway/profiles/network-indicator.json`, `meter.json` and `firmata-indicator.json`. Network indicator output requires a dedicated universe, a stated receiver-loss blackout setting and explicit numeric limits. Each changed level is sent with an upper rate bound. The gateway sends zero levels on disarm or lease expiry. A UDP send gives no receiver acknowledgement. Configure and test the fixture’s own loss-of-signal blackout before connecting it. A raw lighting or Firmata receiver can hold its last value if the host loses power. These adapters are for indicator lighting. The OES1 firmware supplies a device-side watchdog for its supported controlled outputs.

The MIDI, HID and Modbus adapters above read inputs. Bidirectional protocol support, arbitrary serial framing, multicast sACN merging and RDM fixture discovery remain outside this release. The test report specifies which adapters saw actual network packets, software fixtures or physical devices.

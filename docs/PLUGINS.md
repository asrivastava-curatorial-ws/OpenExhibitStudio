# Extension interfaces

## Supply a scientific or physical input

An external program can send newline-delimited values over an existing serial connection. A JSON Lines adapter profile might be:

```json
{
  "devices": [{
    "id": "pendulum",
    "transport": "serial",
    "protocol": "jsonl",
    "port": "/dev/ttyACM0",
    "baud": 115200,
    "inputs": ["angle"]
  }]
}
```

Send **{"channel":"angle","value":18.5}** followed by LF. Add a When–If–Do rule for **input.angle**, choose **set**, target **angle_deg** and value **$value**. Bind a gauge to angle_deg or put **{angle_deg}°** in a text object. The same channel can drive an external plot or another view of a live scene.

For an external simulator already on the exhibit computer, use the OSC input gateway. See **gateway/profiles/osc.json**. Add an explicitly configured route such as **/pendulum/angle → angle**, and list the channel in inputs. Send an OSC message with one integer, float, string or Boolean. A small Python example with no external packages follows.

```python
import socket
import struct

def osc_string(value):
    data = value.encode("utf8") + b"\0"
    return data + bytes((-len(data)) % 4)

packet = osc_string("/pendulum/angle") + osc_string(",f") + struct.pack(">f", 18.5)
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
    sender.sendto(packet, ("127.0.0.1", 9000))
```

## Add a native component

1. Declare the kind in **app/core/project.gd** and the JSON Schema.
2. Supply a Godot Control in **app/core/stage.gd → component**. Return the node with a configured mouse filter and a useful keyboard focus policy.
3. Keep content in the object dictionary and transient state in the session. Read variable values in refresh. Use **session.dispatch(event,value,true)** for visitor input. Use **session.sensor(channel,value)** for sensor semantics and trace history.
4. Implement the needed authoring fields or picker in Studio. Rebuild the separate player and studio packs. Add a round-trip and a normal-entry-point test.

The renderer uses only registered component constructors. A project cannot load an arbitrary GDScript file. Source-level native extensions are deliberately installed by the developer and share the application process. Put independent simulators with their own dependencies in a separate process and use OSC or the typed input adapters.

## Bounded expressions and reusable logic

Enable **bounded math expressions** in global project settings to use declarative math trees as action values. A typical value is **{"fn":"mul","args":["$value",0.1]}**. Supported functions are add, sub, mul, div, min, max, sin, cos, sqrt, abs, length, at, and, or and not. Arguments can reference a variable or the current event. Trees are limited to eight levels and two arguments per function. There is no operating-system, network, file or language-eval primitive. Variables can contain JSON arrays. Append/clear actions support capped collections. The graph’s emit action calls shared event rules. State machines can be expressed with a state variable, conditions and transitions. There is no separate statechart compiler.

For a site transport, implement **SerialAdapter** or **MQTTAdapter**’s contract from gateway/adapters.py: notify open and close, deliver bounded input bytes, support write and expose a stop event. Register it explicitly in the gateway configuration validator and adapter factory. Never activate unrecognized outputs on connection.

## Optional local content tools

**tools/local_media.py** connects only to loopback services or installed executables. Model downloads and their licences belong to the operator. Run **--help** and the relevant subcommand for arguments.

| Command | Local dependency | Result |
| --- | --- | --- |
| ollama | Ollama with an installed model on port 11434 | UTF-8 text for editing |
| comfy | ComfyUI on port 8188 and a trusted local API workflow JSON | First output image |
| speak | Piper executable and a voice model | WAV narration |
| transcribe | whisper.cpp whisper-cli and a compatible acoustic model | Transcript text |

These optional bridges are content preparation tools. The core editor and player have no AI dependency. Live service/model execution awaits testing with the operator’s chosen versions.

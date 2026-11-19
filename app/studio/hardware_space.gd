extends RefCounted
## Hardware workspace.
## 1. Try it without hardware: virtual sliders and buttons for every input channel, lamps for outputs.
## 2. Connect a board: pick a board profile and a port; Studio starts the local gateway service
##    with a fresh access token and connects to it — no tokens to copy, no terminal needed.
## 3. Firmware: the offline block editor and the exact arduino-cli commands.

const StyleKit := preload("res://core/skin.gd")
const Storage := preload("res://core/storage.gd")
const Tools := preload("res://core/tools.gd")
const RuleText := preload("res://studio/rule_text.gd")
const PinPlanner := preload("res://studio/pin_planner.gd")

const GATEWAY_PORT := 18440
## [profile file, label, needs a serial port]
const PROFILES := [
	["uno.json", "Arduino Uno / Nano / Mega — OpenExhibit firmware (USB)", true],
	["serial-text.json", "Any Arduino or ESP32 sketch that prints “name value” lines (USB)", true],
	["firmata.json", "Arduino with StandardFirmata / ConfigurableFirmata (USB)", true],
	["firmata-indicator.json", "Firmata board with an indicator LED output (USB)", true],
	["esp32.json", "ESP32 — OpenExhibit firmware over Wi-Fi (local MQTT broker)", false],
	["osc.json", "OSC sender — TouchOSC, Chataigne, Open Stage Control (UDP 9000)", false],
	["meter.json", "Modbus TCP meter or PLC", false],
	["network-indicator.json", "Network lighting — Art-Net / sACN indicator", false],
]

var host
var planner
var gateway_pid := -1
var ports := []
var profile_index := 0
var port_index := 0
var virtual_values := {}


func _init(owner) -> void:
	host = owner
	planner = PinPlanner.new(owner)  # kept alive: its dialogs call back into it


func shutdown() -> void:
	if host.gateway:
		host.gateway.close()
	Tools.stop(gateway_pid)
	gateway_pid = -1


func show(parent: Control) -> void:
	var box: VBoxContainer = host.logic._page(parent)
	host.logic._heading(
		box,
		"Hardware",
		"Test with virtual inputs first, then connect a real board. Outputs stay off until you arm them."
	)
	_virtual_section(box)
	box.add_child(HSeparator.new())
	_board_section(box)
	box.add_child(HSeparator.new())
	_firmware_section(box)
	box.add_child(HSeparator.new())
	host.logic.monitor(box)


# ----------------------------------------------------------------------------- virtual
func _virtual_section(box: VBoxContainer) -> void:
	box.add_child(StyleKit.label("Try it without hardware", 15, StyleKit.BLUE))
	var channels := RuleText.input_channels(host.p)
	if channels.is_empty():
		channels = ["dial", "button"]
		(
			box
			. add_child(
				(
					host
					. logic
					. _muted(
						"This exhibit declares no input channels yet; “dial” and “button” are offered for testing. Declare channels with Board pins and components."
					)
				)
			)
		)
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	for channel in channels:
		var name: String = channel
		grid.add_child(StyleKit.label(name, 13))
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1023
		slider.step = 1
		slider.custom_minimum_size.x = 260
		slider.value = virtual_values.get(name, 0)
		var readout := StyleKit.label(str(int(slider.value)), 12, StyleKit.MUTED)
		readout.custom_minimum_size.x = 50
		slider.value_changed.connect(func(v: float) -> void:
			virtual_values[name] = v
			readout.text = str(int(v))
			host.session.sensor(name, v)
		)
		grid.add_child(slider)
		grid.add_child(readout)
		grid.add_child(StyleKit.button("Pulse", func() -> void:
			host.session.sensor(name, 1)
			host.session.sensor(name, 0)
		))
	var outputs := RuleText.output_channels(host.p)
	var lamps := HFlowContainer.new()
	box.add_child(lamps)
	var arm := CheckButton.new()
	arm.text = "Arm virtual outputs"
	arm.button_pressed = host.session.virtual_armed
	arm.toggled.connect(func(on: bool) -> void:
		if on:
			host.session.virtual_armed = true
		else:
			host.session.disarm()
		_draw_lamps(lamps, outputs)
	)
	box.add_child(arm)
	_draw_lamps(lamps, outputs)
	host.work.watch(host.session.updated, lamps, func() -> void:
		if is_instance_valid(lamps):
			_draw_lamps(lamps, outputs)
	)


func _draw_lamps(lamps: HFlowContainer, outputs: Array) -> void:
	StyleKit.clear(lamps)
	if outputs.is_empty():
		lamps.add_child(StyleKit.label("No outputs are used by this exhibit.", 12, StyleKit.MUTED))
		return
	for channel in outputs:
		var value = host.session.virtual_outputs.get(channel)
		var on := _is_on(value)
		var lamp := StyleKit.label(
			("●  " if on else "○  ") + str(channel) + ("  = " + RuleText.value(value) if value != null else ""),
			13,
			Color("#3fb950") if on else StyleKit.MUTED
		)
		lamp.custom_minimum_size.x = 150
		lamps.add_child(lamp)


func _is_on(value) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	return value is String and value != ""


# ----------------------------------------------------------------------------- real board
func _board_section(box: VBoxContainer) -> void:
	box.add_child(StyleKit.label("Connect a board", 15, StyleKit.BLUE))
	var running := gateway_pid > 0 and OS.is_process_running(gateway_pid)
	if not running:
		gateway_pid = -1
	var profile := OptionButton.new()
	for entry in PROFILES:
		if FileAccess.file_exists(Tools.path("gateway/profiles/" + entry[0])):
			profile.add_item(entry[1])
			profile.set_item_metadata(profile.item_count - 1, entry)
	profile_index = clampi(profile_index, 0, maxi(0, profile.item_count - 1))
	profile.select(profile_index)
	profile.disabled = running
	profile.item_selected.connect(func(i: int) -> void:
		profile_index = i
		host.refresh()
	)
	box.add_child(StyleKit.label("Board or protocol", 12, StyleKit.MUTED))
	box.add_child(profile)
	var entry: Array = profile.get_item_metadata(profile_index) if profile.item_count else []
	var needs_port: bool = entry.size() > 0 and entry[2]
	if needs_port:
		var row := HBoxContainer.new()
		box.add_child(StyleKit.label("USB serial port", 12, StyleKit.MUTED))
		box.add_child(row)
		var port := OptionButton.new()
		port.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if ports.is_empty():
			port.add_item("No boards found — plug one in and press Refresh")
			port.disabled = true
		for item in ports:
			port.add_item("%s  (%s)" % [item.get("name", ""), item.get("path", "")])
		port_index = clampi(port_index, 0, maxi(0, ports.size() - 1))
		port.select(port_index)
		port.item_selected.connect(func(i: int) -> void: port_index = i)
		row.add_child(port)
		row.add_child(StyleKit.button("Refresh", _scan_ports))
	var actions := HFlowContainer.new()
	box.add_child(actions)
	if running:
		actions.add_child(StyleKit.button("Arm outputs", host.gateway.arm, true))
		actions.add_child(StyleKit.button("Disarm", host.gateway.disarm))
		actions.add_child(StyleKit.button("Stop hardware service", func() -> void:
			shutdown()
			host.refresh()
		))
	else:
		actions.add_child(StyleKit.button("Start hardware service", _start.bind(entry), true))
	var status := StyleKit.label(host.gateway.status, 12, StyleKit.TEXT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	host.work.watch(host.gateway.status_changed, status, func(text: String) -> void:
		if is_instance_valid(status):
			status.text = text
	)
	(
		box
		. add_child(
			(
				host
				. logic
				. _muted(
					"Outputs never switch on by themselves: they need Arm after every connection, restart or unplug. A software stop is not an emergency stop — wire one in hardware for anything that moves or carries mains power."
				)
			)
		)
	)
	if not needs_port and entry.size():
		box.add_child(
			host.logic._muted(
				"Network devices: edit gateway/profiles/%s for addresses and topics before starting." % entry[0]
			)
		)


func _scan_ports() -> void:
	var output := []
	var code := Tools.run("gateway/openexhibit_gateway.py", ["--list"], output)
	var parsed = JSON.parse_string("".join(output)) if code == 0 else null
	if parsed is Array:
		ports = parsed
		host.tell("Found %d serial port(s)." % ports.size())
	else:
		ports = []
		host.tell("Port scan failed. Run setup with --hardware (installs pyserial), then try again.")
	host.refresh()


func _start(entry: Array) -> void:
	if entry.is_empty():
		return
	var profile = Storage.json_at(Tools.path("gateway/profiles/" + entry[0]))
	if not profile is Dictionary:
		host.tell("Board profile missing: " + entry[0])
		return
	if entry[2]:
		if ports.is_empty():
			host.tell("Choose a serial port first (press Refresh after plugging the board in).")
			return
		for device in profile.get("devices", []):
			if device.get("transport") == "serial":
				device.port = ports[port_index].get("path", "")
	var config := Storage.absolute("user://hardware/site.json")
	var problem := Storage.write_json(config, profile)
	if problem:
		host.tell(problem)
		return
	var token := Tools.random_token()
	OS.set_environment("OPENEXHIBIT_TOKEN", token)
	gateway_pid = Tools.spawn("gateway/openexhibit_gateway.py", ["--config", config, "--port", str(GATEWAY_PORT)])
	if gateway_pid <= 0:
		host.tell("The hardware service could not start. Check that Python 3 is installed (bash setup.sh --hardware).")
		return
	host.tell("Hardware service starting…")
	await host.get_tree().create_timer(0.8).timeout
	host.gateway.connect_local(token, GATEWAY_PORT)
	host.refresh()


# ----------------------------------------------------------------------------- firmware
func _firmware_section(box: VBoxContainer) -> void:
	box.add_child(StyleKit.label("Firmware and wiring", 15, StyleKit.BLUE))
	var row := HFlowContainer.new()
	box.add_child(row)
	row.add_child(StyleKit.button("Board pins and components…", planner.open))
	row.add_child(StyleKit.button("Open block editor (Blockly)", func() -> void:
		var page := Tools.path("firmware/blockly/index.html")
		if FileAccess.file_exists(page):
			OS.shell_open(page)
		else:
			host.tell("Block editor not found: firmware/blockly/index.html")
	))
	row.add_child(StyleKit.button("Wiring drawings", func() -> void: OS.shell_open(Tools.path("docs/wiring.svg"))))
	row.add_child(StyleKit.button("Channel definitions (JSON)…", func() -> void:
		host.work.json_editor("Device channels", host.p.devices, func(value) -> void: host.p.devices = value)
	))
	box.add_child(
		host.logic._muted("Compile and upload with Arduino CLI (works offline once the board core is installed):")
	)
	var commands := TextEdit.new()
	commands.editable = false
	commands.custom_minimum_size.y = 96
	commands.text = "python3 tools/firmware.py list\npython3 tools/firmware.py compile --board uno\npython3 tools/firmware.py upload --board uno --port /dev/ttyACM0"
	box.add_child(commands)

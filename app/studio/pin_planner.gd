extends RefCounted
const StyleKit = preload("res://core/skin.gd")
const BOARDS = ["Uno classic", "Nano classic", "Mega 2560", "ESP32 DevKit (classic)"]
const COMPONENTS = [
	"Push button",
	"Switch",
	"Rotary encoder",
	"Potentiometer",
	"RFID / NFC reader",
	"PIR motion detector",
	"Ultrasonic rangefinder",
	"Time-of-flight sensor",
	"Reed switch",
	"Hall-effect sensor",
	"Load cell + amplifier",
	"Pressure sensor",
	"Accelerometer / gyro",
	"Temperature",
	"Humidity",
	"Light sensor",
	"Current sensor",
	"Voltage sensor",
	"Addressable LEDs",
	"RGB lighting",
	"DC motor + driver",
	"Stepper + driver",
	"Hobby servo",
	"Relay interface",
	"Fan + driver",
	"Solenoid + driver",
	"LCD / OLED",
	"DMX fixture",
	"Bass shaker + amplifier"
]
var host
var board = "Uno classic"
var pin = "A0"
var hardware
var selected_new = ""


func _init(h):
	host = h


func pins_for(name_: String) -> Array:
	var result = []
	if name_ == "ESP32 DevKit (classic)":
		for n in [13, 14, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 39]:
			result.append("GPIO" + str(n))
	else:
		for n in range(2, 54 if name_ == "Mega 2560" else 14):
			result.append("D" + str(n))
		for n in 16 if name_ == "Mega 2560" else 8 if name_ == "Nano classic" else 6:
			result.append("A" + str(n))
	return result


func open():
	var b = host.dialog("Board and component planner", 600, 620)
	var saved = host.p.extensions.get("pin_plan", {}) if host.p.has("extensions") else {}
	board = saved.get("board", board)
	var opt = host.choice(b, "Board profile", BOARDS, board)
	opt.item_selected.connect(func(i):
		board = BOARDS[i]
		pin = pins_for(board)[0]
		b.get_window().queue_free()
		open_board()
	)
	build(b, saved)


func open_board():
	var b = host.dialog("Board and component planner", 600, 620)
	var opt = host.choice(b, "Board profile", BOARDS, board)
	opt.item_selected.connect(func(i):
		board = BOARDS[i]
		pin = pins_for(board)[0]
		b.get_window().queue_free()
		open_board()
	)
	var saved = host.p.get("extensions", {}).get("pin_plan", {})
	build(b, saved if saved.get("board") == board else {})


func build(b, saved):
	var assigned = saved.get("pins", {})
	var msg = StyleKit.label("Select a pin", 13, StyleKit.MINT)
	b.add_child(msg)
	var grid = GridContainer.new()
	grid.columns = 6
	b.add_child(grid)
	for where in pins_for(board):
		grid.add_child(StyleKit.button(where, func():
			pin = where
			msg.text = where + "   /   " + str(assigned.get(where, {}).get("channel", "available"))
		, assigned.has(where)))
	var comp = host.choice(b, "Component", COMPONENTS)
	var mode = host.choice(
		b, "Channel direction / mode", ["digital input", "analog input", "output plan", "bus peripheral"]
	)
	var channel = host.field(b, "Logical channel", "dial")
	var status = StyleKit.label("", 12, StyleKit.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(status)
	b.add_child(StyleKit.button("Assign selected pin", func():
		var name_ = channel.text.strip_edges()
		var m = mode.get_item_text(mode.selected)
		if not name_.is_valid_identifier():
			status.text = "Use an identifier such as dial or visitor_button."
			return
		if assigned.has(pin):
			status.text = "Pin already in use. Remove its assignment first."
			return
		for item in assigned.values():
			if item.channel == name_:
				status.text = "That logical channel already exists."
				return
		if (
			board.begins_with("ESP32")
			and pin in ["GPIO34", "GPIO35", "GPIO36", "GPIO39"]
			and m in ["output plan", "bus peripheral"]
		):
			status.text = "This classic ESP32 pin is input-only."
			return
		if (
			m == "analog input"
			and not (
				pin.begins_with("A")
				or (
					board.begins_with("ESP32")
					and pin in ["GPIO32", "GPIO33", "GPIO34", "GPIO35", "GPIO36", "GPIO39"]
				)
			)
		):
			status.text = "Select an analog-capable input (ADC1 on wireless ESP32)."
			return
		var newpins = assigned.duplicate(true)
		newpins[pin] = {"component": comp.get_item_text(comp.selected), "mode": m, "channel": name_}
		b.get_window().queue_free()
		host.mutate("Save pin assignment", func():
			if not host.p.has("extensions"):
				host.p.extensions = {}
			host.p.extensions.pin_plan = {"board": board, "pins": newpins}
		)
	, true))
	b.add_child(StyleKit.button("Remove selected assignment", func():
		if not assigned.has(pin):
			return
		b.get_window().queue_free()
		host.mutate("Remove pin assignment", func(): host.p.extensions.pin_plan.pins.erase(pin))
	))
	var info = (
		StyleKit
		. label(
			"Pin plans document the installation. Export AVR input pins below for ConfigurableFirmata. Bus devices and actuators need a supported site firmware adapter.",
			12,
			StyleKit.MUTED
		)
	)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(info)
	if not board.begins_with("ESP32"):
		b.add_child(StyleKit.button("Export Firmata input configuration…", func():
			var active = []
			var names = []
			for where in assigned:
				var item = assigned[where]
				if item.mode == "analog input" or (item.mode == "digital input" and where.begins_with("D")):
					active.append(
						{
							"pin": int(where.substr(1)),
							"mode": "analog" if item.mode == "analog input" else "digital",
							"channel": item.channel,
							"pullup": item.component in ["Push button", "Switch", "Reed switch"],
							"invert": item.component in ["Push button", "Switch", "Reed switch"]
						}
					)
					names.append(item.channel)
			if active.is_empty():
				status.text = "Assign a supported analog or digital input first."
				return
			b.get_window().queue_free()
			host.file_dialog("Save Firmata gateway configuration", FileDialog.FILE_MODE_SAVE_FILE, ["*.json"], func(path):
				var result = host.io.write_json(
					path,
					{
						"devices":
						[
							{
								"id": "firmata_input",
								"transport": "serial",
								"protocol": "firmata",
								"port": "COM3" if OS.get_name() == "Windows" else "/dev/ttyACM0",
								"baud": 57600,
								"inputs": names,
								"pins": active
							}
						]
					}
				)
				host.tell(
					(
						result
						if result
						else "Saved gateway configuration · set its serial port for the installation."
					)
				)
			)
		))

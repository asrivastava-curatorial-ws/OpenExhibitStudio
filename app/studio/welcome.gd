extends RefCounted
## Start screen: blank exhibit, templates (the bundled examples, opened as copies), and recent
## exhibits. Shown when Studio starts without a project and from File → Start screen.

const StyleKit := preload("res://core/skin.gd")
const Paths := preload("res://core/paths.gd")

## [example folder, title, what it shows]
const TEMPLATES := [
	["START WITH A TEMPLATE", ""],
	["01-solar", "Touchscreen kiosk", "Buttons update a live solar-system model and fact card."],
	["06-digital-book", "Digital flipbook", "Pages with swipe, arrow-key and on-screen navigation."],
	["15-live-show", "Live audience talk", "AhaSlides-style polls, quiz, word cloud, Q&A and spinner on phones."],
	["13-shows", "Timed video show", "Two films sequenced with fades and slides on a timeline."],
	["08-arduino", "Arduino exhibit", "A dial and button on a board drive a gauge, chart and lamp."],
	["PROJECTION", ""],
	["02-panorama", "Three-projector panorama", "Edge-blended linear panorama with alignment grids."],
	["03-earth", "Earth on a sphere", "Four projectors map an equirectangular globe; a rotary encoder spins it."],
	["04-cyclorama", "Cylindrical cyclorama", "Fixed-height cylinder with multilingual text."],
	["05-room", "Immersive room", "Independent floor, wall and ceiling outputs."],
	["07-physical-book", "Projected physical book", "Page detection with markers, sensors or manual fallback."],
	["MORE EXAMPLES", ""],
	["09-esp32", "ESP32 light and servo", "Wireless board over a local MQTT broker."],
	["10-floor", "Interactive floor", "Webcam motion moves a particle field."],
	["11-mixed", "Mixed installation", "One input updates a kiosk, a projection and two devices."],
	["12-postcards", "Visitor drawing wall", "Visitors draw on a kiosk; drawings appear on the projection."],
	["14-live-quiz", "Quiz contest scoreboard", "Team quiz with a projection-mapped live scoreboard."],
]


static func open(host) -> void:
	var box: VBoxContainer = host.dialog("Welcome to OpenExhibit Studio", 860, 640)
	box.get_window().exclusive = false
	box.add_child(
		_muted(
			"Build interactive exhibits, projection-mapped installations and live audience sessions — fully offline."
		)
	)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.7
	columns.add_child(left)
	var blank := StyleKit.button("+  Blank exhibit", _choose.bind(box, host.new_project), true)
	blank.alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(blank)
	var examples := Paths.examples()
	for entry in TEMPLATES:
		if entry[1] == "":
			left.add_child(_heading(entry[0]))
			continue
		var project_path: String = examples.path_join(entry[0]).path_join("project.oes.json") if examples else ""
		if not FileAccess.file_exists(project_path):
			continue
		left.add_child(_card(entry[1], entry[2], _choose.bind(box, host.request_open.bind(project_path))))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(_heading("OPEN"))
	var open_button := StyleKit.button("Open an exhibit or .oex package…", _choose.bind(box, host.open_project))
	open_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(open_button)
	right.add_child(_heading("RECENT"))
	var recent: Array = host.recent_projects()
	if recent.is_empty():
		right.add_child(_muted("Exhibits you save will appear here."))
	for path in recent.slice(0, 8):
		right.add_child(
			_card(str(path).get_base_dir().get_file(), str(path), _choose.bind(box, host.request_open.bind(path)))
		)
	right.add_child(_heading("TIP"))
	right.add_child(
		_muted(
			"Templates open as read-only examples. Use File → Save as and pick an empty folder to make your own copy."
		)
	)

	var show := CheckBox.new()
	show.text = "Show this screen when Studio starts"
	show.button_pressed = bool(host.pref("welcome", true))
	show.toggled.connect(func(on: bool) -> void: host.set_pref("welcome", on))
	box.add_child(show)


static func _choose(box: Control, action: Callable) -> void:
	box.get_window().queue_free()
	action.call()


static func _heading(text: String) -> Label:
	var label := StyleKit.label(text, 11, StyleKit.MUTED)
	label.custom_minimum_size.y = 28
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label


static func _muted(text: String) -> Label:
	var label := StyleKit.label(text, 12, StyleKit.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func _card(title: String, detail: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title + "\n" + detail
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 52
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	return button

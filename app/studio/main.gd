extends Control
## OpenExhibit Studio — the authoring shell.
##
## Owns the open project dictionary, the undo history and the current selection, and lays out
## the window: menu bar · workspace rail · explorer (scenes + layers) · centre workspace ·
## inspector · status bar. Workspaces live in their own scripts and edit the project only
## through [method mutate], so every change is validated, undoable and autosaved.

const Model := preload("res://core/project.gd")
const Storage := preload("res://core/storage.gd")
const Session := preload("res://core/session.gd")
const Paths := preload("res://core/paths.gd")
const StyleKit := preload("res://core/skin.gd")
const Tools := preload("res://core/tools.gd")
const Gateway := preload("res://core/gateway_client.gd")
const Canvas := preload("res://studio/canvas.gd")
const Workspaces := preload("res://studio/workspaces.gd")
const LogicSpace := preload("res://studio/logic_space.gd")
const HardwareSpace := preload("res://studio/hardware_space.gd")
const AudienceSpace := preload("res://studio/audience_space.gd")
const RuleText := preload("res://studio/rule_text.gd")
const Welcome := preload("res://studio/welcome.gd")

## Workspace keys in rail order. Keys are stable identifiers; labels are what people see.
const SPACES := [
	"Canvas",
	"Flipbook",
	"Science",
	"Assets",
	"Logic",
	"Timeline",
	"Hardware",
	"Installation",
	"3D scene",
	"Mapping",
	"Test",
	"Live audience",
	"Deployment",
]
const SPACE_INFO := {
	"Canvas": ["▦", "Screens", "Design what visitors see and touch", "DESIGN"],
	"Flipbook": ["▤", "Flipbook", "Turn scenes into book pages", "DESIGN"],
	"Science": ["∿", "Science", "Add simulations, charts and models", "DESIGN"],
	"Assets": ["▧", "Media", "Images, sound, video and 3D files in this exhibit", "DESIGN"],
	"Logic": ["⑂", "Interactions", "When something happens, do something", "BEHAVIOUR"],
	"Timeline": ["▷", "Timeline", "Timed shows, cues and animation", "BEHAVIOUR"],
	"Hardware": ["⊞", "Hardware", "Sensors, buttons, lights and motors", "BEHAVIOUR"],
	"Installation": ["⌂", "Installation", "Screens, projectors and surfaces in the room", "INSTALL"],
	"3D scene": ["◇", "3D view", "Orbit the installation in 3D", "INSTALL"],
	"Mapping": ["▱", "Projection", "Warp, blend and calibrate projector outputs", "INSTALL"],
	"Test": ["◎", "Try it", "Use the exhibit as a visitor (F5)", "RUN"],
	"Live audience": ["◉", "Live audience", "Polls, quizzes, word clouds and Q&A on phones", "RUN"],
	"Deployment": ["⇧", "Publish", "Package the exhibit and run it on a player", "RUN"],
}
## Component kinds offered in the Add dialog, grouped, with plain names.
const KIND_GROUPS := [
	["Basics", [["text", "Text"], ["button", "Button"], ["panel", "Panel / shape"], ["image", "Image"]]],
	["Media", [["video", "Video (.ogv)"], ["audio", "Sound"], ["model", "3D model"]]],
	["Visitor input", [["slider", "Slider"], ["entry", "Text box"], ["drawing", "Drawing pad"]]],
	[
		"Data and science",
		[
			["gauge", "Gauge"],
			["plot", "Live chart"],
			["orbit", "Solar system"],
			["particles", "Particle field"],
			["fractal", "Fractal"],
			["grid", "Grid pattern"]
		]
	],
	["Live audience", [["contest", "Live audience board"]]],
]
const PRESS_ACTIONS := [
	["", "Nothing (or use Interactions)"],
	["goto", "Go to scene"],
	["set", "Set variable"],
	["add", "Add to variable"],
	["play", "Play timeline"],
	["output", "Send to device output"],
	["next", "Next page"],
	["prev", "Previous page"],
	["reset", "Reset the visit"],
]
const RECENT_FILE := "user://recent.json"
const PREFS_FILE := "user://studio.cfg"

var p: Dictionary
var io := Storage.new()
var session
var gateway
var work
var logic
var hardware
var audience
var edit_scene := ""
var selected := ""
var space := "Canvas"
var dirty := false
var undo_stack := []
var redo_stack := []
var canvas
var center: VBoxContainer
var inspector: VBoxContainer
var expanded: Window
var snap_on := true
var msg := ""
var next_save := 0
var journal := ""
var booted := false

var _status: Label
var _title_label: Label
var _mode_label: Label
var _header: Label
var _scenes: ItemList
var _layers: ItemList
var _right_scroll: ScrollContainer
var _rail_buttons := {}
var _last_edit_label := ""
var _last_edit_time := 0
var _touch_start := Vector2.ZERO
var _recent_menu: PopupMenu


# ----------------------------------------------------------------------------- lifecycle
func _ready() -> void:
	theme = StyleKit.theme()
	get_window().min_size = Vector2i(1024, 640)
	get_window().title = "OpenExhibit Studio"
	get_tree().set_auto_accept_quit(false)
	gateway = Gateway.new()
	add_child(gateway)
	work = Workspaces.new(self)
	logic = LogicSpace.new(self)
	hardware = HardwareSpace.new(self)
	audience = AudienceSpace.new(self)
	get_viewport().files_dropped.connect(_on_files_dropped)

	var source := Paths.first_project()
	var loaded := io.open(source) if source and FileAccess.file_exists(source) else {}
	var initial_error: String = io.error
	if loaded.is_empty():
		p = Model.fresh()
		_new_working_folder()
	else:
		p = loaded
		_remember(io.path)
	edit_scene = p.start
	journal = Storage.absolute("user://recovery/last.json")
	_build_shell()
	reset_session()
	refresh()
	booted = true
	if initial_error:
		tell(initial_error)
	if not _offer_recovery() and _show_welcome_at_start():
		Welcome.open(self)


func _new_working_folder() -> void:
	io.folder = Storage.absolute("user://working/" + Model.uid("draft"))
	DirAccess.make_dir_recursive_absolute(io.folder)


func _show_welcome_at_start() -> bool:
	if DisplayServer.get_name() == "headless" or "--no-welcome" in OS.get_cmdline_user_args():
		return false
	if Paths.option("--project"):
		return false
	return bool(pref("welcome", true))


func _offer_recovery() -> bool:
	var recovery = Storage.json_at(journal)
	if not (recovery is Dictionary and recovery.has("project") and Model.validate(recovery.project) == ""):
		return false
	var box := ConfirmationDialog.new()
	add_child(box)
	box.title = "Restore unsaved exhibit?"
	box.dialog_text = "Studio closed with unsaved edits to “%s”. Restore them?" % recovery.project.title
	box.ok_button_text = "Restore"
	box.cancel_button_text = "Discard"
	box.confirmed.connect(_restore_recovery.bind(recovery))
	box.canceled.connect(DirAccess.remove_absolute.bind(journal))
	box.popup_centered()
	return true


func _restore_recovery(recovery: Dictionary) -> void:
	p = recovery.project
	io.folder = recovery.get("folder", "")
	io.path = recovery.get("path", "")
	io.revision = recovery.get("revision", "")
	io.packaged = recovery.get("packaged", false)
	edit_scene = p.start
	selected = ""
	dirty = true
	reset_session()
	refresh()
	tell("Recovered unsaved edits. Save to keep them.")


func reset_session() -> void:
	session = Session.new(p)
	gateway.attach(session)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and booted:
		if dirty:
			_ask_save_before_quit()
		else:
			_quit()


func _ask_save_before_quit() -> void:
	var box := ConfirmationDialog.new()
	add_child(box)
	box.title = "Save changes?"
	box.dialog_text = "“%s” has unsaved changes." % p.title
	box.ok_button_text = "Save"
	box.cancel_button_text = "Cancel"
	box.add_button("Don't save", true, "discard")
	box.confirmed.connect(func() -> void:
		save()
		if not dirty:
			_quit()
	)
	box.custom_action.connect(func(_action: StringName) -> void:
		if FileAccess.file_exists(journal):
			DirAccess.remove_absolute(journal)
		_quit()
	)
	box.popup_centered()


func _quit() -> void:
	audience.shutdown()
	hardware.shutdown()
	get_tree().quit()


# ----------------------------------------------------------------------------- shell layout
func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = StyleKit.BG
	add_child(background)
	StyleKit.fill(background)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	StyleKit.fill(root)
	root.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	StyleKit.stretch(body)
	root.add_child(body)
	body.add_child(_build_rail())

	var outer := HSplitContainer.new()
	StyleKit.stretch(outer)
	body.add_child(outer)
	outer.add_child(_build_explorer())
	var inner := HSplitContainer.new()
	StyleKit.stretch(inner)
	outer.add_child(inner)
	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 0)
	StyleKit.stretch(middle)
	inner.add_child(middle)
	middle.add_child(_build_breadcrumb())
	center = VBoxContainer.new()
	StyleKit.stretch(center)
	middle.add_child(center)
	_right_scroll = ScrollContainer.new()
	_right_scroll.custom_minimum_size.x = 290
	_right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(_right_scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = SIZE_EXPAND_FILL
	_right_scroll.add_child(inspector)
	root.add_child(_build_status_bar())


func _build_top_bar() -> Control:
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.PANEL, StyleKit.LINE, 0, 7))
	var bar := HBoxContainer.new()
	top.add_child(bar)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/icon.svg")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.custom_minimum_size = Vector2(24, 24)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bar.add_child(logo)
	bar.add_child(StyleKit.label("OpenExhibit", 15, Color.WHITE))
	bar.add_child(StyleKit.label("Studio", 13, StyleKit.BLUE))
	bar.add_child(VSeparator.new())

	var file := _menu(bar, "File")
	_menu_item(file, "New exhibit", new_project, KEY_MASK_CTRL | KEY_N)
	_menu_item(file, "Open…", open_project, KEY_MASK_CTRL | KEY_O)
	_recent_menu = PopupMenu.new()
	_recent_menu.id_pressed.connect(_open_recent)
	file.add_submenu_node_item("Open recent", _recent_menu)
	_menu_item(file, "Start screen and templates…", Welcome.open.bind(self))
	file.add_separator()
	_menu_item(file, "Save", save, KEY_MASK_CTRL | KEY_S)
	_menu_item(file, "Save as…", save_as, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	_menu_item(file, "Export package (.oex)…", pack_project, KEY_MASK_CTRL | KEY_E)
	file.add_separator()
	_menu_item(file, "Quit", func() -> void: _notification(NOTIFICATION_WM_CLOSE_REQUEST), KEY_MASK_CTRL | KEY_Q)
	_refresh_recent_menu()

	var edit := _menu(bar, "Edit")
	_menu_item(edit, "Undo", undo, KEY_MASK_CTRL | KEY_Z)
	_menu_item(edit, "Redo", redo, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_Z)
	edit.add_separator()
	_menu_item(edit, "Duplicate layer", duplicate_object, KEY_MASK_CTRL | KEY_D)
	_menu_item(edit, "Delete layer", delete_object, KEY_DELETE)
	edit.add_separator()
	_menu_item(edit, "Command palette…", commands, KEY_MASK_CTRL | KEY_P)

	var view := _menu(bar, "View")
	_menu_item(view, "Try it as a visitor", toggle_test, KEY_F5)
	_menu_item(view, "Exhibit settings…", settings_dialog)
	_menu_item(view, "Detach inspector", float_inspector)

	var help := _menu(bar, "Help")
	_menu_item(help, "Quick guide", guide)
	_menu_item(help, "User manual (opens in browser)", _open_doc.bind("docs/USER-MANUAL.md"))
	_menu_item(help, "What works and what doesn't", _open_doc.bind("docs/CAPABILITIES.md"))

	_title_label = StyleKit.label("", 12, StyleKit.MUTED)
	_title_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(_title_label)
	bar.add_child(StyleKit.button("⌕  Commands", commands))
	bar.add_child(StyleKit.button("Save", save))
	bar.add_child(StyleKit.button("▶  Try it", toggle_test, true))
	return top


func _menu(parent: Control, caption: String) -> PopupMenu:
	var button := MenuButton.new()
	button.text = caption
	button.flat = true
	parent.add_child(button)
	var popup := button.get_popup()
	popup.id_pressed.connect(
		func(id: int) -> void: (popup.get_item_metadata(popup.get_item_index(id)) as Callable).call()
	)
	return popup


func _menu_item(popup: PopupMenu, caption: String, action: Callable, accel := 0) -> void:
	var id := popup.item_count
	popup.add_item(caption, id, accel)
	popup.set_item_metadata(popup.get_item_index(id), action)


func _build_rail() -> Control:
	var rail := PanelContainer.new()
	rail.add_theme_stylebox_override("panel", StyleKit.box(Color("#010409"), StyleKit.LINE, 0, 6))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	scroll.add_child(column)
	var group := ""
	for key in SPACES:
		var info: Array = SPACE_INFO[key]
		if info[3] != group:
			group = info[3]
			var heading := StyleKit.label(group, 10, StyleKit.MUTED)
			heading.custom_minimum_size.y = 26
			heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			column.add_child(heading)
		var button := StyleKit.button("%s  %s" % [info[0], info[1]], set_space.bind(key))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = info[2]
		button.custom_minimum_size = Vector2(150, 30)
		column.add_child(button)
		_rail_buttons[key] = button
	return rail


func _build_explorer() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 210
	panel.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.PANEL, Color.TRANSPARENT, 0, 9))
	var column := VBoxContainer.new()
	panel.add_child(column)

	column.add_child(_section_header("SCENES", "+", add_scene, "New scene"))
	_scenes = ItemList.new()
	_scenes.custom_minimum_size.y = 120
	_scenes.item_selected.connect(func(i: int) -> void:
		edit_scene = p.scenes[i].id
		selected = ""
		set_space("Canvas")
	)
	column.add_child(_scenes)
	var scene_tools := HBoxContainer.new()
	column.add_child(scene_tools)
	scene_tools.add_child(_tool_button("↑", move_scene.bind(-1), "Move scene earlier"))
	scene_tools.add_child(_tool_button("↓", move_scene.bind(1), "Move scene later"))
	scene_tools.add_child(_tool_button("⧉", duplicate_scene, "Duplicate scene"))
	scene_tools.add_child(_tool_button("🗑", delete_scene, "Delete scene"))

	column.add_child(HSeparator.new())
	column.add_child(_section_header("LAYERS", "+", add_menu, "Add a component"))
	_layers = ItemList.new()
	StyleKit.stretch(_layers)
	_layers.allow_reselect = true
	_layers.item_selected.connect(func(i: int) -> void: pick(str(_layers.get_item_metadata(i))))
	column.add_child(_layers)
	var layer_tools := HBoxContainer.new()
	column.add_child(layer_tools)
	layer_tools.add_child(_tool_button("↑", move_layer.bind(1), "Bring forward"))
	layer_tools.add_child(_tool_button("↓", move_layer.bind(-1), "Send backward"))
	layer_tools.add_child(_tool_button("⧉", duplicate_object, "Duplicate (Ctrl+D)"))
	layer_tools.add_child(_tool_button("🗑", delete_object, "Delete (Del)"))
	return panel


func _section_header(caption: String, symbol: String, action: Callable, hint: String) -> Control:
	var row := HBoxContainer.new()
	var label := StyleKit.label(caption, 11, StyleKit.MUTED)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_tool_button(symbol, action, hint))
	return row


func _tool_button(symbol: String, action: Callable, hint: String) -> Button:
	var button := StyleKit.button(symbol, action)
	button.tooltip_text = hint
	button.custom_minimum_size = Vector2(32, 28)
	return button


func _build_breadcrumb() -> Control:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.BG, StyleKit.LINE, 0, 7))
	var row := HBoxContainer.new()
	strip.add_child(row)
	_mode_label = StyleKit.label("", 13, StyleKit.BLUE)
	row.add_child(_mode_label)
	row.add_child(StyleKit.label("/", 13, StyleKit.MUTED))
	_header = StyleKit.label("", 13)
	_header.size_flags_horizontal = SIZE_EXPAND_FILL
	_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_header)
	row.add_child(StyleKit.button("+  Add component", add_menu))
	return strip


func _build_status_bar() -> Control:
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.PANEL, StyleKit.LINE, 0, 3))
	var row := HBoxContainer.new()
	bottom.add_child(row)
	_status = StyleKit.label("Ready", 12, StyleKit.MUTED)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_status)
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	row.add_child(
		StyleKit.label("OpenExhibit %s · Godot %s" % [version, Engine.get_version_info().string], 11, StyleKit.MUTED)
	)
	return bottom


# ----------------------------------------------------------------------------- refresh
## Rebuilds the explorer, centre workspace and (unless kept) the inspector from the project.
func refresh(keep_inspector := false) -> void:
	_scenes.clear()
	for i in p.scenes.size():
		var scene: Dictionary = p.scenes[i]
		_scenes.add_item(("★ " if scene.id == p.start else "   ") + str(scene.name))
		_scenes.set_item_tooltip(i, "First scene" if scene.id == p.start else scene.id)
		if scene.id == edit_scene:
			_scenes.select(i)
	_layers.clear()
	var objects: Array = scene_data().get("objects", [])
	for i in range(objects.size() - 1, -1, -1):
		var o: Dictionary = objects[i]
		var flags := ("  ◌" if o.get("hidden", false) else "") + ("  🔒" if o.get("locked", false) else "")
		_layers.add_item(str(o.get("name", o.id)) + flags)
		var index := _layers.item_count - 1
		_layers.set_item_metadata(index, o.id)
		_layers.set_item_tooltip(index, "%s · %s" % [_kind_label(o.kind), o.id])
		if o.id == selected:
			_layers.select(index)
	_header.text = str(scene_data().get("name", ""))
	_title_label.text = p.title + ("  ●" if dirty else "")
	get_window().title = p.title + (" *" if dirty else "") + " — OpenExhibit Studio"
	_mode_label.text = SPACE_INFO[space][1]
	for key in _rail_buttons:
		var active: bool = key == space
		_rail_buttons[key].add_theme_stylebox_override(
			"normal",
			StyleKit.box(
				Color("#1f2a37") if active else Color.TRANSPARENT, StyleKit.BLUE if active else Color.TRANSPARENT, 5, 5
			)
		)
		_rail_buttons[key].add_theme_color_override("font_color", Color.WHITE if active else StyleKit.MUTED)

	StyleKit.clear(center)
	canvas = null
	if space in ["Canvas", "Test"]:
		_build_canvas()
	elif space == "Logic":
		logic.show(center)
	elif space == "Hardware":
		hardware.show(center)
	elif space == "Live audience":
		audience.show(center)
	else:
		work.show_space(space, center)
	if not keep_inspector:
		inspect()
	tell(msg if msg else "Ready")


func _build_canvas() -> void:
	canvas = Canvas.new()
	StyleKit.stretch(canvas)
	center.add_child(canvas)
	canvas.snap = snap_on
	canvas.picked.connect(pick)
	canvas.transformed.connect(_on_canvas_transform)
	canvas.configure(session, io.folder, edit_scene, selected, space == "Test")
	var tools := HBoxContainer.new()
	center.add_child(tools)
	tools.add_child(StyleKit.button("−", _zoom.bind(1.0 / 1.2)))
	tools.add_child(StyleKit.button("Fit", _zoom.bind(0.0)))
	tools.add_child(StyleKit.button("+", _zoom.bind(1.2)))
	var snapping := CheckButton.new()
	snapping.text = "Snap to 8 px (hold Alt for 1 px)"
	snapping.button_pressed = snap_on
	snapping.toggled.connect(func(on: bool) -> void:
		snap_on = on
		canvas.snap = on
	)
	tools.add_child(snapping)
	tools.add_child(StyleKit.label("%d × %d px" % p.canvas, 12, StyleKit.MUTED))
	if space == "Test":
		var hint := StyleKit.label(
			"Visitor mode — buttons work, idle reset runs. F5 returns to editing.", 12, StyleKit.BLUE
		)
		hint.size_flags_horizontal = SIZE_EXPAND_FILL
		tools.add_child(hint)
		tools.add_child(StyleKit.button("Reset visit", session.reset))


func _zoom(factor: float) -> void:
	canvas.zoom = 1.0 if factor == 0.0 else clampf(canvas.zoom * factor, 0.3, 3.0)
	canvas.layout_view()


func _on_canvas_transform(id: String, rect: Array) -> void:
	mutate("Move / resize", func() -> void: Model.lookup(scene_data().objects, id).rect = rect)


func scene_data() -> Dictionary:
	return Model.lookup(p.scenes, edit_scene)


func obj() -> Dictionary:
	return Model.lookup(scene_data().get("objects", []), selected)


func set_space(key: String) -> void:
	if space == "Test" and key != "Test":
		reset_session()
	if key == "Test" and space != "Test":
		reset_session()
		session.scene = edit_scene
	space = key
	refresh()


func toggle_test() -> void:
	set_space("Canvas" if space == "Test" else "Test")


func pick(id: String) -> void:
	selected = id
	if is_instance_valid(canvas):
		canvas.active = id
		if canvas.overlay:
			canvas.overlay.queue_redraw()
	_layers.deselect_all()
	for i in _layers.item_count:
		if _layers.get_item_metadata(i) == id:
			_layers.select(i)
	inspect()


func tell(text: String) -> void:
	msg = text
	if _status:
		_status.text = text


# ----------------------------------------------------------------------------- editing
## Applies `change` to the project as one undoable step. The project is validated afterwards;
## an invalid result is rolled back and explained in the status bar.
## Options: keep_inspector (the edit came from the inspector, which already shows it) and
## coalesce (repeated edits with the same label within 1.5 s become one undo step).
func mutate(label: String, change: Callable, options := {}) -> void:
	var before := p.duplicate(true)
	var old_scene := edit_scene
	var old_selection := selected
	change.call()
	var problem := Model.validate(p)
	if problem:
		p = before
		edit_scene = old_scene if not Model.lookup(p.scenes, old_scene).is_empty() else p.start
		selected = old_selection
		reset_session()
		refresh()
		tell("Not applied: " + problem)
		return
	var now := Time.get_ticks_msec()
	var coalesce: bool = options.get("coalesce", false)
	var merge := coalesce and label == _last_edit_label and now - _last_edit_time < 1500 and not undo_stack.is_empty()
	if not merge:
		undo_stack.append([before, old_scene, old_selection])
		if undo_stack.size() > 100:
			undo_stack.pop_front()
	_last_edit_label = label if coalesce else ""
	_last_edit_time = now
	redo_stack.clear()
	dirty = true
	next_save = now + 700
	msg = label
	reset_session()
	refresh(options.get("keep_inspector", false))


func _step_history(from: Array, to: Array) -> void:
	if from.is_empty():
		return
	to.append([p.duplicate(true), edit_scene, selected])
	var previous: Array = from.pop_back()
	p = previous[0]
	edit_scene = previous[1] if not Model.lookup(p.scenes, previous[1]).is_empty() else p.start
	selected = previous[2]
	_last_edit_label = ""
	dirty = true
	next_save = Time.get_ticks_msec() + 500
	reset_session()
	refresh()


func undo() -> void:
	_step_history(undo_stack, redo_stack)


func redo() -> void:
	_step_history(redo_stack, undo_stack)


func add_scene() -> void:
	var box := dialog("New scene", 420, 230)
	var name_field := field(box, "Scene name", "New scene")
	box.add_child(StyleKit.button("Create scene", func() -> void:
		var caption := name_field.text.strip_edges()
		if caption.is_empty():
			return
		box.get_window().queue_free()
		mutate("New scene", func() -> void:
			edit_scene = Model.uid("scene")
			p.scenes.append({"id": edit_scene, "name": caption, "background": "#0d1117", "objects": []})
			selected = ""
		)
	, true))
	name_field.select_all()
	name_field.grab_focus.call_deferred()


func move_scene(step: int) -> void:
	var index: int = p.scenes.find(scene_data())
	var target := index + step
	if index < 0 or target < 0 or target >= p.scenes.size():
		return
	mutate("Reorder scenes", func() -> void:
		var scene = p.scenes.pop_at(index)
		p.scenes.insert(target, scene)
	)


func duplicate_scene() -> void:
	mutate("Duplicate scene", func() -> void:
		var copy := scene_data().duplicate(true)
		copy.id = Model.uid("scene")
		copy.name = str(copy.name) + " copy"
		p.scenes.insert(p.scenes.find(scene_data()) + 1, copy)
		edit_scene = copy.id
		selected = ""
	)


## Deletes the current scene and everything that pointed at it (navigation actions, timeline
## keys, fixed output assignments), so the project stays valid.
func delete_scene() -> void:
	if p.scenes.size() < 2:
		tell("An exhibit needs at least one scene.")
		return
	var doomed := edit_scene
	var box := ConfirmationDialog.new()
	add_child(box)
	box.title = "Delete scene?"
	box.dialog_text = (
		"Delete “%s” and its layers? Buttons that go to it will stop navigating. Undo restores everything."
		% scene_data().name
	)
	box.ok_button_text = "Delete scene"
	box.confirmed.connect(func() -> void:
		mutate("Delete scene", func() -> void:
			p.scenes = p.scenes.filter(func(s: Dictionary) -> bool: return s.id != doomed)
			if p.start == doomed:
				p.start = p.scenes[0].id
			for rule in p.rules:
				rule.actions = rule.actions.filter(func(a: Dictionary) -> bool:
					return not (a.get("op") == "goto" and a.get("target") == doomed)
				)
			for timeline in p.timelines:
				timeline.cues = timeline.get("cues", []).filter(func(c: Dictionary) -> bool:
					return not (c.action.get("op") == "goto" and c.action.get("target") == doomed)
				)
				timeline.keys = timeline.get("keys", []).filter(
					func(k: Dictionary) -> bool: return k.scene != doomed
				)
			for output in p.installation.outputs:
				if output.get("scene", "@live") == doomed:
					output.scene = "@live"
			edit_scene = p.start
			selected = ""
		)
	)
	box.popup_centered()


func add_menu() -> void:
	var box := dialog("Add a component", 560, 560)
	for group in KIND_GROUPS:
		box.add_child(StyleKit.label(group[0].to_upper(), 11, StyleKit.MUTED))
		var flow := HFlowContainer.new()
		box.add_child(flow)
		for pair in group[1]:
			var kind: String = pair[0]
			var button := StyleKit.button(pair[1], func() -> void:
				box.get_window().queue_free()
				if kind in ["image", "audio", "video", "model"]:
					import_media(kind)
				else:
					add_object(kind)
			)
			button.custom_minimum_size.x = 160
			flow.add_child(button)


func _kind_label(kind: String) -> String:
	for group in KIND_GROUPS:
		for pair in group[1]:
			if pair[0] == kind:
				return pair[1]
	return kind.capitalize()


func add_object(kind: String, asset := "") -> void:
	mutate("Add " + _kind_label(kind).to_lower(), func() -> void:
		selected = Model.uid(kind)
		var o := {"id": selected, "name": _kind_label(kind), "kind": kind, "rect": [80, 80, 340, 96]}
		if kind in ["text", "button", "entry"]:
			o.text = {"text": "New text", "button": "Press me", "entry": "Type here"}[kind]
		if kind == "panel":
			o.color = "#21262d"
		if kind in ["orbit", "image", "drawing", "model", "video", "particles", "fractal", "plot", "grid"]:
			o.rect = [100, 90, 540, 340]
		if kind == "contest":
			o.rect = [40, 32, p.canvas[0] - 80, p.canvas[1] - 64]
		if kind in ["entry", "slider", "drawing", "gauge", "fractal"]:
			o.bind = selected
		if kind in ["entry", "slider"]:
			var source := ("change." if kind == "entry" else "input.") + selected
			p.rules.append(
				{
					"id": Model.uid("rule"),
					"event": source,
					"actions": [{"op": "set", "target": selected, "value": "$value"}]
				}
			)
		if asset:
			o.asset = asset
		scene_data().objects.append(o)
		if space not in ["Canvas", "Test"]:
			space = "Canvas"
	)


func import_media(kind: String) -> void:
	var filters := {
		"image": "*.png,*.jpg,*.jpeg,*.webp,*.svg ; Images",
		"audio": "*.ogg,*.mp3,*.wav ; Sound",
		"video": "*.ogv ; Ogg Theora video",
		"model": "*.glb,*.gltf,*.obj ; 3D models",
	}
	file_dialog(
		"Import " + kind,
		FileDialog.FILE_MODE_OPEN_FILE,
		[filters[kind]],
		func(path: String) -> void: add_asset_path(path, kind)
	)


func add_asset_path(path: String, kind: String) -> void:
	var id := io.import_asset(path, p)
	if id:
		add_object(kind, id)
	else:
		tell(io.error)


func _on_files_dropped(files: PackedStringArray) -> void:
	for file in files:
		var ext := file.get_extension().to_lower()
		if ext in ["json", "oex"]:
			request_open(file)
			return
		if ext in ["png", "jpg", "jpeg", "svg", "webp"]:
			add_asset_path(file, "image")
		elif ext in ["wav", "ogg", "mp3"]:
			add_asset_path(file, "audio")
		elif ext == "ogv":
			add_asset_path(file, "video")
		elif ext in ["glb", "gltf", "obj"]:
			add_asset_path(file, "model")
		elif ext in ["mp4", "webm", "mov", "mkv"]:
			tell(
				(
					"Convert video to .ogv first:  ffmpeg -i %s -c:v libtheora -q:v 7 -c:a libvorbis out.ogv"
					% file.get_file()
				)
			)
		else:
			tell("Unsupported file type: ." + ext)


func delete_object() -> void:
	if obj().is_empty():
		return
	var doomed := selected
	mutate("Delete layer", func() -> void:
		scene_data().objects.erase(obj())
		for timeline in p.timelines:
			timeline.keys = timeline.get("keys", []).filter(
				func(k: Dictionary) -> bool: return k.object != doomed or k.scene != edit_scene
			)
		p.rules = p.rules.filter(func(r: Dictionary) -> bool: return r.id != "press_" + doomed)
		selected = ""
	)


func duplicate_object() -> void:
	if obj().is_empty():
		return
	mutate("Duplicate layer", func() -> void:
		var copy := obj().duplicate(true)
		selected = Model.uid(copy.kind)
		copy.id = selected
		copy.name = str(copy.get("name", copy.kind)) + " copy"
		copy.rect[0] += 16
		copy.rect[1] += 16
		scene_data().objects.append(copy)
	)


func move_layer(step: int) -> void:
	var o := obj()
	if o.is_empty():
		return
	mutate("Reorder layer", func() -> void:
		var objects: Array = scene_data().objects
		var index := objects.find(o)
		objects.remove_at(index)
		objects.insert(clampi(index + step, 0, objects.size()), o)
	)


# ----------------------------------------------------------------------------- inspector
func inspect() -> void:
	StyleKit.clear(inspector)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.PANEL, Color.TRANSPARENT, 0, 12))
	inspector.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(StyleKit.label("INSPECTOR", 11, StyleKit.MUTED))
	var o := obj()
	if o.is_empty():
		_inspect_scene(box)
	else:
		_inspect_object(box, o)
	box.add_child(HSeparator.new())
	box.add_child(StyleKit.button("Detach / dock inspector", float_inspector))


func _inspect_scene(box: VBoxContainer) -> void:
	var scene := scene_data()
	box.add_child(StyleKit.label(str(scene.name), 18, Color.WHITE))
	box.add_child(_hint("Scene · click a layer on the canvas or in Layers to edit it."))
	_prop_text(box, "Scene name", scene, "name")
	_prop_color(box, "Background", scene, "background", "#0d1117")
	_prop_choice(
		box,
		"Transition when it opens",
		scene,
		"transition",
		[["cut", "Cut"], ["fade", "Fade"], ["slide", "Slide"]],
		"cut"
	)
	if scene.id != p.start:
		box.add_child(
			StyleKit.button(
				"Make this the first scene", func() -> void: mutate("First scene", func() -> void: p.start = scene.id)
			)
		)
	box.add_child(HSeparator.new())
	box.add_child(StyleKit.label("Exhibit", 14, StyleKit.BLUE))
	box.add_child(
		_hint(
			(
				"%s · %d scenes · %d outputs"
				% [p.installation.get("preset", "Custom"), p.scenes.size(), p.installation.outputs.size()]
			)
		)
	)
	box.add_child(StyleKit.button("Exhibit settings…", settings_dialog))


func _inspect_object(box: VBoxContainer, o: Dictionary) -> void:
	box.add_child(StyleKit.label(str(o.get("name", o.id)), 18, Color.WHITE))
	box.add_child(_hint(_kind_label(o.kind) + " · " + o.id))
	_prop_text(box, "Layer name", o, "name")
	match o.kind:
		"text":
			_prop_text(box, "Text — use {variable} to show a value", o, "text", true)
			_prop_number(box, "Font size", o, "font", 30, 7, 240)
			_prop_choice(box, "Alignment", o, "align", [[0, "Left"], [1, "Centre"], [2, "Right"]], 0)
			_prop_color(box, "Colour", o, "color", "#e6edf3")
		"button":
			_prop_text(box, "Label", o, "text")
			_prop_number(box, "Font size", o, "font", 22, 7, 240)
			_prop_color(box, "Text colour", o, "color", "#e6edf3")
			_prop_color(box, "Fill", o, "fill", "#1a3841")
			_prop_color(box, "Border", o, "border", "#34616a")
			_press_editor(box, o)
		"panel":
			_prop_color(box, "Fill", o, "color", "#21262d")
			_prop_color(box, "Border", o, "border", "#00000000")
			_prop_number(box, "Corner radius", o, "radius", 12, 0, 400)
		"entry":
			_prop_text(box, "Placeholder text", o, "text")
			_prop_number(box, "Font size", o, "font", 24, 7, 240)
			_prop_variable(box, "Stores the typed text in", o)
		"slider":
			_prop_number(box, "Minimum", o, "min", 0, -1e9, 1e9, 0.01)
			_prop_number(box, "Maximum", o, "max", 100, -1e9, 1e9, 0.01)
			_prop_number(box, "Step", o, "step", 1, 0.0001, 1e9, 0.0001)
			_prop_variable(box, "Shows the value of", o)
			box.add_child(
				_hint("Moving it raises the event “input.%s”; use it in Interactions." % o.get("channel", o.id))
			)
		"gauge", "plot":
			_prop_number(box, "Minimum", o, "min", 0, -1e9, 1e9, 0.01)
			_prop_number(box, "Maximum", o, "max", 100, -1e9, 1e9, 0.01)
			_prop_color(box, "Colour", o, "color", "#58a6ff")
			if o.kind == "gauge":
				_prop_variable(box, "Shows variable", o)
			else:
				_prop_text(box, "Plots channel", o, "channel")
		"drawing", "fractal":
			_prop_color(box, "Colour", o, "color", "#58a6ff")
			_prop_variable(box, "Variable", o)
		"image":
			_prop_check(box, "Stretch to fill the frame", o, "stretch")
			box.add_child(StyleKit.button("Replace image…", _replace_asset.bind(o, "image")))
		"video", "audio":
			_prop_check(box, "Loop", o, "loop", o.kind == "video")
			_prop_number(box, "Volume (dB)", o, "volume_db", 0, -60, 12, 0.5)
			box.add_child(StyleKit.button("Replace file…", _replace_asset.bind(o, o.kind)))
		"contest":
			box.add_child(
				_hint("Shows the live audience session (join code, questions, results). Run it from Live audience.")
			)
	box.add_child(StyleKit.label("Position and size", 14, StyleKit.BLUE))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for j in 4:
		_prop_rect(grid, ["X", "Y", "Width", "Height"][j], o, j)
	var flags := HBoxContainer.new()
	box.add_child(flags)
	_prop_check(flags, "Hidden", o, "hidden")
	_prop_check(flags, "Locked", o, "locked")
	var actions := HBoxContainer.new()
	box.add_child(actions)
	actions.add_child(StyleKit.button("Duplicate", duplicate_object))
	actions.add_child(StyleKit.button("Delete", delete_object))


func _hint(text: String) -> Label:
	var label := StyleKit.label(text, 12, StyleKit.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _commit(label: String, target: Dictionary, key: String, value, coalesce := false) -> void:
	if target.get(key) == value:
		return
	mutate(label, func() -> void: target[key] = value, {"keep_inspector": true, "coalesce": coalesce})


func _prop_text(box: Control, caption: String, target: Dictionary, key: String, multiline := false) -> void:
	box.add_child(StyleKit.label(caption, 12, StyleKit.MUTED))
	if multiline:
		var area := TextEdit.new()
		area.text = str(target.get(key, ""))
		area.custom_minimum_size.y = 76
		area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		area.focus_exited.connect(
			func() -> void: _commit("Edit " + caption.get_slice(" —", 0).to_lower(), target, key, area.text)
		)
		box.add_child(area)
		return
	var line := LineEdit.new()
	line.text = str(target.get(key, ""))
	var apply := func(_ignored = null) -> void: _commit("Edit " + caption.to_lower(), target, key, line.text)
	line.text_submitted.connect(apply)
	line.focus_exited.connect(apply)
	box.add_child(line)


func _prop_number(
	box: Control,
	caption: String,
	target: Dictionary,
	key: String,
	fallback: float,
	low: float,
	high: float,
	step := 1.0
) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := StyleKit.label(caption, 12, StyleKit.MUTED)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = float(target.get(key, fallback))
	spin.custom_minimum_size.x = 110
	spin.value_changed.connect(func(v: float) -> void: _commit("Edit " + caption.to_lower(), target, key, v, true))
	row.add_child(spin)


func _prop_rect(grid: GridContainer, caption: String, target: Dictionary, index: int) -> void:
	var spin := SpinBox.new()
	spin.prefix = caption.left(1)
	spin.min_value = -8192 if index < 2 else 1
	spin.max_value = 16384
	spin.value = float(target.rect[index])
	spin.tooltip_text = caption
	spin.custom_minimum_size.x = 120
	spin.value_changed.connect(func(v: float) -> void:
		if target.rect[index] == v:
			return
		mutate("Move / resize", func() -> void: target.rect[index] = v, {"keep_inspector": true, "coalesce": true})
	)
	grid.add_child(spin)


func _prop_color(box: Control, caption: String, target: Dictionary, key: String, fallback: String) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := StyleKit.label(caption, 12, StyleKit.MUTED)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.color = Color.from_string(str(target.get(key, fallback)), Color(fallback))
	picker.edit_alpha = true
	picker.custom_minimum_size = Vector2(110, 28)
	picker.color_changed.connect(
		func(c: Color) -> void: _commit("Edit " + caption.to_lower(), target, key, "#" + c.to_html(c.a < 0.999), true)
	)
	row.add_child(picker)


func _prop_choice(box: Control, caption: String, target: Dictionary, key: String, options: Array, fallback) -> void:
	box.add_child(StyleKit.label(caption, 12, StyleKit.MUTED))
	var menu := OptionButton.new()
	for i in options.size():
		menu.add_item(str(options[i][1]))
		menu.set_item_metadata(i, options[i][0])
		if options[i][0] == target.get(key, fallback):
			menu.select(i)
	menu.item_selected.connect(
		func(i: int) -> void: _commit("Edit " + caption.to_lower(), target, key, menu.get_item_metadata(i))
	)
	box.add_child(menu)


func _prop_check(box: Control, caption: String, target: Dictionary, key: String, fallback := false) -> void:
	var check := CheckBox.new()
	check.text = caption
	check.button_pressed = bool(target.get(key, fallback))
	check.toggled.connect(func(on: bool) -> void: _commit(caption, target, key, on))
	box.add_child(check)


func _prop_variable(box: Control, caption: String, target: Dictionary) -> void:
	_prop_text(box, caption + " (variable name)", target, "bind")


func _replace_asset(target: Dictionary, kind: String) -> void:
	var filters := {"image": "*.png,*.jpg,*.jpeg,*.webp,*.svg", "audio": "*.ogg,*.mp3,*.wav", "video": "*.ogv"}
	file_dialog("Replace " + kind, FileDialog.FILE_MODE_OPEN_FILE, [filters.get(kind, "*")], func(path: String) -> void:
		var id := io.import_asset(path, p)
		if id:
			mutate("Replace " + kind, func() -> void: target.asset = id)
		else:
			tell(io.error)
	)


# --------------------------------------------------------------------- button "When pressed"
func _press_event(o: Dictionary) -> String:
	return str(o.get("event", "tap." + o.id))


## The rule that the inspector manages for a button has the ID press_<button id>.
func _press_rule(o: Dictionary) -> Dictionary:
	return Model.lookup(p.rules, "press_" + o.id)


func _press_editor(box: VBoxContainer, o: Dictionary) -> void:
	box.add_child(StyleKit.label("When pressed", 14, StyleKit.BLUE))
	var rule := _press_rule(o)
	var action: Dictionary = rule.get("actions", [{}])[0] if rule.get("actions", []).size() == 1 else {}
	var current := str(action.get("op", ""))
	if current == "emit" and str(action.get("target")) in ["book.next", "book.prev"]:
		current = "next" if action.target == "book.next" else "prev"
	if not rule.is_empty() and rule.get("actions", []).size() > 1:
		box.add_child(_hint("This button runs %d actions — edit them in Interactions." % rule.actions.size()))
		box.add_child(StyleKit.button("Open in Interactions", set_space.bind("Logic")))
		return
	var kinds := OptionButton.new()
	for i in PRESS_ACTIONS.size():
		kinds.add_item(PRESS_ACTIONS[i][1])
		if PRESS_ACTIONS[i][0] == current:
			kinds.select(i)
	box.add_child(kinds)
	var detail := VBoxContainer.new()
	box.add_child(detail)
	var others: Array = p.rules.filter(
		func(r: Dictionary) -> bool: return r.event == _press_event(o) and r.id != "press_" + o.id
	)
	if others.size():
		box.add_child(_hint("Also used by %d rule(s) in Interactions." % others.size()))
	_press_detail(detail, o, current, action)
	kinds.item_selected.connect(func(i: int) -> void:
		var op: String = PRESS_ACTIONS[i][0]
		StyleKit.clear(detail)
		_press_detail(detail, o, op, {})
		if op in ["", "next", "prev", "reset", "pause"]:
			_save_press(o, op, "", null)
	)


func _press_detail(detail: VBoxContainer, o: Dictionary, op: String, action: Dictionary) -> void:
	match op:
		"goto":
			var scenes := OptionButton.new()
			scenes.add_item("Choose a scene…")
			for scene in p.scenes:
				scenes.add_item(str(scene.name))
				scenes.set_item_metadata(scenes.item_count - 1, scene.id)
				if scene.id == action.get("target"):
					scenes.select(scenes.item_count - 1)
			scenes.item_selected.connect(func(i: int) -> void:
				if i > 0:
					_save_press(o, "goto", str(scenes.get_item_metadata(i)), null)
			)
			detail.add_child(scenes)
		"play":
			if p.timelines.is_empty():
				detail.add_child(_hint("No timelines yet — create one in Timeline."))
				return
			var tracks := OptionButton.new()
			tracks.add_item("Choose a timeline…")
			for t in p.timelines:
				tracks.add_item(str(t.get("name", t.id)))
				tracks.set_item_metadata(tracks.item_count - 1, t.id)
				if t.id == action.get("target"):
					tracks.select(tracks.item_count - 1)
			tracks.item_selected.connect(func(i: int) -> void:
				if i > 0:
					_save_press(o, "play", str(tracks.get_item_metadata(i)), null)
			)
			detail.add_child(tracks)
		"set", "add", "output":
			var target := LineEdit.new()
			target.placeholder_text = "output channel, e.g. lamp" if op == "output" else "variable name, e.g. score"
			target.text = str(action.get("target", ""))
			var value := LineEdit.new()
			value.placeholder_text = "value, e.g. 1"
			value.text = RuleText.value(action.get("value", 1)) if action.has("value") else "1"
			var apply := func(_ignored = null) -> void:
				if target.text.strip_edges():
					_save_press(o, op, target.text.strip_edges(), _parse_value(value.text))
			target.text_submitted.connect(apply)
			target.focus_exited.connect(apply)
			value.text_submitted.connect(apply)
			value.focus_exited.connect(apply)
			detail.add_child(target)
			detail.add_child(
				StyleKit.label("to" if op == "set" else ("value" if op == "output" else "amount"), 12, StyleKit.MUTED)
			)
			detail.add_child(value)


func _parse_value(text: String):
	var t := text.strip_edges()
	if t.is_valid_float():
		return float(t)
	if t in ["true", "false"]:
		return t == "true"
	return t


func _save_press(o: Dictionary, op: String, target: String, value) -> void:
	var event := _press_event(o)
	mutate("Button action", func() -> void:
		p.rules = p.rules.filter(func(r: Dictionary) -> bool: return r.id != "press_" + o.id)
		if op == "":
			return
		var action := {"op": op, "target": target}
		if op == "next" or op == "prev":
			action = {"op": "emit", "target": "book." + op}
		elif op == "reset":
			action = {"op": "reset", "target": ""}
		if value != null:
			action.value = value
		p.rules.append({"id": "press_" + o.id, "event": event, "actions": [action]})
	, {"keep_inspector": true})


func float_inspector() -> void:
	if expanded:
		inspector.reparent(_right_scroll)
		expanded.queue_free()
		expanded = null
		_right_scroll.show()
		return
	expanded = Window.new()
	expanded.title = "OpenExhibit · Inspector"
	expanded.size = Vector2i(340, 680)
	add_child(expanded)
	var scroll := ScrollContainer.new()
	expanded.add_child(scroll)
	StyleKit.fill(scroll)
	inspector.reparent(scroll)
	_right_scroll.hide()
	expanded.close_requested.connect(float_inspector)


# ----------------------------------------------------------------------------- shared widgets
## Labelled single-line field (used by workspaces and dialogs).
func field(box: Control, caption: String, value) -> LineEdit:
	box.add_child(StyleKit.label(caption, 12, StyleKit.MUTED))
	var line := LineEdit.new()
	line.text = str(value)
	box.add_child(line)
	return line


func number(box: Control, caption: String, value, low, high, step = 0.1) -> SpinBox:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := StyleKit.label(caption, 12, StyleKit.MUTED)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 110
	row.add_child(spin)
	return spin


func choice(box: Control, caption: String, items: Array, current = "") -> OptionButton:
	if caption:
		box.add_child(StyleKit.label(caption, 12, StyleKit.MUTED))
	var menu := OptionButton.new()
	for item in items:
		menu.add_item(str(item))
	menu.select(maxi(0, items.find(current)))
	box.add_child(menu)
	return menu


## Opens a scrollable modal window and returns the column to fill.
func dialog(title: String, width := 520, height := 480) -> VBoxContainer:
	var window := Window.new()
	window.title = title
	window.transient = true
	window.exclusive = true
	window.size = Vector2i(width, height)
	window.min_size = Vector2i(mini(400, width), 220)
	window.theme = theme
	add_child(window)
	window.close_requested.connect(window.queue_free)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window.add_child(scroll)
	StyleKit.fill(scroll)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.PANEL, Color.TRANSPARENT, 0, 16))
	scroll.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(StyleKit.label(title, 18, Color.WHITE))
	window.popup_centered()
	return column


func file_dialog(title: String, mode: int, filters: Array, on_pick: Callable) -> void:
	var picker := FileDialog.new()
	add_child(picker)
	picker.title = title
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = mode
	picker.filters = PackedStringArray(filters)
	if io.folder and DirAccess.dir_exists_absolute(io.folder):
		picker.current_dir = io.folder
	if mode == FileDialog.FILE_MODE_SAVE_FILE:
		picker.current_file = "exhibit.oex" if "*.oex" in str(filters) else "project.oes.json"
	picker.file_selected.connect(func(path: String) -> void:
		on_pick.call(path)
		picker.queue_free()
	)
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.72)


# ----------------------------------------------------------------------------- files
func discard_then(next_step: Callable) -> void:
	if not dirty:
		next_step.call()
		return
	var box := ConfirmationDialog.new()
	box.title = "Discard unsaved edits?"
	box.dialog_text = "“%s” has unsaved changes. Save first to keep them." % p.title
	box.ok_button_text = "Discard and continue"
	add_child(box)
	box.confirmed.connect(func() -> void:
		next_step.call()
		box.queue_free()
	)
	box.canceled.connect(box.queue_free)
	box.popup_centered()


func new_project() -> void:
	discard_then(func() -> void:
		io = Storage.new()
		_new_working_folder()
		switch_project(Model.fresh())
		tell("New exhibit. Choose File → Save as to give it a folder.")
	)


func switch_project(value: Dictionary) -> void:
	p = value
	edit_scene = p.start
	selected = ""
	space = "Canvas"
	dirty = false
	next_save = 0
	undo_stack.clear()
	redo_stack.clear()
	if FileAccess.file_exists(journal):
		DirAccess.remove_absolute(journal)
	reset_session()
	msg = ""
	refresh()


func open_project() -> void:
	file_dialog("Open exhibit", FileDialog.FILE_MODE_OPEN_FILE, ["*.json,*.oex ; Projects and packages"], request_open)


func request_open(path: String) -> void:
	discard_then(func() -> void:
		var next := Storage.new()
		var loaded := next.open(path)
		if loaded.is_empty():
			tell(next.error)
			return
		io = next
		switch_project(loaded)
		_remember(io.path)
		tell("Opened " + io.path)
	)


func _is_example(path: String) -> bool:
	return Paths.examples() != "" and path.begins_with(Paths.examples() + "/")


func save() -> void:
	if not io.path or io.packaged or _is_example(io.path):
		save_as()
	else:
		save_to(io.path)


func save_as() -> void:
	file_dialog(
		"Save exhibit — choose or create an empty folder",
		FileDialog.FILE_MODE_SAVE_FILE,
		["*.json ; Project JSON"],
		save_to
	)


func save_to(path: String) -> void:
	if not path.to_lower().ends_with(".json"):
		path += ".oes.json"
	if io.save(p, path):
		dirty = false
		next_save = 0
		if FileAccess.file_exists(journal):
			DirAccess.remove_absolute(journal)
		_remember(io.path)
		msg = "Saved " + io.path
		refresh(true)
	else:
		tell(io.error)


func pack_project() -> void:
	file_dialog("Export portable exhibit", FileDialog.FILE_MODE_SAVE_FILE, ["*.oex ; Portable exhibit"], func(path: String) -> void:
		if not path.to_lower().ends_with(".oex"):
			path += ".oex"
		tell("Exported " + path + " — open it with the Player." if io.pack(p, path) else io.error)
	)


func examples_dialog() -> void:
	Welcome.open(self)


func _remember(path: String) -> void:
	if not path or _is_example(path) or path.begins_with(Storage.absolute("user://")):
		return
	var recent = Storage.json_at(Storage.absolute(RECENT_FILE))
	var list: Array = recent if recent is Array else []
	list.erase(path)
	list.push_front(path)
	Storage.write_json(Storage.absolute(RECENT_FILE), list.slice(0, 10))
	_refresh_recent_menu()


func recent_projects() -> Array:
	var recent = Storage.json_at(Storage.absolute(RECENT_FILE))
	return (recent if recent is Array else []).filter(
		func(path) -> bool: return path is String and FileAccess.file_exists(path)
	)


func _refresh_recent_menu() -> void:
	if not _recent_menu:
		return
	_recent_menu.clear()
	var list := recent_projects()
	for i in list.size():
		_recent_menu.add_item(str(list[i]).get_base_dir().get_file() + "  —  " + str(list[i]), i)
	if list.is_empty():
		_recent_menu.add_item("No recent exhibits", 0)
		_recent_menu.set_item_disabled(0, true)


func _open_recent(index: int) -> void:
	var list := recent_projects()
	if index < list.size():
		request_open(list[index])


func pref(key: String, fallback = null):
	var config := ConfigFile.new()
	config.load(PREFS_FILE)
	return config.get_value("studio", key, fallback)


func set_pref(key: String, value) -> void:
	var config := ConfigFile.new()
	config.load(PREFS_FILE)
	config.set_value("studio", key, value)
	config.save(PREFS_FILE)


func _open_doc(relative: String) -> void:
	var path := Tools.path(relative)
	if FileAccess.file_exists(path):
		OS.shell_open(path)
	else:
		tell("Documentation not found next to this installation: " + relative)


# ----------------------------------------------------------------------------- dialogs
func settings_dialog() -> void:
	var box := dialog("Exhibit settings", 480, 560)
	var title := field(box, "Exhibit title", p.title)
	var width := number(box, "Design width (px)", p.canvas[0], 32, 8192, 1)
	var height := number(box, "Design height (px)", p.canvas[1], 32, 8192, 1)
	var idle := number(
		box, "Reset to the first scene after idle (seconds, 0 = never)", p.settings.get("idle_seconds", 0), 0, 86400, 1
	)
	var scene_ids: Array = p.scenes.map(func(s: Dictionary) -> String: return s.id)
	var scene_names: Array = p.scenes.map(func(s: Dictionary) -> String: return str(s.name))
	var start := choice(box, "First scene", scene_names, scene_names[maxi(0, scene_ids.find(p.start))])
	var track_ids: Array = [""] + p.timelines.map(func(t: Dictionary) -> String: return t.id)
	var track_names: Array = (
		["(none)"] + p.timelines.map(func(t: Dictionary) -> String: return str(t.get("name", t.id)))
	)
	var autoplay := choice(
		box,
		"Timeline to play at start",
		track_names,
		track_names[maxi(0, track_ids.find(p.settings.get("autoplay", "")))]
	)
	var expressions := CheckBox.new()
	expressions.text = "Allow maths expressions in rule values (advanced)"
	expressions.button_pressed = p.settings.get("expressions", false)
	box.add_child(expressions)
	box.add_child(StyleKit.button("Apply", func() -> void:
		box.get_window().queue_free()
		mutate("Exhibit settings", func() -> void:
			p.title = title.text.strip_edges() if title.text.strip_edges() else p.title
			p.canvas = [width.value, height.value]
			p.settings.idle_seconds = idle.value
			p.start = scene_ids[start.selected]
			p.settings.autoplay = track_ids[autoplay.selected]
			p.settings.expressions = expressions.button_pressed
		)
	, true))


func commands() -> void:
	var box := dialog("Command palette", 520, 560)
	var search := field(box, "Type to search · Enter runs the first match", "")
	var list := VBoxContainer.new()
	box.add_child(list)
	var options := {
		"Save": save,
		"Save as…": save_as,
		"Open…": open_project,
		"New exhibit": new_project,
		"Export package": pack_project,
		"Add a component": add_menu,
		"New scene": add_scene,
		"Start screen and templates": Welcome.open.bind(self),
		"Undo": undo,
		"Redo": redo,
		"Exhibit settings": settings_dialog,
		"Try it as a visitor": toggle_test,
	}
	for key in SPACES:
		options["Go to " + SPACE_INFO[key][1]] = set_space.bind(key)
	var visible_actions := []
	var filter := func(query: String) -> void:
		StyleKit.clear(list)
		visible_actions.clear()
		for caption in options:
			if query.to_lower() in caption.to_lower():
				visible_actions.append(options[caption])
				var run: Callable = options[caption]
				var button := StyleKit.button(caption, func() -> void:
					box.get_window().queue_free()
					run.call()
				)
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				list.add_child(button)
	search.text_changed.connect(filter)
	search.text_submitted.connect(func(_text: String) -> void:
		if visible_actions.size():
			box.get_window().queue_free()
			(visible_actions[0] as Callable).call()
	)
	filter.call("")
	search.grab_focus.call_deferred()


func guide() -> void:
	var box := dialog("Quick guide", 600, 520)
	for line in [
		"1. File → Start screen offers templates and recent exhibits.",
		"2. Click a layer on the canvas (or in Layers) and edit it in the Inspector — changes apply as you type.",
		"3. Drag to move; drag the bottom-right handle to resize. Hold Alt for single-pixel moves.",
		"4. Select a button and choose what happens “When pressed” — no event names to type.",
		"5. Interactions builds richer rules: When something happens → If a condition → Do actions.",
		"6. Press F5 (Try it) to use the exhibit as a visitor; F5 again returns to editing.",
		"7. Live audience runs polls, quizzes and Q&A on visitors' phones over the local network.",
		"8. Save as into an empty folder; File → Export package makes a .oex for the Player.",
	]:
		box.add_child(_hint(line))


# ----------------------------------------------------------------------------- input + autosave
func _process(_delta: float) -> void:
	if not booted:
		return
	if space in ["Test", "Timeline", "Hardware", "Logic", "Mapping", "Flipbook", "Science"]:
		session.wall_tick()
	if dirty and next_save and Time.get_ticks_msec() >= next_save:
		next_save = 0
		var problem := Storage.write_json(
			journal,
			{"project": p, "path": io.path, "folder": io.folder, "revision": io.revision, "packaged": io.packaged}
		)
		if problem:
			tell("Recovery copy could not be written: " + problem)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var command := key.ctrl_pressed or key.meta_pressed
	if command:
		match key.keycode:
			KEY_S:
				if key.shift_pressed:
					save_as()
				else:
					save()
			KEY_O:
				open_project()
			KEY_N:
				new_project()
			KEY_E:
				pack_project()
			KEY_Z:
				if key.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_P:
				commands()
			KEY_D:
				duplicate_object()
			KEY_Q:
				_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			_:
				return
	elif key.keycode == KEY_F5:
		toggle_test()
	elif key.keycode == KEY_DELETE and space == "Canvas":
		delete_object()
	else:
		return
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not booted or space != "Test":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
		elif absf(event.position.x - _touch_start.x) > 110 and absf(event.position.y - _touch_start.y) < 80:
			session.dispatch("book.next" if event.position.x < _touch_start.x else "book.prev", 1, true)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_RIGHT, KEY_LEFT]:
		session.dispatch("book.next" if event.keycode == KEY_RIGHT else "book.prev", 1, true)

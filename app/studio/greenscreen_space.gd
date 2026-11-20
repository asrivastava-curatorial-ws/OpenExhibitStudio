extends RefCounted
## Green screen workspace — a camera photo booth. Visitors stand in front of a green cloth; the
## booth replaces the green with the exhibit's background videos and pictures and lets them take a
## photo or a short video home by QR code, over the local network only.
## Studio starts the booth service (tools/greenscreen.py) and opens the booth in the browser on this
## computer (browsers allow the camera only on a local address). Calibration made on the booth can
## be saved back into the exhibit. The service stops automatically when Studio closes.

const StyleKit := preload("res://core/skin.gd")
const Store := preload("res://core/storage.gd")
const Model := preload("res://core/project.gd")
const Tools := preload("res://core/tools.gd")

const VIDEO_TYPES := ["webm", "mp4", "m4v"]
const IMAGE_TYPES := ["png", "jpg", "jpeg", "webp"]
const FITS := [["cover", "Fill the screen"], ["contain", "Show the whole picture"]]
## Same defaults as tools/booth/config.py, which also checks and clamps every value.
const DEFAULTS := {
	"photo": true,
	"clip": true,
	"clip_seconds": 8,
	"countdown": 3,
	"keep_minutes": 30,
	"cycle_seconds": 20,
	"mirror": true,
}
## What the booth's setup panel changes; "Save booth settings into this exhibit" copies these.
const CALIBRATION := ["key", "person", "mirror", "camera"]

var host
var info := {}
var pid := -1
var address := "127.0.0.1"
var _starting := false


func _init(owner) -> void:
	host = owner


func running() -> bool:
	if pid > 0 and not OS.is_process_running(pid):
		pid = -1
		info = {}
	return pid > 0 and info.has("booth")


func shutdown() -> void:
	Tools.stop(pid)
	pid = -1
	info = {}


func booth() -> Dictionary:
	return host.p.get("extensions", {}).get("greenscreen", {})


func _value(key: String):
	return booth().get(key, DEFAULTS.get(key))


## Applies `edit` to the exhibit's booth settings as one undoable step, creating them on first use.
func _change(label: String, edit: Callable, coalesce := false) -> void:
	host.mutate(label, func() -> void:
		if not host.p.has("extensions"):
			host.p.extensions = {}
		if not host.p.extensions.get("greenscreen") is Dictionary:
			host.p.extensions.greenscreen = {"backgrounds": []}
		edit.call(host.p.extensions.greenscreen)
	, {"coalesce": coalesce})


# ----------------------------------------------------------------------------- page
func show(parent: Control) -> void:
	var box: VBoxContainer = host.logic._page(parent)
	(
		host
		. logic
		. _heading(
			box,
			"Green screen",
			"A camera photo booth: visitors stand in front of a green cloth and appear in your videos and pictures. They can take a photo or a short video home by scanning a QR code — over this local network only, nothing goes to the internet."
		)
	)
	_backgrounds_section(box)
	box.add_child(HSeparator.new())
	_visitor_section(box)
	box.add_child(HSeparator.new())
	_booth_section(box)
	box.add_child(HSeparator.new())
	box.add_child(StyleKit.label("Setting up the green screen", 15, StyleKit.BLUE))
	for line in [
		"Use matte green fabric or paint, stretched without folds, and light it evenly with its own lamps; light people separately from the front.",
		"Keep people one or two metres in front of the cloth so it does not throw green light onto them, and ask them not to wear green.",
		"Fix the camera's exposure and white balance if the camera software allows it; automatic changes upset the keying.",
		"On the booth press Ctrl+Shift+S for setup: “Detect from edges” with nobody in front of the cloth, then adjust until “Show matte” shows people white and the cloth black.",
	]:
		box.add_child(host.logic._muted("•  " + line))


func _backgrounds_section(box: VBoxContainer) -> void:
	box.add_child(StyleKit.label("Backgrounds", 15, StyleKit.BLUE))
	var backgrounds: Array = booth().get("backgrounds", [])
	if backgrounds.is_empty():
		(
			box
			. add_child(
				(
					host
					. logic
					. _muted(
						"No backgrounds yet. Add your videos (WebM or MP4) or pictures (PNG, JPEG, WebP); visitors switch between them on the booth screen."
					)
				)
			)
		)
	for i in backgrounds.size():
		box.add_child(_background_row(backgrounds[i], i, backgrounds.size()))
	var row := HFlowContainer.new()
	box.add_child(row)
	row.add_child(StyleKit.button("Add video or picture…", func() -> void:
		host.file_dialog(
			"Add a background",
			FileDialog.FILE_MODE_OPEN_FILE,
			["*.webm,*.mp4,*.m4v,*.png,*.jpg,*.jpeg,*.webp ; Videos and pictures"],
			add_background
		)
	, true))
	var overlay := str(booth().get("overlay", ""))
	row.add_child(StyleKit.button("Choose overlay picture…", func() -> void:
		host.file_dialog(
			"Overlay (PNG with transparency)",
			FileDialog.FILE_MODE_OPEN_FILE,
			["*.png ; PNG pictures"],
			_set_overlay
		)
	))
	if overlay:
		row.add_child(
			StyleKit.button(
				"Remove overlay",
				func() -> void: _change("Remove overlay", func(g: Dictionary) -> void: g.erase("overlay"))
			)
		)
	box.add_child(
		host.logic._muted(
			(
				"Overlay: "
				+ (_asset_file(overlay) if overlay else "none")
				+ " — an optional frame or logo drawn over the booth picture and every photo and video."
			)
		)
	)
	(
		box
		. add_child(
			(
				host
				. logic
				. _muted(
					"Browsers cannot play Ogg Theora (.ogv). Convert other videos with:  ffmpeg -i input.mov -c:v libvpx-vp9 -b:v 0 -crf 32 -an output.webm"
				)
			)
		)
	)


func _background_row(item: Dictionary, index: int, count: int) -> Control:
	var row := HBoxContainer.new()
	var title := LineEdit.new()
	title.text = str(item.get("name", ""))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size.x = 180
	var rename := func(_ignored = null) -> void:
		var text := title.text.strip_edges()
		if text and text != str(item.get("name", "")):
			_change("Rename background", func(g: Dictionary) -> void: g.backgrounds[index].name = text)
	title.text_submitted.connect(rename)
	title.focus_exited.connect(rename)
	row.add_child(title)
	var fit := OptionButton.new()
	for pair in FITS:
		fit.add_item(pair[1])
	fit.select(maxi(0, FITS.map(func(pair: Array) -> String: return pair[0]).find(item.get("fit", "cover"))))
	fit.item_selected.connect(func(choice: int) -> void:
		_change("Background fit", func(g: Dictionary) -> void: g.backgrounds[index].fit = FITS[choice][0])
	)
	row.add_child(fit)
	var file := _asset_file(str(item.get("asset", "")))
	var file_label := StyleKit.label(file if file else "missing file", 12, StyleKit.MUTED if file else StyleKit.RED)
	file_label.custom_minimum_size.x = 130
	file_label.clip_text = true
	row.add_child(file_label)
	for step in [[-1, "↑"], [1, "↓"]]:
		var target: int = index + step[0]
		var move := StyleKit.button(step[1], func() -> void:
			_change("Reorder backgrounds", func(g: Dictionary) -> void:
				var moved = g.backgrounds.pop_at(index)
				g.backgrounds.insert(target, moved)
			)
		)
		move.disabled = target < 0 or target >= count
		row.add_child(move)
	row.add_child(
		StyleKit.button(
			"✕",
			func() -> void: _change("Remove background", func(g: Dictionary) -> void: g.backgrounds.remove_at(index))
		)
	)
	return row


func _asset_file(asset_id: String) -> String:
	var asset = host.p.assets.get(asset_id)
	return str(asset.path).get_file() if asset is Dictionary else ""


## Adds a video or picture file as a background (also used for files dropped on Studio).
func add_background(path: String) -> void:
	var ext := path.get_extension().to_lower()
	if not ext in VIDEO_TYPES + IMAGE_TYPES:
		var hint := "  Convert .ogv videos to WebM first." if ext == "ogv" else ""
		host.tell("Backgrounds can be WebM or MP4 videos, or PNG, JPEG or WebP pictures." + hint)
		return
	var id: String = host.io.import_asset(path, host.p)
	if not id:
		host.tell(host.io.error)
		return
	_change("Add background", func(g: Dictionary) -> void:
		if not g.get("backgrounds") is Array:
			g.backgrounds = []
		g.backgrounds.append({"asset": id, "name": path.get_file().get_basename().capitalize(), "fit": "cover"})
	)


func _set_overlay(path: String) -> void:
	var id: String = host.io.import_asset(path, host.p)
	if not id:
		host.tell(host.io.error)
		return
	_change("Set overlay", func(g: Dictionary) -> void: g.overlay = id)


func _visitor_section(box: VBoxContainer) -> void:
	box.add_child(StyleKit.label("For visitors", 15, StyleKit.BLUE))
	var title := LineEdit.new()
	title.placeholder_text = host.p.title
	title.text = str(booth().get("title", ""))
	var retitle := func(_ignored = null) -> void:
		if title.text.strip_edges() != str(booth().get("title", "")):
			_change("Booth title", func(g: Dictionary) -> void: g.title = title.text.strip_edges())
	title.text_submitted.connect(retitle)
	title.focus_exited.connect(retitle)
	box.add_child(StyleKit.label("Title on the booth screen and download page", 12, StyleKit.MUTED))
	box.add_child(title)
	var flags := HFlowContainer.new()
	box.add_child(flags)
	for pair in [["photo", "Photos"], ["clip", "Short videos"], ["mirror", "Mirror the camera (selfie view)"]]:
		var check := CheckBox.new()
		check.text = pair[1]
		check.button_pressed = bool(_value(pair[0]))
		check.toggled.connect(func(on: bool) -> void: _change(pair[1], func(g: Dictionary) -> void: g[pair[0]] = on))
		flags.add_child(check)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for spec in [
		["countdown", "Countdown before a photo or video (s)", 0, 10],
		["clip_seconds", "Video length (s)", 2, 30],
		["keep_minutes", "Delete photos and videos after (min)", 1, 1440],
		["cycle_seconds", "Change background when nobody is there (s, 0 = never)", 0, 600],
	]:
		var label := StyleKit.label(spec[1], 12, StyleKit.MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = spec[2]
		spin.max_value = spec[3]
		spin.value = float(_value(spec[0]))
		spin.custom_minimum_size.x = 110
		spin.value_changed.connect(func(v: float) -> void:
			var apply := func(g: Dictionary) -> void: g[spec[0]] = int(v)
			_change(str(spec[1]).get_slice(" (", 0), apply, true)
		)
		grid.add_child(spin)


func _booth_section(box: VBoxContainer) -> void:
	box.add_child(StyleKit.label("Booth", 15, StyleKit.BLUE))
	var is_running := running()
	var networks := Tools.lan_addresses()
	var labels: Array = networks.map(func(pair: Array) -> String: return pair[1])
	var addresses: Array = networks.map(func(pair: Array) -> String: return pair[0])
	if not address in addresses:
		address = addresses[-1] if addresses.size() > 1 else addresses[0]
	var network: OptionButton = host.choice(box, "Who can download", labels, labels[addresses.find(address)])
	network.disabled = is_running
	network.item_selected.connect(func(i: int) -> void: address = addresses[i])
	var row := HFlowContainer.new()
	box.add_child(row)
	if is_running:
		row.add_child(StyleKit.button("Open booth", func() -> void: OS.shell_open(str(info.booth)), true))
		row.add_child(StyleKit.button("Booth setup", func() -> void: OS.shell_open(str(info.booth) + "&setup")))
		row.add_child(StyleKit.button("Save booth settings into this exhibit", save_into_exhibit))
		row.add_child(StyleKit.button("Delete visitor photos and videos now", _clear_captures))
		row.add_child(StyleKit.button("Stop booth", stop))
		box.add_child(StyleKit.label("Phones download from  " + str(info.get("download", "")), 13, StyleKit.BLUE))
		for warning in info.get("warnings", []):
			box.add_child(StyleKit.label(str(warning), 12, StyleKit.RED))
	else:
		row.add_child(StyleKit.button("Start booth", _start.bind(false), true))
		row.add_child(StyleKit.button("Start with setup", _start.bind(true)))
		if address == "127.0.0.1" and addresses.size() > 1:
			box.add_child(host.logic._muted("“This computer only” is for rehearsing; phones need the local network."))
	(
		box
		. add_child(
			(
				host
				. logic
				. _muted(
					"The booth opens in the browser on this computer, where the camera is connected; allow the camera when asked. On the booth: F full screen, ←/→ backgrounds, Space photo, R video, Ctrl+Shift+S setup."
				)
			)
		)
	)


# ----------------------------------------------------------------------------- service
func _start(open_setup: bool) -> void:
	if running() or _starting:
		return
	var current := booth()
	var backgrounds: Array = []
	for item in current.get("backgrounds", []):
		var asset = host.p.assets.get(str(item.get("asset", "")))
		if asset is Dictionary:
			var path: String = host.io.folder.path_join(asset.path)
			backgrounds.append({"name": item.get("name", ""), "fit": item.get("fit", "cover"), "path": path})
	if backgrounds.is_empty():
		host.tell("Add at least one background video or picture first.")
		return
	_starting = true
	var folder := Store.absolute("user://greenscreen")
	DirAccess.make_dir_recursive_absolute(folder)
	var stem := folder.path_join("run-" + Model.uid("b"))
	var settings := current.duplicate(true)
	settings.erase("backgrounds")
	settings.erase("overlay")
	if not settings.get("title"):
		settings.title = host.p.title
	var overlay = host.p.assets.get(str(current.get("overlay", "")))
	var run := {
		"settings": settings,
		"backgrounds": backgrounds,
		"overlay": host.io.folder.path_join(overlay.path) if overlay is Dictionary else "",
	}
	if Store.write_json(stem + ".json", run) != "":
		_fail("Could not prepare the booth files.")
		return
	var args := ["--config", stem + ".json", "--info", stem + "-service.json", "--bind", address]
	args.append_array(["--captures", folder.path_join("captures")])
	pid = Tools.spawn("tools/greenscreen.py", args)
	if pid <= 0:
		_fail("Python 3 is needed for the green-screen booth. Run setup again, or set OPENEXHIBIT_PYTHON.")
		return
	host.tell("Starting the green-screen booth…")
	for i in 80:
		await host.get_tree().create_timer(0.1).timeout
		var reply = Store.json_at(stem + "-service.json")
		if reply is Dictionary and reply.has("error"):
			_fail(str(reply.error))
			return
		if reply is Dictionary and reply.has("booth"):
			info = reply
			_starting = false
			host.refresh()
			host.tell("Booth running · phones download from " + str(info.download))
			if DisplayServer.get_name() != "headless":  # automated runs have no one to show the booth to
				OS.shell_open(str(info.booth) + ("&setup" if open_setup else ""))
			return
		if not OS.is_process_running(pid):
			break
	_fail("The booth did not start. Another program may be using ports 8788/8789, or the network address changed.")


func _fail(message: String) -> void:
	_starting = false
	shutdown()
	host.tell(message)
	host.refresh()


## Calls the running booth service: `path` under /api/, JSON `body` for POST (empty for GET).
func _call(path: String, body: String, done: Callable) -> void:
	var request := HTTPRequest.new()
	host.add_child(request)
	request.timeout = 5
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		request.queue_free()
		var reply = (
			JSON.parse_string(data.get_string_from_utf8())
			if result == HTTPRequest.RESULT_SUCCESS and code == 200
			else null
		)
		done.call(reply if reply is Dictionary else {})
	)
	var base := str(info.booth).get_slice("/booth#", 0)
	var headers := ["Authorization: Bearer " + str(info.booth).get_slice("#", 1)]
	if body:
		headers.append("Content-Type: application/json")
	request.request(base + path, headers, HTTPClient.METHOD_POST if body else HTTPClient.METHOD_GET, body)


func stop() -> void:
	if not running():
		return
	_call("/api/stop", "{}", func(_reply: Dictionary) -> void:
		shutdown()
		host.refresh()
		host.tell("Booth stopped. Visitors' photos and videos are deleted when they expire.")
	)


func _clear_captures() -> void:
	if running():
		_call("/api/captures/clear", "{}", func(reply: Dictionary) -> void:
			host.tell("Deleted %d visitor photo(s) and video(s)." % int(reply.get("deleted", 0)))
		)


## Copies the calibration made on the booth (camera, key colour, placement) into the exhibit.
func save_into_exhibit() -> void:
	if not running():
		return
	_call("/api/settings", "", func(reply: Dictionary) -> void:
		var settings = reply.get("settings")
		if not settings is Dictionary:
			host.tell("Could not read the settings from the booth.")
			return
		_change("Save booth settings", func(g: Dictionary) -> void:
			for key in CALIBRATION:
				if settings.has(key):
					g[key] = settings[key]
		)
		host.tell("Booth settings saved into the exhibit. Save the project to keep them.")
	)

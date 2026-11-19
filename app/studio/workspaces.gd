extends RefCounted
## Workspaces that edit the installation and content structure: Installation, 3D view,
## Projection, Timeline, Flipbook, Science, Media and Publish. Interactions, Hardware and
## Live audience have their own scripts. All edits go through host.mutate().

const StyleKit := preload("res://core/skin.gd")
const Model := preload("res://core/project.gd")
const Store := preload("res://core/storage.gd")
const Mapping := preload("res://core/mapping.gd")
const ModelView := preload("res://core/model_view.gd")
const Stage := preload("res://core/stage.gd")
const Feed := preload("res://core/feed.gd")
const Pad := preload("res://studio/calibration_pad.gd")
const CalibrationTools := preload("res://studio/calibration_tools.gd")
const RuleText := preload("res://studio/rule_text.gd")

const PATTERNS := ["Exhibit content", "Alignment grid", "Colour bars"]

var host
var calibration
var out_index := 0
var pattern := 0
var mesh_edit := false
var track_index := 0


func _init(owner) -> void:
	host = owner
	calibration = CalibrationTools.new(owner)


## Connects `callback` to `source` until `widget` leaves the tree (workspaces are rebuilt often).
func watch(source: Signal, widget: Node, callback: Callable) -> void:
	source.connect(callback)
	widget.tree_exiting.connect(func() -> void:
		if not source.is_null() and source.is_connected(callback):
			source.disconnect(callback)
	, CONNECT_ONE_SHOT)


func show_space(key: String, parent: Control) -> void:
	var box: VBoxContainer = host.logic._page(parent)
	match key:
		"Installation", "3D scene":
			installation(box, key == "3D scene")
		"Mapping":
			mapping(box)
		"Timeline":
			timeline(box)
		"Flipbook":
			book(box)
		"Science":
			science(box)
		"Assets":
			assets(box)
		"Deployment":
			deployment(box)


func heading(box: Control, title: String, text: String) -> void:
	host.logic._heading(box, title, text)


func note(box: Control, text: String) -> Label:
	var label: Label = host.logic._muted(text)
	box.add_child(label)
	return label


func row(box: Control) -> HFlowContainer:
	var flow := HFlowContainer.new()
	box.add_child(flow)
	return flow


func btn(box: Control, caption: String, action: Callable, accent := false) -> Button:
	var button := StyleKit.button(caption, action, accent)
	box.add_child(button)
	return button


func text_value(menu: OptionButton) -> String:
	return menu.get_item_text(menu.selected)


func json_value(text: String):
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else text


func out() -> Dictionary:
	out_index = clampi(out_index, 0, host.p.installation.outputs.size() - 1)
	return host.p.installation.outputs[out_index]


## Validated JSON editing for advanced settings that have no form yet.
func json_editor(title: String, original, apply: Callable) -> void:
	var box: VBoxContainer = host.dialog(title, 720, 620)
	var text := TextEdit.new()
	text.custom_minimum_size = Vector2(360, 380)
	text.text = JSON.stringify(original, "  ", false)
	box.add_child(text)
	var problem := note(box, "Changes are validated before they reach the project; invalid edits are refused.")
	btn(box, "Validate and apply", func() -> void:
		var parser := JSON.new()
		if parser.parse(text.text) != OK:
			problem.text = "Line %d · %s" % [parser.get_error_line(), parser.get_error_message()]
			return
		if typeof(parser.data) != typeof(original):
			problem.text = "Keep the original type (object or list)."
			return
		box.get_window().queue_free()
		host.mutate(title, apply.bind(parser.data))
	, true)


# ----------------------------------------------------------------------------- installation
func installation(box: VBoxContainer, scene3d: bool) -> void:
	heading(
		box,
		"3D view" if scene3d else "Installation",
		"Describe the physical room: screens, projectors and surfaces in metres. Drag to orbit, scroll to zoom."
	)
	var view := ModelView.new()
	view.custom_minimum_size.y = 280
	box.add_child(view)
	view.setup()
	view.installation(host.p.installation)
	if scene3d:
		for o in host.scene_data().objects:
			if o.kind == "model" and host.p.assets.has(o.get("asset", "")):
				var problem = view.load_model(host.io.folder.path_join(host.p.assets[o.asset].path))
				if problem:
					note(box, problem)
		btn(box, "Import 3D model…", host.import_media.bind("model"))
		note(box, "OBJ, glTF and GLB models can also be placed on a canvas scene as interactive objects.")
		return
	var surface: Dictionary = host.p.installation.surfaces[0]
	note(
		box,
		(
			"Current layout: %s · %d surfaces · %d outputs"
			% [
				host.p.installation.get("preset", "Custom"),
				host.p.installation.surfaces.size(),
				host.p.installation.outputs.size()
			]
		)
	)
	var layout: OptionButton = host.choice(
		box, "Layout preset", Mapping.PRESETS, host.p.installation.get("preset", "Kiosk")
	)
	var count: SpinBox = host.number(box, "Number of outputs (0 = the preset's usual count)", 0, 0, 32, 1)
	var radius: SpinBox = host.number(
		box, "Radius (m) — cylinders, spheres, domes", surface.get("radius", 2), 0.1, 100, 0.1
	)
	var height: SpinBox = host.number(box, "Physical height (m)", surface.get("height", 2.4), 0.1, 100, 0.1)
	var arc: SpinBox = host.number(box, "Cylinder coverage (degrees)", surface.get("arc", 180), 10, 360, 1)
	btn(box, "Apply layout", func() -> void:
		host.mutate("Change installation layout", func() -> void:
			host.p.installation = Mapping.make(
				text_value(layout), int(count.value), radius.value, height.value, arc.value
			)
			out_index = 0
		)
	, true)
	note(
		box,
		"Applying a layout replaces outputs and their calibration; Undo brings them back. Scenes are untouched, so the same content can move between installations."
	)
	if surface.kind in ["sphere", "dome"]:
		var layouts := ["equirectangular", "cubemap_cross"]
		var texture: OptionButton = host.choice(
			box, "Content format on the surface", layouts, surface.get("source_layout", "equirectangular")
		)
		texture.item_selected.connect(
			func(i: int) -> void: host.mutate("Set texture layout", func() -> void: surface.source_layout = layouts[i])
		)
	if surface.kind == "mesh":
		btn(box, "Attach UV-mapped surface mesh…", func() -> void:
			host.file_dialog("Attach UV-mapped surface", FileDialog.FILE_MODE_OPEN_FILE, ["*.obj,*.gltf,*.glb"], func(path: String) -> void:
				var id: String = host.io.import_asset(path, host.p)
				if id:
					host.mutate("Assign projection mesh", func() -> void: surface.asset = id)
				else:
					host.tell(host.io.error)
			)
		)
	btn(box, "Advanced: surface definitions (JSON)…", func() -> void:
		json_editor(
			"Surface definitions",
			host.p.installation.surfaces,
			func(value) -> void: host.p.installation.surfaces = value
		)
	)


# ----------------------------------------------------------------------------- projection
func mapping(box: VBoxContainer) -> void:
	heading(
		box,
		"Projection",
		"Check each output against the alignment grid, then drag the corner handles until it lines up with the surface."
	)
	var outputs: Array = host.p.installation.outputs
	var ids: Array = outputs.map(func(o: Dictionary) -> String: return o.id)
	var output := out()
	var chooser: OptionButton = host.choice(box, "Output", ids, output.id)
	chooser.item_selected.connect(func(i: int) -> void:
		out_index = i
		host.refresh()
	)
	var surface := Model.lookup(host.p.installation.surfaces, output.surface)
	note(
		box,
		(
			"%s · %s surface · screen %d · %d × %d px · optical calibration unverified until checked on site"
			% [surface.get("name", surface.id), surface.kind, output.screen, output.size[0], output.size[1]]
		)
	)
	var preview_mode: OptionButton = host.choice(box, "Show", PATTERNS, PATTERNS[pattern])
	var viewport := SubViewport.new()
	viewport.size = Vector2i(host.p.canvas[0], host.p.canvas[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(viewport)
	var stage := Stage.new()
	viewport.add_child(stage)
	stage.configure(host.session, host.io.folder, output.get("scene", "@live"), false, true)
	var frame := AspectRatioContainer.new()
	frame.ratio = float(output.size[0]) / output.size[1]
	frame.custom_minimum_size.y = 220
	box.add_child(frame)
	var feed := Feed.new()
	frame.add_child(feed)
	feed.custom_minimum_size = Vector2(160, 120)
	feed.pattern = pattern
	feed.configure(viewport, stage, output, surface, host.session, host.io.folder)
	preview_mode.item_selected.connect(func(i: int) -> void:
		pattern = i
		feed.pattern = i
		feed.calibrate()
	)
	var handles: OptionButton = host.choice(
		box,
		"Warp handles",
		["Corner pin (4 points)", "Mesh (3 × 3 points)"],
		"Mesh (3 × 3 points)" if mesh_edit else "Corner pin (4 points)"
	)
	handles.item_selected.connect(func(i: int) -> void:
		mesh_edit = i == 1
		host.refresh()
	)
	var pad := Pad.new()
	pad.custom_minimum_size.y = 150
	pad.points = (output.get("mesh", Mapping.lattice_default()) if mesh_edit else output.warp).duplicate(true)
	box.add_child(pad)
	pad.changed.connect(func(points: Array) -> void:
		host.mutate("Warp calibration", func() -> void:
			output["mesh" if mesh_edit else "warp"] = points
			output.erase("capture_check")
		, {"coalesce": true})
	)
	var actions := row(box)
	btn(actions, "Output settings…", output_settings)
	if surface.kind in ["sphere", "cylinder"]:
		btn(actions, "Coverage analysis", coverage.bind(surface))
	btn(actions, "Save calibration profile…", func() -> void:
		host.file_dialog("Save calibration profile", FileDialog.FILE_MODE_SAVE_FILE, ["*.json"], func(path: String) -> void:
			var problem := Store.write_json(
				path, {"format": "openexhibit-calibration", "version": 1, "installation": host.p.installation}
			)
			host.tell(problem if problem else "Saved calibration profile " + path)
		)
	)
	btn(actions, "Load calibration profile…", func() -> void:
		host.file_dialog("Load calibration profile", FileDialog.FILE_MODE_OPEN_FILE, ["*.json"], func(path: String) -> void:
			var profile = Store.json_at(path)
			if (
				profile is Dictionary
				and profile.get("format") == "openexhibit-calibration"
				and profile.get("version") == 1
				and profile.has("installation")
			):
				host.mutate(
					"Load calibration profile", func() -> void: host.p.installation = profile.installation
				)
			else:
				host.tell("Not a calibration profile.")
		)
	)
	btn(actions, "Save warped still (PNG)…", func() -> void:
		host.file_dialog(
			"Save warped output still",
			FileDialog.FILE_MODE_SAVE_FILE,
			["*.png"],
			save_still.bind(output, surface, viewport, stage)
		)
	)
	box.add_child(StyleKit.label("Measured calibration", 14, StyleKit.BLUE))
	var measured := row(box)
	if surface.kind == "plane":
		btn(measured, "Camera calibration wizard…", calibration.calibration_wizard.bind(output))
		btn(measured, "Apply measured warp…", func() -> void:
			host.file_dialog(
				"Measured planar warp",
				FileDialog.FILE_MODE_OPEN_FILE,
				["*.json"],
				func(path: String) -> void: calibration.import_warp(output, surface, path)
			)
		)
	btn(measured, "Import surveyed pose or luminance…", func() -> void:
		host.file_dialog(
			"Optical measurement report",
			FileDialog.FILE_MODE_OPEN_FILE,
			["*.json"],
			func(path: String) -> void: calibration.apply_optical(output, path)
		)
	)
	if output.has("capture_check"):
		note(box, "Measured check: %.3f px p95 on independent dots." % output.capture_check.independent_dots.p95_px)


func save_still(path: String, output: Dictionary, surface: Dictionary, viewport: SubViewport, stage) -> void:
	if DisplayServer.get_name() == "headless":
		host.tell("Image export needs a graphics display.")
		return
	var target := SubViewport.new()
	target.size = Vector2i(output.size[0], output.size[1])
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(target)
	var feed := Feed.new()
	target.add_child(feed)
	feed.size = Vector2(target.size)
	feed.pattern = pattern
	feed.configure(viewport, stage, output, surface, host.session, host.io.folder)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := target.get_texture().get_image()
	host.tell(
		"Saved warped still: " + path if image and image.save_png(path) == OK else "Could not export the output image."
	)
	target.queue_free()


func output_settings() -> void:
	var output := out()
	var box: VBoxContainer = host.dialog("Output " + output.id, 560, 680)
	var screen: SpinBox = host.number(box, "Screen number (0 = primary)", output.screen, 0, 63, 1)
	var width: SpinBox = host.number(box, "Width (px)", output.size[0], 32, 8192, 1)
	var height: SpinBox = host.number(box, "Height (px)", output.size[1], 32, 8192, 1)
	var scene_ids: Array = ["@live"] + host.p.scenes.map(func(s: Dictionary) -> String: return s.id)
	var scene_names: Array = (
		["Follows the visitor (live)"] + host.p.scenes.map(func(s: Dictionary) -> String: return "Always “%s”" % s.name)
	)
	var scene: OptionButton = host.choice(
		box, "Content", scene_names, scene_names[maxi(0, scene_ids.find(output.get("scene", "@live")))]
	)
	var gamma: SpinBox = host.number(box, "Gamma", output.get("gamma", 1), 0.1, 4)
	var black: SpinBox = host.number(box, "Black lift", output.get("black", 0), 0, 0.8, 0.01)
	var power: SpinBox = host.number(box, "Blend curve exponent", output.get("blend_power", 1), 0.1, 5)
	var throw_ratio: SpinBox = host.number(box, "Throw ratio", output.get("throw", 1), 0.02, 20, 0.01)
	var edges := []
	for j in 4:
		edges.append(
			host.number(box, "Blend width — " + ["left", "right", "top", "bottom"][j], output.blend[j], 0, 1, 0.01)
		)
	btn(box, "Apply", func() -> void:
		box.get_window().queue_free()
		host.mutate("Edit output", func() -> void:
			output.screen = int(screen.value)
			output.size = [width.value, height.value]
			output.scene = scene_ids[scene.selected]
			output.gamma = gamma.value
			output.black = black.value
			output.blend_power = power.value
			output.throw = throw_ratio.value
			for j in 4:
				output.blend[j] = edges[j].value
		)
	, true)
	btn(box, "Advanced: position, aim, lens shift, gain, mask, view (JSON)…", func() -> void:
		box.get_window().queue_free()
		json_editor(
			"Output calibration", output, func(value) -> void: host.p.installation.outputs[out_index] = value
		)
	)


func coverage(surface: Dictionary) -> void:
	var box: VBoxContainer = host.dialog("Projector coverage", 700, 500)
	var image := Image.create_empty(144, 72, false, Image.FORMAT_RGB8)
	var total := 0.0
	var dark := 0.0
	var overlap := 0.0
	var centre := Mapping.v3(surface.get("position", [0, 0, 0]))
	var outputs: Array = host.p.installation.outputs.filter(func(o: Dictionary) -> bool: return o.surface == surface.id)
	for y in 72:
		var latitude := PI * (0.5 - (y + 0.5) / 72)
		var weight := cos(latitude) if surface.kind == "sphere" else 1.0
		for x in 144:
			var angle := ((x + 0.5) / 144 - 0.5) * (TAU if surface.kind == "sphere" else deg_to_rad(surface.arc))
			var point := Vector3(sin(angle) * surface.radius, 0, cos(angle) * surface.radius)
			if surface.kind == "sphere":
				point = Vector3(point.x * cos(latitude), surface.radius * sin(latitude), point.z * cos(latitude))
			else:
				point.y = (0.5 - (y + 0.5) / 72) * surface.height
			var count := 0
			for o in outputs:
				if Mapping.sees(Mapping.local_frame(surface) * point + centre, o, surface):
					count += 1
			image.set_pixel(x, y, [Color("#a54850"), Color("#3fb950"), Color("#d29922")][mini(2, count)])
			total += weight
			if count == 0:
				dark += weight
			elif count > 1:
				overlap += weight
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(image)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.custom_minimum_size.y = 260
	box.add_child(picture)
	note(box, "Red = unlit · green = one projector · amber = overlap (blend zone)")
	note(box, "Unlit %.1f%% · overlap %.1f%%" % [100 * dark / total, 100 * overlap / total])
	if surface.kind == "sphere":
		for pole in [1, -1]:
			var covered := false
			for o in outputs:
				covered = covered or Mapping.sees(centre + Vector3(0, surface.radius * pole, 0), o, surface)
			note(box, ("North" if pole > 0 else "South") + " pole: " + ("covered" if covered else "unlit"))
	note(box, "Ideal geometry before masking. Shadows from visitors, mounts and nearby objects need an on-site check.")


# ----------------------------------------------------------------------------- timeline
func timeline(box: VBoxContainer) -> void:
	heading(
		box,
		"Timeline",
		"Cues fire while the timeline plays forward. Scrubbing previews animation and always switches device outputs off."
	)
	var bar := row(box)
	btn(bar, "+  New timeline", func() -> void:
		host.mutate("Add timeline", func() -> void:
			host.p.timelines.append(
				{
					"id": Model.uid("show"),
					"name": "New show",
					"duration": 30,
					"loop": false,
					"cues": [],
					"keys": []
				}
			)
			track_index = host.p.timelines.size() - 1
		)
	, true)
	if host.p.timelines.is_empty():
		note(
			box,
			"A timeline can change scenes, set variables, trigger devices and animate objects at set times — for example a looping attract mode or a narrated show."
		)
		return
	track_index = clampi(track_index, 0, host.p.timelines.size() - 1)
	var track: Dictionary = host.p.timelines[track_index]
	var names: Array = host.p.timelines.map(func(t: Dictionary) -> String: return str(t.get("name", t.id)))
	var chooser: OptionButton = host.choice(box, "Timeline", names, names[track_index])
	chooser.item_selected.connect(func(i: int) -> void:
		track_index = i
		host.refresh()
	)
	var transport := row(box)
	btn(transport, "▶  Play from start", func() -> void: host.session.play(track.id), true)
	btn(transport, "Pause / resume", func() -> void:
		if host.session.timeline == track.id:
			host.session.playing = not host.session.playing
	)
	var readout := StyleKit.label("0.00 / %.2f s" % track.duration, 13, StyleKit.BLUE)
	box.add_child(readout)
	var scrub := HSlider.new()
	scrub.max_value = track.duration
	scrub.step = 0.01
	box.add_child(scrub)
	scrub.value_changed.connect(func(x: float) -> void:
		host.session.timeline = track.id
		host.session.seek(x)
	)
	watch(host.session.clock_changed, scrub, func() -> void:
		if is_instance_valid(scrub) and host.session.timeline == track.id:
			scrub.set_value_no_signal(host.session.head)
			readout.text = "%.2f / %.2f s" % [host.session.head, track.duration]
	)
	var edit := row(box)
	btn(edit, "+  Cue at playhead…", func() -> void: cue_form(track, scrub.value))
	btn(edit, "+  Animation key at playhead…", func() -> void: key_form(track, scrub.value))
	btn(
		edit,
		"Duration, loop and all entries (JSON)…",
		func() -> void: json_editor("Timeline", track, func(value) -> void: host.p.timelines[track_index] = value)
	)
	box.add_child(StyleKit.label("Cues", 14, StyleKit.BLUE))
	var cues: Array = track.get("cues", []).duplicate()
	cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)
	if cues.is_empty():
		note(box, "No cues yet.")
	for cue in cues:
		var line := HBoxContainer.new()
		box.add_child(line)
		var label := StyleKit.label("%7.2f s   %s" % [cue.at, RuleText.action(host.p, cue.action)], 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		line.add_child(
			StyleKit.button("✕", func() -> void: host.mutate("Delete cue", func() -> void: track.cues.erase(cue)))
		)
	box.add_child(StyleKit.label("Animation keys", 14, StyleKit.BLUE))
	if track.get("keys", []).is_empty():
		note(box, "No animation keys yet. Two keys on the same property animate between them.")
	for key in track.get("keys", []):
		var line := HBoxContainer.new()
		box.add_child(line)
		var label := StyleKit.label(
			(
				"%7.2f s   %s.%s = %s  (%s)"
				% [key.at, key.object, key.property, str(key.value), key.get("curve", "linear")]
			),
			13
		)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		line.add_child(
			StyleKit.button("✕", func() -> void: host.mutate("Delete key", func() -> void: track.keys.erase(key)))
		)
	host.logic.monitor(box)


func cue_form(track: Dictionary, at: float) -> void:
	var box: VBoxContainer = host.dialog("Add cue", 480, 420)
	var when: SpinBox = host.number(box, "Time (seconds)", at, 0, track.duration, 0.01)
	var ops: Array = RuleText.ACTIONS.keys()
	var labels: Array = ops.map(func(op: String) -> String: return RuleText.ACTIONS[op])
	var operation: OptionButton = host.choice(box, "Action", labels, labels[ops.find("goto")])
	var target: LineEdit = host.field(box, "Target — scene ID, variable, output channel or event", host.edit_scene)
	var value: LineEdit = host.field(box, "Value (where the action uses one)", "1")
	btn(box, "Add cue", func() -> void:
		box.get_window().queue_free()
		host.mutate("Add cue", func() -> void:
			track.cues.append(
				{
					"at": when.value,
					"action":
					{
						"op": ops[operation.selected],
						"target": target.text.strip_edges(),
						"value": json_value(value.text)
					}
				}
			)
		)
	, true)


func key_form(track: Dictionary, at: float) -> void:
	var objects: Array = host.scene_data().objects
	if objects.is_empty():
		host.tell("Add a layer to this scene first.")
		return
	var ids: Array = objects.map(func(o: Dictionary) -> String: return o.id)
	var box: VBoxContainer = host.dialog("Add animation key", 480, 460)
	var object: OptionButton = host.choice(box, "Layer", ids, host.selected)
	var property: OptionButton = host.choice(box, "Property", ["x", "y", "opacity", "rotation"])
	var when: SpinBox = host.number(box, "Time (seconds)", at, 0, track.duration, 0.01)
	var value: SpinBox = host.number(box, "Value", 0, -8192, 8192, 0.01)
	var curve: OptionButton = host.choice(box, "Easing to the next key", ["linear", "smooth", "step"])
	btn(box, "Add key", func() -> void:
		box.get_window().queue_free()
		host.mutate("Add animation key", func() -> void:
			track.keys.append(
				{
					"at": when.value,
					"scene": host.edit_scene,
					"object": text_value(object),
					"property": text_value(property),
					"value": value.value,
					"curve": text_value(curve)
				}
			)
		)
	, true)


# ----------------------------------------------------------------------------- flipbook
func book(box: VBoxContainer) -> void:
	heading(
		box,
		"Flipbook",
		"Each scene is a page. Arrange them, then press Build page navigation to add next/previous buttons, arrow keys, swipes and page sensors."
	)
	for scene in host.p.scenes:
		var line := HBoxContainer.new()
		box.add_child(line)
		var open := StyleKit.button(str(scene.name), func() -> void:
			host.edit_scene = scene.id
			host.selected = ""
			host.set_space("Canvas")
		)
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		line.add_child(open)
	var actions := row(box)
	btn(actions, "+  Blank page", host.add_scene)
	btn(actions, "+  Page from image…", func() -> void:
		host.file_dialog(
			"Import page image", FileDialog.FILE_MODE_OPEN_FILE, ["*.jpg,*.jpeg,*.png,*.webp"], image_page
		)
	)
	btn(actions, "Build page navigation", link_book, true)
	note(
		box,
		"Whole PDFs: python3 tools/import_pdf.py book.pdf new-book-folder (needs Poppler). The Player turns pages with ←/→ keys, swipes, on-screen buttons or a page sensor sending its page number."
	)


func image_page(path: String) -> void:
	var id: String = host.io.import_asset(path, host.p)
	if not id:
		host.tell(host.io.error)
		return
	host.mutate("Add book page", func() -> void:
		var page := Model.uid("page")
		host.p.scenes.append(
			{
				"id": page,
				"name": path.get_file().get_basename(),
				"transition": "slide",
				"objects":
				[
					{
						"id": "page_art",
						"kind": "image",
						"asset": id,
						"rect": [0, 0, host.p.canvas[0], host.p.canvas[1]]
					}
				]
			}
		)
		host.edit_scene = page
	)


## Rebuilds page navigation: on-screen buttons, arrow-key/swipe rules and page-sensor rules.
## Re-running it replaces the previous navigation (everything with the booklink_ prefix).
func link_book() -> void:
	host.mutate("Build page navigation", func() -> void:
		var scenes: Array = host.p.scenes
		var canvas: Array = host.p.canvas
		host.p.rules = host.p.rules.filter(
			func(r: Dictionary) -> bool: return not str(r.id).begins_with("booklink_")
		)
		for j in scenes.size():
			var page: Dictionary = scenes[j]
			page.objects = page.objects.filter(
				func(o: Dictionary) -> bool: return not o.id in ["booklink_prev", "booklink_next"]
			)
			for side in ["prev", "next"]:
				var destination: String = scenes[clampi(j + (-1 if side == "prev" else 1), 0, scenes.size() - 1)].id
				var event := "book.%s.%s" % [side, page.id]
				page.objects.append(
					{
						"id": "booklink_" + side,
						"kind": "button",
						"text": "‹" if side == "prev" else "›",
						"event": event,
						"rect": [12 if side == "prev" else canvas[0] - 82, canvas[1] - 70, 70, 56]
					}
				)
				host.p.rules.append(
					{
						"id": Model.uid("booklink_nav"),
						"event": event,
						"actions": [{"op": "goto", "target": destination}]
					}
				)
				host.p.rules.append(
					{
						"id": Model.uid("booklink_key"),
						"event": "book." + side,
						"if": {"left": "$current_page", "op": "==", "right": page.id},
						"actions": [{"op": "emit", "target": event}]
					}
				)
			host.p.rules.append(
				{
					"id": Model.uid("booklink_enter"),
					"event": "enter." + page.id,
					"actions": [{"op": "set", "target": "current_page", "value": page.id}]
				}
			)
			host.p.rules.append(
				{
					"id": Model.uid("booklink_sensor"),
					"event": "input.page",
					"if": {"op": "==", "right": j + 1},
					"actions": [{"op": "goto", "target": page.id}]
				}
			)
		host.p.variables.current_page = host.p.start
	)


# ----------------------------------------------------------------------------- science
func science(box: VBoxContainer) -> void:
	heading(
		box, "Science", "Add a live model to the current scene, then bind it to a variable or sensor in the Inspector."
	)
	var items := [
		[
			"orbit",
			"Solar system",
			"Eight planets move with their real relative orbital periods (sizes and distances illustrative)."
		],
		["plot", "Live chart", "Plots the last 160 samples from a sensor channel."],
		["gauge", "Gauge", "Shows a numeric variable on a bounded scale."],
		[
			"particles",
			"Particle field",
			"Particles stream from a point set by motion_x and motion_y (0–1), e.g. from a camera."
		],
		["fractal", "Sierpiński triangle", "Recursion depth follows a variable from 0 to 7."],
		["grid", "Grid pattern", "A reference grid for alignment and scale."],
	]
	for item in items:
		var line := HBoxContainer.new()
		box.add_child(line)
		var add := StyleKit.button("+  " + item[1], host.add_object.bind(item[0]))
		add.custom_minimum_size.x = 200
		line.add_child(add)
		var text := StyleKit.label(item[2], 12, StyleKit.MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
	note(
		box,
		"External simulations can feed values in through the hardware service (OSC, JSON lines, MQTT) — see docs/PLUGINS.md."
	)


# ----------------------------------------------------------------------------- media
func assets(box: VBoxContainer) -> void:
	heading(
		box,
		"Media",
		"Files are copied into the exhibit's assets folder and checked by SHA-256 when it opens or is exported."
	)
	var bar := row(box)
	for kind in ["image", "audio", "video", "model"]:
		btn(
			bar,
			"+  " + {"image": "Image", "audio": "Sound", "video": "Video (.ogv)", "model": "3D model"}[kind],
			host.import_media.bind(kind)
		)
	if host.p.assets.is_empty():
		note(box, "No media yet. You can also drag files onto the Studio window.")
	for id in host.p.assets:
		var asset: Dictionary = host.p.assets[id]
		var line := HBoxContainer.new()
		box.add_child(line)
		var label := StyleKit.label(str(asset.path).get_file().substr(17), 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		line.add_child(StyleKit.label(str(asset.sha256).left(12), 11, StyleKit.MUTED))
	note(box, "Videos must be Ogg Theora:  ffmpeg -i input.mp4 -c:v libtheora -q:v 7 -c:a libvorbis output.ogv")


# ----------------------------------------------------------------------------- publish
func deployment(box: VBoxContainer) -> void:
	heading(
		box,
		"Publish",
		"Export a single .oex package and open it with the Player on any exhibit computer. The Player does not need Studio."
	)
	for o in host.p.installation.outputs:
		note(
			box,
			(
				"%s → screen %d · %d × %d px · %s"
				% [
					o.id,
					o.screen,
					o.size[0],
					o.size[1],
					"follows the visitor" if o.get("scene", "@live") == "@live" else "fixed scene"
				]
			)
		)
	var actions := row(box)
	btn(actions, "Export .oex package…", host.pack_project, true)
	btn(actions, "Verify media checksums", func() -> void:
		var problem := Model.validate(host.p)
		for asset in host.p.assets.values():
			if FileAccess.get_sha256(host.io.folder.path_join(asset.path)) != asset.sha256:
				problem = "Changed or missing file: " + str(asset.path)
				break
		host.tell(problem if problem else "All %d media files verified." % host.p.assets.size())
	)
	btn(actions, "Open in the Player (preview)", launch_player)
	box.add_child(StyleKit.label("On the exhibit computer", 14, StyleKit.BLUE))
	var commands := TextEdit.new()
	commands.editable = false
	commands.custom_minimum_size.y = 120
	commands.text = "bash player.sh exhibit.oex --kiosk              # Linux, full screen, keys locked\nPlayer.cmd exhibit.oex --kiosk                   # Windows\n# start at login: packaging/openexhibit-player.service (systemd user unit)\n# Player keys: F2 test patterns · F5 reset visit · F10 operator panel · F12 outputs off"
	box.add_child(commands)


func launch_player() -> void:
	var path := Store.absolute("user://previews/" + Model.uid("exhibit") + ".oex")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if not host.io.pack(host.p, path):
		host.tell(host.io.error)
		return
	var engine := OS.get_executable_path()
	var args := []
	var pack := engine.get_base_dir().path_join("player.pck")
	if FileAccess.file_exists(pack):
		args = ["--main-pack", pack]
	elif OS.has_feature("editor") or FileAccess.file_exists(ProjectSettings.globalize_path("res://project.godot")):
		args = ["--path", ProjectSettings.globalize_path("res://"), "res://player/player.tscn"]
	else:
		var sibling := engine.get_base_dir().path_join(
			"OpenExhibitPlayer" + (".exe" if OS.get_name() == "Windows" else "")
		)
		if not FileAccess.file_exists(sibling):
			host.tell("Install the Player next to Studio to preview.")
			return
		engine = sibling
	args.append_array(["--", "--project", path])
	var pid := OS.create_process(engine, PackedStringArray(args))
	host.tell(
		"Player opened (process %d). Close its window to return." % pid if pid > 0 else "Could not open the Player."
	)

extends RefCounted
## Live audience workspace — AhaSlides-style sessions on visitors' phones.
## Studio starts the local session service (tools/quiz.py), opens its slide editor and
## presenter console in the browser, and can save the edited slides back into the exhibit.
## The service is stopped automatically when Studio closes.

const StyleKit := preload("res://core/skin.gd")
const Store := preload("res://core/storage.gd")
const Model := preload("res://core/project.gd")
const Tools := preload("res://core/tools.gd")

const SAMPLES := [
	["tools/contest/decks/science-show.quiz.json", "Sample: interactive science talk (all slide types)"],
	["tools/contest/museum.quiz.json", "Sample: team quiz contest"],
]

var host
var info := {}
var pid := -1
var address := "127.0.0.1"
var self_paced := false
var database := ""
var _starting := false


func _init(owner) -> void:
	host = owner


func running() -> bool:
	if pid > 0 and not OS.is_process_running(pid):
		pid = -1
		info = {}
	return pid > 0 and info.has("host")


func shutdown() -> void:
	Tools.stop(pid)
	pid = -1
	info = {}


func deck() -> Dictionary:
	return host.p.get("extensions", {}).get("contest", {})


func show(parent: Control) -> void:
	var box: VBoxContainer = host.logic._page(parent)
	(
		host
		. logic
		. _heading(
			box,
			"Live audience",
			"Polls, quizzes, word clouds, open-ended ideas, Q&A and a spinner wheel. Visitors join on their phones over this local network — no app, no account, no internet."
		)
	)
	_slides_section(box)
	box.add_child(HSeparator.new())
	_session_section(box)
	box.add_child(HSeparator.new())
	box.add_child(StyleKit.label("On a projection surface", 15, StyleKit.BLUE))
	(
		box
		. add_child(
			(
				host
				. logic
				. _muted(
					"The presenter's “Projector” window is an ordinary browser page. For a warped or edge-blended projection, add the live board to a scene; the Player renders it through that output's calibration."
				)
			)
		)
	)
	box.add_child(StyleKit.button("Add live audience board to this scene", host.add_object.bind("contest")))


func _slides_section(box: VBoxContainer) -> void:
	box.add_child(StyleKit.label("Slides", 15, StyleKit.BLUE))
	var current := deck()
	if current.is_empty():
		(
			box
			. add_child(
				(
					host
					. logic
					. _muted(
						"This exhibit has no slides of its own yet. Start from a sample, edit it, then save it into the exhibit."
					)
				)
			)
		)
	else:
		box.add_child(
			StyleKit.label(
				(
					"“%s” · %d slides — saved in this exhibit"
					% [current.get("title", ""), current.get("questions", []).size()]
				),
				13
			)
		)
	var row := HFlowContainer.new()
	box.add_child(row)
	row.add_child(StyleKit.button("Edit slides", open_page.bind("/edit"), true))
	if running():
		row.add_child(StyleKit.button("Save slides into this exhibit", save_into_exhibit))
	row.add_child(StyleKit.button("Import slides file…", func() -> void:
		host.file_dialog(
			"Import slides (.quiz.json)", FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; Slide decks"], _import_file
		)
	))
	if current.is_empty() or not running():
		for sample in SAMPLES:
			if FileAccess.file_exists(Tools.path(sample[0])):
				row.add_child(StyleKit.button(sample[1], _import_file.bind(Tools.path(sample[0]))))
	(
		box
		. add_child(
			(
				host
				. logic
				. _muted(
					"In the editor: add slides from the gallery, paste questions in Aiken format, or import PowerPoint/PDF pages. Changes save to the running session automatically; “Save slides into this exhibit” stores them in the project file."
				)
			)
		)
	)


func _session_section(box: VBoxContainer) -> void:
	box.add_child(StyleKit.label("Session", 15, StyleKit.BLUE))
	var is_running := running()
	var networks := Tools.lan_addresses()
	var labels: Array = networks.map(func(pair: Array) -> String: return pair[1])
	var addresses: Array = networks.map(func(pair: Array) -> String: return pair[0])
	if not address in addresses:
		address = addresses[-1] if addresses.size() > 1 else addresses[0]
	var network: OptionButton = host.choice(box, "Who can join", labels, labels[addresses.find(address)])
	network.disabled = is_running
	network.item_selected.connect(func(i: int) -> void: address = addresses[i])
	var mode: OptionButton = host.choice(
		box,
		"Pace",
		["Presenter-led (you move the slides)", "Self-paced (each person moves on their own)"],
		"Self-paced (each person moves on their own)" if self_paced else "Presenter-led (you move the slides)"
	)
	mode.disabled = is_running
	mode.item_selected.connect(func(i: int) -> void: self_paced = i == 1)
	var row := HFlowContainer.new()
	box.add_child(row)
	if is_running:
		row.add_child(StyleKit.button("Present (presenter + projector)", present, true))
		row.add_child(StyleKit.button("Projector window only", open_page.bind("/display")))
		row.add_child(StyleKit.button("Stop session", stop))
		box.add_child(
			StyleKit.label(
				"Phones join at  %s   ·   room code %s" % [info.get("join", ""), info.get("code", "")],
				13,
				StyleKit.BLUE
			)
		)
		box.add_child(
			host.logic._muted(
				(
					"Answers are stored in "
					+ database
					+ ". Keep this file to export results later (Resume a saved session)."
				)
			)
		)
	else:
		row.add_child(StyleKit.button("Start session and present", present, true))
		row.add_child(StyleKit.button("Resume a saved session…", func() -> void:
			host.file_dialog("Resume session database", FileDialog.FILE_MODE_OPEN_FILE, ["*.sqlite ; Session databases"], func(path: String) -> void:
				database = path
				_start(database, "/host")
			)
		))
		if address == "127.0.0.1" and addresses.size() > 1:
			box.add_child(
				host.logic._muted(
					"“This computer only” is for rehearsing. Choose the local network so phones can join."
				)
			)
		elif addresses.size() == 1:
			(
				box
				. add_child(
					(
						host
						. logic
						. _muted(
							"No local network found. Connect to Wi-Fi or Ethernet so phones can reach this computer; guest networks that isolate devices will not work."
						)
					)
				)
			)


func _import_file(path: String) -> void:
	var data = Store.json_at(path)
	if not (
		data is Dictionary
		and data.get("format") == "oes-quiz"
		and data.get("questions") is Array
		and data.questions.size()
	):
		host.tell("Not a slides file (expected an oes-quiz .json).")
		return
	host.mutate("Import slides", func() -> void:
		if not host.p.has("extensions"):
			host.p.extensions = {}
		host.p.extensions.contest = data
	)
	if running():
		host.tell("Slides imported into the exhibit. Stop and start the session to use them.")


## Opens a page of the running session (starting the service first if needed).
func open_page(page: String) -> void:
	if running():
		OS.shell_open(_url(page))
	else:
		_start("", page)


func present() -> void:
	if not running():
		_start(database, "present")
		return
	OS.shell_open(_url("/host"))


func _url(page: String) -> String:
	if page == "/display":
		return str(info.get("display", ""))
	return str(info.host).replace("/host#", page + "#")


func _start(existing_db: String, then_open: String) -> void:
	if running() or _starting:
		return
	_starting = true
	var folder := Store.absolute("user://sessions")
	DirAccess.make_dir_recursive_absolute(folder)
	var stem := folder.path_join(Time.get_datetime_string_from_system().replace(":", "-") + "-" + Model.uid("s"))
	database = existing_db if existing_db else stem + ".sqlite"
	var info_file := stem + "-service.json"
	var args := ["--db", database, "--info", info_file, "--bind", address]
	if self_paced:
		args.append("--self-paced")
	var slides := deck()
	if not slides.is_empty():
		var deck_file := stem + "-slides.json"
		if Store.write_json(deck_file, slides) != "":
			_fail("Could not stage the slides for the session.")
			return
		args.append_array(["--deck", deck_file])
	else:
		args.append_array(["--deck", Tools.path(SAMPLES[0][0])])
	pid = Tools.spawn("tools/quiz.py", args)
	if pid <= 0:
		_fail("Python 3 is needed for live audience sessions. Run setup again, or set OPENEXHIBIT_PYTHON.")
		return
	host.tell("Starting the live audience service…")
	for i in 80:
		await host.get_tree().create_timer(0.1).timeout
		var reply = Store.json_at(info_file)
		if reply is Dictionary and reply.has("error"):
			_fail(str(reply.error))
			return
		if reply is Dictionary and reply.has("host"):
			info = reply
			_starting = false
			host.refresh()
			host.tell("Live session running · phones join at " + str(info.join))
			if then_open == "present":
				OS.shell_open(_url("/host"))
			else:
				OS.shell_open(_url(then_open))
			return
		if not OS.is_process_running(pid):
			break
	_fail(
		"The live audience service did not start. Another program may be using ports 8786/8787, or the selected network address changed."
	)


func _fail(message: String) -> void:
	_starting = false
	shutdown()
	host.tell(message)
	host.refresh()


func stop() -> void:
	if not running():
		return
	var request := HTTPRequest.new()
	host.add_child(request)
	request.timeout = 4
	request.request_completed.connect(func(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		request.queue_free()
		shutdown()
		host.refresh()
		host.tell("Live session stopped. Its answers stay in " + database)
	)
	var token := str(info.host).get_slice("#", 1)
	request.request(
		str(info.host).get_slice("/host#", 0) + "/api/host/stop",
		["Content-Type: application/json", "Authorization: Bearer " + token],
		HTTPClient.METHOD_POST,
		"{}"
	)


## Reads the slides from the running session (as edited in the browser) into the project.
func save_into_exhibit() -> void:
	if not running():
		return
	var request := HTTPRequest.new()
	host.add_child(request)
	request.timeout = 5
	request.body_size_limit = 16 * 1024 * 1024
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		var state = (
			JSON.parse_string(body.get_string_from_utf8())
			if result == HTTPRequest.RESULT_SUCCESS and code == 200
			else null
		)
		if not (state is Dictionary and state.get("deck") is Dictionary):
			host.tell("Could not read the slides from the session.")
			return
		host.mutate("Save slides into exhibit", func() -> void:
			if not host.p.has("extensions"):
				host.p.extensions = {}
			host.p.extensions.contest = state.deck
		)
		host.tell("Slides saved into the exhibit. Save the project to keep them.")
	)
	var token := str(info.host).get_slice("#", 1)
	request.request(str(info.host).get_slice("/host#", 0) + "/api/host/state", ["Authorization: Bearer " + token])

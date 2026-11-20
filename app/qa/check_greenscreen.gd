extends SceneTree
## Studio and the green-screen booth service together: start the booth from the Green screen
## workspace, read it over its API, save calibration made on the booth back into the exhibit (with
## undo), clear captures and stop it. Needs Python 3; run without network sandboxing:
##   godot --headless --path app --script res://qa/check_greenscreen.gd -- --examples ../examples \
##       --project ../examples/16-green-screen/project.oes.json

const Studio = preload("res://studio/studio.tscn")
var failures := 0


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func _initialize() -> void:
	call_deferred("run")


func wait_until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + seconds * 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


## Calls the booth service directly, as the booth page would. `booth_url` carries the token.
func call_booth(booth_url: String, path: String, body := "") -> Dictionary:
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = 3
	var base := booth_url.get_slice("/booth#", 0)
	var headers := ["Authorization: Bearer " + booth_url.get_slice("#", 1)]
	if body:
		headers.append("Content-Type: application/json")
	request.request(base + path, headers, HTTPClient.METHOD_POST if body else HTTPClient.METHOD_GET, body)
	var reply: Array = await request.request_completed
	request.queue_free()
	if reply[0] != HTTPRequest.RESULT_SUCCESS or reply[1] != 200:
		return {}
	var data = JSON.parse_string((reply[3] as PackedByteArray).get_string_from_utf8())
	return data if data is Dictionary else {}


func run() -> void:
	var editor = Studio.instantiate()
	root.add_child(editor)
	await process_frame
	editor.set_space("Green screen")
	check(editor.greenscreen.booth().get("backgrounds", []).size() == 3, "example booth has three backgrounds")
	editor.greenscreen._start(false)
	var started: bool = await wait_until(func() -> bool: return editor.greenscreen.running(), 15)
	check(started, "Studio starts the booth service")
	if not started:
		quit(1)
		return
	var url := str(editor.greenscreen.info.booth)
	var booth := await call_booth(url, "/api/booth")
	var names: Array = booth.get("backgrounds", []).map(func(b: Dictionary) -> String: return b.name)
	check(names == ["Deep space", "Under the sea", "Sunset hills"], "booth serves the exhibit's backgrounds")
	check(booth.get("settings", {}).get("title") == "Step into another world", "booth uses the exhibit's title")

	var calibration := {"settings": {"key": {"color": "#10a050", "tolerance": 0.33}, "mirror": false}}
	var saved := await call_booth(url, "/api/settings", JSON.stringify(calibration))
	check(saved.get("settings", {}).get("key", {}).get("tolerance") == 0.33, "booth setup changes are accepted")
	editor.greenscreen.save_into_exhibit()
	var copied: bool = await wait_until(
		func() -> bool: return editor.greenscreen.booth().get("key", {}).get("tolerance") == 0.33, 5
	)
	check(copied, "Save booth settings into this exhibit copies the calibration")
	check(editor.greenscreen.booth().get("mirror") == false, "calibration includes the mirror setting")
	check(editor.dirty, "saving calibration marks the exhibit changed")
	editor.undo()
	check(not editor.greenscreen.booth().has("key"), "undo removes the copied calibration")

	var cleared := await call_booth(url, "/api/captures/clear", "{}")
	check(cleared.get("deleted") == 0, "capture clearing answers")
	editor.greenscreen.stop()
	var stopped: bool = await wait_until(func() -> bool: return editor.greenscreen.pid == -1, 10)
	check(stopped and (await call_booth(url, "/api/booth")).is_empty(), "Stop booth ends the service")
	print("RESULT green-screen Studio checks, ", failures, " failures.")
	quit(1 if failures else 0)

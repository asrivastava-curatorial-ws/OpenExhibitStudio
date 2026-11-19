extends RefCounted
## Bridges between the Projection workspace and the measurement tools: launches the camera
## calibration wizard and imports its measured reports (planar warp, surveyed pose, luminance).
## Reports are accepted only when they match the output and stay within their own limits.

const Store := preload("res://core/storage.gd")
const Model := preload("res://core/project.gd")
const Tools := preload("res://core/tools.gd")

var host


func _init(owner) -> void:
	host = owner


func calibration_wizard(output: Dictionary) -> void:
	var check := ["-c", "import tkinter, numpy, PIL, cv2"]
	var py := Tools.python()
	if OS.execute(py[0], PackedStringArray(py[1] + check), [], true) != 0:
		host.tell("The calibration wizard needs Python with Tk, NumPy, Pillow and OpenCV — see docs/CALIBRATION.md.")
		return
	var pid := Tools.spawn(
		"tools/calibration_wizard.py", ["--size", str(int(output.size[0])), str(int(output.size[1]))]
	)
	host.tell("Camera calibration wizard opened." if pid > 0 else "The calibration wizard could not start.")


func import_warp(output: Dictionary, surface: Dictionary, path: String) -> void:
	var report = Store.json_at(path)
	var matches: bool = (
		surface.kind == "plane"
		and report is Dictionary
		and report.get("format") == "oes-measured-warp"
		and report.get("version") == 1
		and report.get("size") == output.size
		and report.get("status") == "capture-validated"
		and report.get("warp") is Array
	)
	if not matches:
		host.tell("Choose a measured planar warp made for this output's pixel size.")
		return
	for key in ["independent_dots", "spatial_holdout"]:
		var measured = report.get(key)
		var limits = report.get("limits")
		var complete: bool = (
			measured is Dictionary
			and limits is Dictionary
			and Model.numeric(measured.get("p95_px"))
			and Model.numeric(measured.get("max_px"))
			and Model.numeric(limits.get("p95_px"))
			and Model.numeric(limits.get("max_px"))
		)
		if not complete:
			host.tell("The calibration report has incomplete residual measurements.")
			return
		var plausible: bool = (
			measured.p95_px >= 0
			and measured.max_px >= measured.p95_px
			and limits.p95_px > 0
			and limits.p95_px <= 10
			and limits.max_px <= 3 * limits.p95_px
			and measured.p95_px <= limits.p95_px
			and measured.max_px <= limits.max_px
			and measured.get("samples", 0) >= 6
		)
		if not plausible:
			host.tell("This report exceeds its own calibration limits; it was not applied.")
			return
	host.mutate("Apply measured planar warp", func() -> void:
		output.warp = report.warp
		output.erase("mesh")
		output["capture_check"] = {
			"method": report.get("method"),
			"independent_dots": report.independent_dots,
			"spatial_holdout": report.spatial_holdout
		}
	)


func apply_optical(output: Dictionary, path: String) -> void:
	var report = Store.json_at(path)
	if not report is Dictionary or report.get("version") != 1:
		host.tell("Choose a version 1 pose or photometry report.")
		return
	if report.get("format") == "oes-survey-pose":
		var valid: bool = (
			report.get("size") == output.size
			and Model.vector(report.get("position"), 3)
			and Model.vector(report.get("aim"), 3)
			and Model.vector(report.get("up"), 3)
			and Model.vector(report.get("shift"), 2)
			and Model.numeric(report.get("throw"))
		)
		if not valid:
			host.tell("The surveyed pose must match this output's pixel size.")
			return
		host.mutate("Apply surveyed projector pose", func() -> void:
			for key in ["position", "aim", "up", "throw", "shift"]:
				output[key] = report[key]
			output.erase("capture_check")
		)
	elif (
		report.get("format") == "oes-photometry"
		and Model.numeric(report.get("gamma"))
		and Model.vector(report.get("gain"), 3)
		and Model.numeric(report.get("max_fractional_error"))
		and Model.numeric(report.get("limit"))
		and report.max_fractional_error >= 0
		and report.max_fractional_error <= report.limit
	):
		host.mutate("Apply measured luminance response", func() -> void:
			output.gamma = report.gamma
			output.gain = report.gain
			output.black = 0
		)
	else:
		host.tell("Not a valid pose or luminance report.")

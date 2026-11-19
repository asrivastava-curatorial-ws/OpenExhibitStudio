extends RefCounted
## Plain-language names for events, conditions and actions, plus catalogues that let the
## inspector and the Interactions workspace offer pickers instead of typed identifiers.

const Model := preload("res://core/project.gd")

## Action operation → label shown in pickers.
const ACTIONS := {
	"goto": "Go to scene",
	"set": "Set variable",
	"add": "Add to variable",
	"mul": "Multiply variable",
	"toggle": "Switch variable on/off",
	"random": "Random whole number into variable",
	"append": "Add value to list variable",
	"clear": "Empty list variable",
	"play": "Play timeline",
	"pause": "Pause timeline",
	"output": "Send to device output",
	"emit": "Trigger another event",
	"reset": "Reset the visit",
}
## What the action's target field refers to.
const TARGET_KIND := {
	"goto": "scene",
	"set": "variable",
	"add": "variable",
	"mul": "variable",
	"toggle": "variable",
	"random": "variable",
	"append": "variable",
	"clear": "variable",
	"play": "timeline",
	"pause": "none",
	"output": "output",
	"emit": "event",
	"reset": "none",
}
## Operations that use the value field.
const USES_VALUE := ["set", "add", "mul", "random", "append", "output", "emit"]
const TESTS := {
	"always": "always",
	"==": "is",
	"!=": "is not",
	">": "is more than",
	">=": "is at least",
	"<": "is less than",
	"<=": "is at most",
	"contains": "contains",
}


static func scene_name(project: Dictionary, id: String) -> String:
	var scene := Model.lookup(project.scenes, id)
	return str(scene.get("name", id)) if not scene.is_empty() else id


## Every event a visitor, device or the show can raise, as [event id, label] pairs.
static func events(project: Dictionary) -> Array:
	var result := []
	for scene in project.scenes:
		for o in scene.get("objects", []):
			var name := str(o.get("text", o.get("name", o.id))).left(32)
			match o.kind:
				"button":
					result.append(
						[str(o.get("event", "tap." + o.id)), "Button “%s” is pressed (%s)" % [name, scene.name]]
					)
				"slider":
					result.append(
						[
							"input." + str(o.get("channel", o.id)),
							"Slider “%s” moves (%s)" % [o.get("name", o.id), scene.name]
						]
					)
				"entry":
					result.append(["change." + o.id, "Text box “%s” changes (%s)" % [o.get("name", o.id), scene.name]])
					result.append(
						["submit." + o.id, "Text box “%s” is submitted (%s)" % [o.get("name", o.id), scene.name]]
					)
	for channel in input_channels(project):
		result.append(["input." + channel, "Sensor “%s” sends a value" % channel])
	for scene in project.scenes:
		result.append(["enter." + scene.id, "Scene “%s” opens" % scene.name])
	result.append(["session.start", "A new visit starts"])
	result.append(["book.next", "Next page is requested (arrow key or swipe)"])
	result.append(["book.prev", "Previous page is requested"])
	var seen := {}
	var unique := []
	for pair in result:
		if not seen.has(pair[0]):
			seen[pair[0]] = true
			unique.append(pair)
	return unique


static func input_channels(project: Dictionary) -> Array:
	var names := []
	for device in project.get("devices", []):
		for c in device.get("channels", []):
			if c is Dictionary and c.get("direction", "input") == "input" and not str(c.id) in names:
				names.append(str(c.id))
	return names


static func output_channels(project: Dictionary) -> Array:
	var names := []
	for device in project.get("devices", []):
		for c in device.get("channels", []):
			if c is Dictionary and c.get("direction", "input") == "output" and not str(c.id) in names:
				names.append(str(c.id))
	for rule in project.rules:
		for a in rule.get("actions", []):
			if a.get("op") == "output" and not str(a.get("target", "")) in names:
				names.append(str(a.target))
	return names


static func variables(project: Dictionary) -> Array:
	var names := []
	for key in project.variables:
		names.append(str(key))
	for scene in project.scenes:
		for o in scene.get("objects", []):
			if o.has("bind") and not str(o.bind) in names:
				names.append(str(o.bind))
	for rule in project.rules:
		for a in rule.get("actions", []):
			if TARGET_KIND.get(a.get("op", ""), "") == "variable" and not str(a.get("target", "")) in names:
				names.append(str(a.target))
	names.sort()
	return names


static func event(project: Dictionary, id: String) -> String:
	for pair in events(project):
		if pair[0] == id:
			return pair[1]
	return "Event “%s” happens" % id


static func value(v) -> String:
	if v is String and v == "$value":
		return "the incoming value"
	if v is String and v.begins_with("$"):
		return "variable %s" % v.substr(1)
	if v is float and is_equal_approx(v, roundf(v)):
		return str(int(v))
	return JSON.stringify(v) if v is String else str(v)


static func action(project: Dictionary, a: Dictionary) -> String:
	var op := str(a.get("op", ""))
	var target := str(a.get("target", ""))
	match op:
		"goto":
			return "go to scene “%s”" % scene_name(project, target)
		"set":
			return "set %s to %s" % [target, value(a.get("value", "$value"))]
		"add":
			return "add %s to %s" % [value(a.get("value", 1)), target]
		"mul":
			return "multiply %s by %s" % [target, value(a.get("value", 1))]
		"toggle":
			return "switch %s on/off" % target
		"random":
			return "put a random number up to %s into %s" % [value(a.get("value", 1)), target]
		"append":
			return "add %s to list %s" % [value(a.get("value", "$value")), target]
		"clear":
			return "empty list %s" % target
		"play":
			var t := Model.lookup(project.timelines, target)
			return "play timeline “%s”" % str(t.get("name", target))
		"pause":
			return "pause the timeline"
		"output":
			return "send %s to output “%s”" % [value(a.get("value", 1)), target]
		"emit":
			return "trigger “%s”" % target
		"reset":
			return "reset the visit"
	return op


static func condition(c: Dictionary) -> String:
	var test := str(c.get("op", "always"))
	if test == "always":
		return ""
	var left := value(c.get("left", "$value"))
	return "if %s %s %s" % [left, TESTS.get(test, test), value(c.get("right", 0))]


## One-sentence summary such as: When Button “Mars” is pressed → go to scene “Mars”.
static func rule(project: Dictionary, r: Dictionary) -> String:
	var parts := []
	for a in r.get("actions", []):
		parts.append(action(project, a))
	var guard := condition(r.get("if", {}))
	var head := (
		"When "
		+ event(project, str(r.get("event", ""))).left(1).to_lower()
		+ event(project, str(r.get("event", ""))).substr(1)
	)
	return head + (", " + guard if guard else "") + " → " + ("; ".join(parts) if parts else "nothing yet")

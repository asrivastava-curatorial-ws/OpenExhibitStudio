extends RefCounted

const Model = preload("res://core/project.gd")
signal updated
signal scene_changed(id)
signal traced(message)
signal output_requested(channel, value)
signal disarm_requested
signal clock_changed
var project: Dictionary
var vars = {}
var scene = ""
var trace: Array[String] = []
var history = {}
var virtual_outputs = {}
var virtual_armed = false
var queue: Array = []
var running = false
var timeline = ""
var head = 0.0
var playing = false
var idle = 0.0
var clock_generation = 0
var breaks = {}
var held = []
var paused_debug = false
var overlay = {}
var last_wall = 0
var play_stack = []
var timeline_origin = ""


func _init(p: Dictionary):
	project = p
	reset()


func log_line(message: String):
	if trace.size() >= 160:
		trace.pop_front()
	trace.append(message)
	traced.emit(message)


func disarm():
	virtual_armed = false
	virtual_outputs.clear()
	disarm_requested.emit()


func reset():
	disarm()
	queue.clear()
	held.clear()
	paused_debug = false
	vars = project.variables.duplicate(true)
	history.clear()
	scene = project.start
	playing = false
	timeline = ""
	head = 0
	idle = 0
	last_wall = Time.get_ticks_usec()
	clock_generation += 1
	overlay.clear()
	scene_changed.emit(scene)
	updated.emit()
	var start = str(project.settings.get("autoplay", ""))
	if start:
		play(start)
	dispatch("session.start")


func val(spec, input, depth = 0):
	if depth > 8:
		return 0
	if spec is Dictionary and project.settings.get("expressions", false):
		var args = spec.get("args", [])
		if not args is Array or args.size() > 2:
			return 0
		var a = val(args[0], input, depth + 1) if args.size() > 0 else 0
		var b = val(args[1], input, depth + 1) if args.size() > 1 else 0
		if spec.get("fn") == "length":
			return a.size() if a is Array else str(a).length()
		if spec.get("fn") == "at":
			return a[int(b)] if a is Array and Model.numeric(b) and int(b) >= 0 and int(b) < a.size() else 0
		if spec.get("fn") == "and":
			return bool(a) and bool(b)
		if spec.get("fn") == "or":
			return bool(a) or bool(b)
		if spec.get("fn") == "not":
			return not bool(a)
		if not Model.numeric(a) or not Model.numeric(b):
			return 0
		match spec.get("fn", ""):
			"add":
				return a + b
			"sub":
				return a - b
			"mul":
				return a * b
			"div":
				return float(a) / float(b) if b != 0 else 0
			"min":
				return minf(a, b)
			"max":
				return maxf(a, b)
			"sin":
				return sin(a)
			"cos":
				return cos(a)
			"sqrt":
				return sqrt(maxf(0, a))
			"abs":
				return absf(a)
			_:
				return 0
	if spec is String:
		if spec == "$value":
			return input
		if spec.begins_with("$"):
			return vars.get(spec.substr(1), 0)
	return spec


func condition(c: Dictionary, input) -> bool:
	var lhs = val(c.get("left", "$value"), input)
	var rhs = val(c.get("right", 0), input)
	match c.get("op", "always"):
		"always":
			return true
		"==":
			return lhs == rhs if typeof(lhs) == typeof(rhs) or (Model.numeric(lhs) and Model.numeric(rhs)) else false
		"!=":
			return not condition({"left": c.get("left", "$value"), "op": "==", "right": c.get("right", 0)}, input)
		">":
			return Model.numeric(lhs) and Model.numeric(rhs) and float(lhs) > float(rhs)
		">=":
			return Model.numeric(lhs) and Model.numeric(rhs) and float(lhs) >= float(rhs)
		"<":
			return Model.numeric(lhs) and Model.numeric(rhs) and float(lhs) < float(rhs)
		"<=":
			return Model.numeric(lhs) and Model.numeric(rhs) and float(lhs) <= float(rhs)
		"contains":
			return (lhs is Array and lhs.has(rhs)) or (lhs is String and str(rhs) in lhs)
	return false


func dispatch(event: String, value = null, visitor = false):
	if visitor:
		idle = 0
	if paused_debug or event.length() > 160:
		return
	if queue.size() >= 256:
		return
	queue.append([event, value])
	if running:
		return
	running = true
	var budget = 256
	var seen = {}
	while not queue.is_empty() and budget > 0 and not paused_debug:
		var msg = queue.pop_front()
		var signature = JSON.stringify(msg)
		if seen.has(signature):
			log_line("Repeated event blocked: " + str(msg[0]))
			continue
		seen[signature] = true
		log_line(str(msg[0]) + "  " + str(msg[1]).left(80))
		for rule in project.rules:
			if rule.get("enabled", true) and rule.event == msg[0] and condition(rule.get("if", {}), msg[1]):
				for action in rule.actions:
					budget -= 1
					if budget < 0:
						break
					held.append([action, msg[1]])
				if breaks.has(rule.id):
					paused_debug = true
		if not paused_debug:
			drain()
		budget -= 1
	if budget <= 0:
		queue.clear()
		log_line("Event budget reached.")
	running = false
	updated.emit()


func drain():
	while not held.is_empty():
		var x = held.pop_front()
		action(x[0], x[1])


func resume_debug():
	paused_debug = false
	running = true
	drain()
	running = false
	dispatch("debug.resume")


func action(a: Dictionary, input = null):
	var dest = str(a.get("target", ""))
	var v = val(a.get("value", "$value"), input)
	match a.get("op", ""):
		"set":
			vars[dest] = v.duplicate(true) if v is Array or v is Dictionary else v
		"add", "mul":
			if Model.numeric(vars.get(dest, 0)) and Model.numeric(v):
				vars[dest] = (
					float(vars.get(dest, 0)) + float(v) if a.op == "add" else float(vars.get(dest, 0)) * float(v)
				)
		"toggle":
			vars[dest] = not bool(vars.get(dest, false))
		"random":
			vars[dest] = randi_range(0, clampi(int(v) if Model.numeric(v) else 1, 0, 1000000))
		"append":
			if not vars.get(dest) is Array:
				vars[dest] = []
			if vars[dest].size() < 2048:
				vars[dest].append(v)
		"clear":
			vars[dest] = []
		"goto":
			if not Model.lookup(project.scenes, dest).is_empty() and scene != dest:
				scene = dest
				scene_changed.emit(scene)
				dispatch("enter." + scene)
		"emit":
			dispatch(dest, v)
		"output":
			if virtual_armed:
				virtual_outputs[dest] = v
			output_requested.emit(dest, v)
		"play":
			play(dest)
		"pause":
			playing = false
		"reset":
			reset()


func sensor(channel: String, v):
	if not history.has(channel):
		history[channel] = []
	var samples = history[channel]
	if samples.size() >= 160:
		samples.pop_front()
	samples.append(v)
	dispatch("input." + channel, v, true)


func play(track: String):
	var t = Model.lookup(project.timelines, track)
	if t.is_empty():
		return
	if track in play_stack or play_stack.size() >= 12:
		log_line("Cyclic timeline start blocked: " + track)
		return
	play_stack.append(track)
	timeline_origin = scene
	timeline = track
	head = 0
	clock_generation += 1
	playing = true
	keys_at(t, head)
	var gen = clock_generation
	for c in t.get("cues", []):
		if c.at == 0 and gen == clock_generation:
			action(c.action)
	play_stack.pop_back()
	updated.emit()


func seek(seconds: float):
	var t = Model.lookup(project.timelines, timeline)
	if t.is_empty():
		return
	disarm()
	clock_generation += 1
	head = clampf(seconds, 0, t.duration)
	var target = timeline_origin if timeline_origin else scene
	var best = -1.0
	for c in t.get("cues", []):
		if c.at <= head and c.at >= best and c.action.op == "goto":
			target = c.action.target
			best = c.at
	if target != scene:
		scene = target
		scene_changed.emit(scene)
	keys_at(t, head)
	updated.emit()
	clock_changed.emit()


func keys_at(t: Dictionary, pos: float):
	overlay.clear()
	var tracks = {}
	for k in t.get("keys", []):
		var key = k.scene + "/" + k.object + "/" + k.property
		if not tracks.has(key):
			tracks[key] = []
		tracks[key].append(k)
	for key in tracks:
		var points = tracks[key]
		points.sort_custom(func(a, b): return a.at < b.at)
		var l = points[0]
		var r = points[-1]
		for point in points:
			if point.at <= pos:
				l = point
			if point.at >= pos:
				r = point
				break
		var f = clampf((pos - l.at) / (r.at - l.at), 0, 1) if r.at > l.at else 0.0
		match l.get("curve", "linear"):
			"smooth":
				f = f * f * (3 - 2 * f)
			"step":
				f = 0
		overlay[key] = lerpf(l.value, r.value, f)


func tick(delta: float):
	idle += delta
	var timeout = float(project.settings.get("idle_seconds", 0))
	if timeout > 0 and idle >= timeout:
		reset()
		return
	if not playing or paused_debug:
		return
	var t = Model.lookup(project.timelines, timeline)
	if t.is_empty():
		return
	var before = head
	head = minf(head + maxf(delta, 0), t.duration)
	var generation = clock_generation
	var due = []
	for cue in t.get("cues", []):
		if before < cue.at and cue.at <= head:
			due.append(cue)
	due.sort_custom(func(a, b): return a.at < b.at)
	for c in due:
		if generation != clock_generation:
			return
		action(c.action)
	if generation != clock_generation:
		return
	keys_at(t, head)
	if head >= t.duration:
		playing = false
		if t.get("loop", false):
			disarm()
			play(timeline)
	if not due.is_empty():
		updated.emit()
	clock_changed.emit()


func wall_tick():
	var now = Time.get_ticks_usec()
	var dt = (now - last_wall) / 1000000.0
	last_wall = now
	tick(dt)


func expand(s: String) -> String:
	for key in vars:
		if "{" + str(key) + "}" in s:
			var v = vars[key]
			var txt = str(v)
			if Model.numeric(v) and is_equal_approx(float(v), roundf(float(v))):
				txt = str(int(v))
			s = s.replace("{" + str(key) + "}", txt)
	return s

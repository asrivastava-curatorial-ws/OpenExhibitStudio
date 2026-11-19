extends RefCounted
## Interactions workspace. Every rule reads as a sentence —
##   When <something happens> [, if <condition>] → <action>; <action>…
## and is edited with pickers (buttons, scenes, sensors, variables) instead of typed IDs.
## The node graph and raw JSON remain available for experienced users.

const StyleKit := preload("res://core/skin.gd")
const Model := preload("res://core/project.gd")
const RuleText := preload("res://studio/rule_text.gd")

var host
var graph_mode := false


func _init(owner) -> void:
	host = owner


func show(parent: Control) -> void:
	var box := _page(parent)
	_heading(
		box,
		"Interactions",
		"When something happens, do something. Buttons can also be wired directly in the Inspector."
	)
	var bar := HFlowContainer.new()
	box.add_child(bar)
	bar.add_child(StyleKit.button("+  New interaction", edit.bind({}), true))
	bar.add_child(StyleKit.button("Variables…", edit_variables))
	bar.add_child(StyleKit.button("List view" if graph_mode else "Graph view", _toggle_graph))
	if graph_mode:
		_graph(box)
	elif host.p.rules.is_empty():
		(
			box
			. add_child(
				_muted(
					"No interactions yet. Example: When button “Mars” is pressed → set planet to “Mars”; go to scene “Mars facts”."
				)
			)
		)
	else:
		for rule in host.p.rules:
			box.add_child(_rule_card(rule))
	box.add_child(HSeparator.new())
	_test_panel(box)
	monitor(box)


func _toggle_graph() -> void:
	graph_mode = not graph_mode
	host.refresh()


func _page(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	StyleKit.stretch(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.BG, Color.TRANSPARENT, 0, 16))
	scroll.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box


func _heading(box: Control, title: String, text: String) -> void:
	box.add_child(StyleKit.label(title, 22, Color.WHITE))
	box.add_child(_muted(text))


func _muted(text: String) -> Label:
	var label := StyleKit.label(text, 12, StyleKit.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _rule_card(rule: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.PANEL, StyleKit.LINE, 6, 10))
	var row := HBoxContainer.new()
	card.add_child(row)
	var enabled := CheckBox.new()
	enabled.button_pressed = rule.get("enabled", true)
	enabled.tooltip_text = "On / off"
	enabled.toggled.connect(
		func(on: bool) -> void: host.mutate("Switch interaction", func() -> void: rule.enabled = on)
	)
	row.add_child(enabled)
	var text := StyleKit.label(
		RuleText.rule(host.p, rule), 13, StyleKit.TEXT if rule.get("enabled", true) else StyleKit.MUTED
	)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	if str(rule.id).begins_with("press_"):
		row.add_child(StyleKit.label("from Inspector", 11, StyleKit.MUTED))
	row.add_child(StyleKit.button("Edit", edit.bind(rule)))
	var paused: bool = host.session.breaks.has(rule.id)
	var stop := StyleKit.button("● Break" if not paused else "○ Unbreak", _toggle_break.bind(rule.id))
	stop.tooltip_text = "Pause the visitor session when this rule fires, to inspect variables."
	row.add_child(stop)
	return card


func _toggle_break(id: String) -> void:
	if host.session.breaks.has(id):
		host.session.breaks.erase(id)
	else:
		host.session.breaks[id] = true
	host.refresh()


# ----------------------------------------------------------------------------- rule editor
## Opens the editor for `rule`, or for a new rule when it is empty.
func edit(rule: Dictionary) -> void:
	var events: Array = RuleText.events(host.p)
	var draft: Dictionary = (
		rule.duplicate(true)
		if not rule.is_empty()
		else {
			"id": Model.uid("rule"),
			"event": events[0][0] if events.size() else "session.start",
			"actions": [{"op": "set", "target": "score", "value": 1}],
		}
	)
	var box: VBoxContainer = host.dialog("Interaction", 700, 700)
	var preview := StyleKit.label("", 13, StyleKit.BLUE)
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var update := func() -> void: preview.text = RuleText.rule(host.p, draft)

	box.add_child(_step_title("WHEN"))
	var when := OptionButton.new()
	var custom := LineEdit.new()
	custom.placeholder_text = "event name, e.g. quiz.correct"
	var known := false
	for pair in events:
		when.add_item(pair[1])
		when.set_item_metadata(when.item_count - 1, pair[0])
		if pair[0] == draft.event:
			when.select(when.item_count - 1)
			known = true
	when.add_item("Another event (type its name)…")
	when.set_item_metadata(when.item_count - 1, "")
	if not known:
		when.select(when.item_count - 1)
		custom.text = draft.event
	custom.visible = not known
	when.item_selected.connect(func(i: int) -> void:
		var id: String = when.get_item_metadata(i)
		custom.visible = id == ""
		if id:
			draft.event = id
		update.call()
	)
	custom.text_changed.connect(func(text: String) -> void:
		draft.event = text.strip_edges()
		update.call()
	)
	box.add_child(when)
	box.add_child(custom)

	box.add_child(_step_title("IF  (optional)"))
	_condition_editor(box, draft, update)

	box.add_child(_step_title("DO"))
	var actions := VBoxContainer.new()
	box.add_child(actions)
	var rebuild := _rebuild_actions.bind(actions, draft, update)
	rebuild.call()
	box.add_child(StyleKit.button("+  Add another action", func() -> void:
		draft.actions.append({"op": "goto", "target": host.p.scenes[0].id})
		rebuild.call()
	))

	box.add_child(HSeparator.new())
	box.add_child(preview)
	var footer := HBoxContainer.new()
	box.add_child(footer)
	footer.add_child(StyleKit.button("Save interaction", func() -> void:
		if str(draft.event).strip_edges().is_empty():
			host.tell("Choose what starts this interaction.")
			return
		box.get_window().queue_free()
		host.mutate("Save interaction", func() -> void:
			var index: int = host.p.rules.find(rule) if not rule.is_empty() else -1
			if index >= 0:
				host.p.rules[index] = draft
			else:
				host.p.rules.append(draft)
		)
	, true))
	if not rule.is_empty():
		footer.add_child(StyleKit.button("Delete", func() -> void:
			box.get_window().queue_free()
			host.mutate("Delete interaction", func() -> void: host.p.rules.erase(rule))
		))
		footer.add_child(StyleKit.button("Edit as JSON…", func() -> void:
			box.get_window().queue_free()
			host.work.json_editor(
				"Interaction (JSON)", rule, func(value) -> void: host.p.rules[host.p.rules.find(rule)] = value
			)
		))


func _rebuild_actions(actions: VBoxContainer, draft: Dictionary, update: Callable) -> void:
	StyleKit.clear(actions)
	for i in draft.actions.size():
		actions.add_child(_action_row(draft, i, update, _rebuild_actions.bind(actions, draft, update)))
	update.call()


func _step_title(text: String) -> Label:
	var label := StyleKit.label(text, 12, StyleKit.BLUE)
	label.custom_minimum_size.y = 24
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label


func _condition_editor(box: Control, draft: Dictionary, update: Callable) -> void:
	var cond: Dictionary = draft.get("if", {})
	var row := HFlowContainer.new()
	box.add_child(row)
	var subject := OptionButton.new()
	subject.add_item("Always")
	subject.set_item_metadata(0, "")
	subject.add_item("the incoming value")
	subject.set_item_metadata(1, "$value")
	for name in RuleText.variables(host.p):
		subject.add_item("variable " + name)
		subject.set_item_metadata(subject.item_count - 1, "$" + name)
	var left := str(cond.get("left", "$value")) if cond.get("op", "always") != "always" else ""
	for i in subject.item_count:
		if subject.get_item_metadata(i) == left:
			subject.select(i)
	var test := OptionButton.new()
	var tests := RuleText.TESTS.keys().filter(func(t: String) -> bool: return t != "always")
	for t in tests:
		test.add_item(RuleText.TESTS[t])
		test.set_item_metadata(test.item_count - 1, t)
		if t == cond.get("op"):
			test.select(test.item_count - 1)
	var right := LineEdit.new()
	right.custom_minimum_size.x = 140
	right.placeholder_text = "value"
	right.text = RuleText.value(cond.get("right", 0)) if cond.has("right") else ""
	row.add_child(subject)
	row.add_child(test)
	row.add_child(right)
	var apply := func(_ignored = null) -> void:
		var chosen: String = subject.get_item_metadata(subject.selected)
		test.visible = chosen != ""
		right.visible = chosen != ""
		if chosen == "":
			draft.erase("if")
		else:
			draft["if"] = {
				"left": chosen, "op": test.get_item_metadata(test.selected), "right": host._parse_value(right.text)
			}
		update.call()
	subject.item_selected.connect(apply)
	test.item_selected.connect(apply)
	right.text_changed.connect(apply)
	apply.call()


func _action_row(draft: Dictionary, index: int, update: Callable, rebuild: Callable) -> Control:
	var action: Dictionary = draft.actions[index]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", StyleKit.box(StyleKit.PANEL, StyleKit.LINE, 6, 8))
	var column := VBoxContainer.new()
	card.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var op := OptionButton.new()
	op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in RuleText.ACTIONS:
		op.add_item(RuleText.ACTIONS[key])
		op.set_item_metadata(op.item_count - 1, key)
		if key == action.get("op"):
			op.select(op.item_count - 1)
	op.item_selected.connect(func(i: int) -> void:
		var key: String = op.get_item_metadata(i)
		draft.actions[index] = _default_action(key)
		rebuild.call()
	)
	top.add_child(op)
	top.add_child(StyleKit.button("↑", _move_action.bind(draft, index, -1, rebuild)))
	top.add_child(StyleKit.button("✕", func() -> void:
		draft.actions.remove_at(index)
		rebuild.call()
	))
	var detail := HFlowContainer.new()
	column.add_child(detail)
	var kind: String = RuleText.TARGET_KIND.get(action.get("op", ""), "none")
	match kind:
		"scene":
			detail.add_child(_picker(_scene_options(), str(action.get("target", "")), func(v: String) -> void:
				action.target = v
				update.call()
			))
		"timeline":
			var tracks: Array = host.p.timelines.map(
				func(t: Dictionary) -> Array: return [t.id, str(t.get("name", t.id))]
			)
			if tracks.is_empty():
				detail.add_child(_muted("Create a timeline first (Timeline workspace)."))
			else:
				detail.add_child(_picker(tracks, str(action.get("target", "")), func(v: String) -> void:
					action.target = v
					update.call()
				))
		"variable", "output", "event":
			var suggestions: Array = (
				RuleText.variables(host.p)
				if kind == "variable"
				else (
					RuleText.output_channels(host.p)
					if kind == "output"
					else RuleText.events(host.p).map(func(e: Array) -> String: return e[0])
				)
			)
			detail.add_child(_combo(str(action.get("target", "")), suggestions, kind, func(v: String) -> void:
				action.target = v
				update.call()
			))
	if action.get("op") in RuleText.USES_VALUE:
		detail.add_child(
			StyleKit.label(
				{
					"set": "to",
					"add": "amount",
					"mul": "by",
					"random": "up to",
					"append": "value",
					"output": "value",
					"emit": "value"
				}[action.op],
				12,
				StyleKit.MUTED
			)
		)
		var values := ["$value"] + RuleText.variables(host.p).map(func(n: String) -> String: return "$" + n)
		var shown := (
			str(action.get("value", "")) if action.get("value") is String else RuleText.value(action.get("value", 1))
		)
		detail.add_child(_combo(shown, values, "value", func(v: String) -> void:
			action.value = v if v.begins_with("$") else host._parse_value(v)
			update.call()
		))
	return card


func _default_action(op: String) -> Dictionary:
	match RuleText.TARGET_KIND.get(op, "none"):
		"scene":
			return {"op": op, "target": host.p.scenes[0].id}
		"timeline":
			return {"op": op, "target": host.p.timelines[0].id if host.p.timelines.size() else ""}
		"output":
			return {"op": op, "target": "lamp", "value": 1}
		"event":
			return {"op": op, "target": "custom.event"}
		"none":
			return {"op": op, "target": ""}
	var action := {"op": op, "target": "score"}
	if op in RuleText.USES_VALUE:
		action.value = 1
	return action


func _move_action(draft: Dictionary, index: int, step: int, rebuild: Callable) -> void:
	var target := index + step
	if target < 0 or target >= draft.actions.size():
		return
	var moved = draft.actions.pop_at(index)
	draft.actions.insert(target, moved)
	rebuild.call()


func _scene_options() -> Array:
	return host.p.scenes.map(func(s: Dictionary) -> Array: return [s.id, str(s.name)])


func _picker(options: Array, current: String, on_change: Callable) -> OptionButton:
	var menu := OptionButton.new()
	for pair in options:
		menu.add_item(pair[1])
		menu.set_item_metadata(menu.item_count - 1, pair[0])
		if pair[0] == current:
			menu.select(menu.item_count - 1)
	if menu.selected < 0 and menu.item_count:
		menu.select(0)
		on_change.call(str(menu.get_item_metadata(0)))
	menu.item_selected.connect(func(i: int) -> void: on_change.call(str(menu.get_item_metadata(i))))
	return menu


## A text field with a ▾ menu of suggestions (variables, channels, events).
func _combo(current: String, suggestions: Array, kind: String, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	var line := LineEdit.new()
	line.text = current
	line.custom_minimum_size.x = 180
	line.placeholder_text = {
		"variable": "variable name",
		"output": "output channel",
		"event": "event name",
		"value": "number, text or $variable"
	}[kind]
	line.text_changed.connect(func(text: String) -> void: on_change.call(text.strip_edges()))
	row.add_child(line)
	if suggestions.size():
		var menu := MenuButton.new()
		menu.text = "▾"
		menu.tooltip_text = "Choose a known " + kind
		for item in suggestions:
			menu.get_popup().add_item(str(item) if str(item) != "$value" else "$value (the incoming value)")
		menu.get_popup().index_pressed.connect(func(i: int) -> void:
			line.text = str(suggestions[i])
			on_change.call(line.text)
		)
		row.add_child(menu)
	return row


# ----------------------------------------------------------------------------- variables
func edit_variables() -> void:
	var box: VBoxContainer = host.dialog("Variables — starting values for each visit", 560, 560)
	(
		box
		. add_child(
			_muted(
				"Numbers, true/false and text are allowed. Use [] for an empty list. Every visit (and Reset visit) starts from these values."
			)
		)
	)
	var rows := VBoxContainer.new()
	box.add_child(rows)
	var add_row := func(name: String, value) -> void:
		var row := HBoxContainer.new()
		var key := LineEdit.new()
		key.text = name
		key.placeholder_text = "name"
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var initial := LineEdit.new()
		initial.text = (
			JSON.stringify(value)
			if value is Array or value is Dictionary
			else RuleText.value(value).trim_prefix('"').trim_suffix('"')
		)
		initial.placeholder_text = "starting value"
		initial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		row.add_child(initial)
		row.add_child(StyleKit.button("✕", row.queue_free))
		rows.add_child(row)
	for name in host.p.variables:
		add_row.call(str(name), host.p.variables[name])
	box.add_child(StyleKit.button("+  Add variable", add_row.bind("", 0)))
	box.add_child(StyleKit.button("Save variables", func() -> void:
		var result := {}
		for row in rows.get_children():
			if row.is_queued_for_deletion():
				continue
			var name: String = (row.get_child(0) as LineEdit).text.strip_edges()
			if name.is_empty():
				continue
			if not Model.identifier(name):
				host.tell("Variable names use letters, digits, - and _ only: " + name)
				return
			var text: String = (row.get_child(1) as LineEdit).text.strip_edges()
			result[name] = [] if text == "[]" else host._parse_value(text)
		box.get_window().queue_free()
		host.mutate("Edit variables", func() -> void: host.p.variables = result)
	, true))


# ----------------------------------------------------------------------------- test + monitor
func _test_panel(box: Control) -> void:
	box.add_child(StyleKit.label("Try an event", 14, StyleKit.BLUE))
	var row := HFlowContainer.new()
	box.add_child(row)
	var events := OptionButton.new()
	for pair in RuleText.events(host.p):
		events.add_item(pair[1])
		events.set_item_metadata(events.item_count - 1, pair[0])
	row.add_child(events)
	var value := LineEdit.new()
	value.text = "1"
	value.custom_minimum_size.x = 90
	value.tooltip_text = "Value carried by the event"
	row.add_child(value)
	row.add_child(StyleKit.button("Send", func() -> void:
		if events.selected >= 0:
			host.session.dispatch(
				str(events.get_item_metadata(events.selected)), host._parse_value(value.text), true
			)
	, true))
	row.add_child(StyleKit.button("Resume after breakpoint", host.session.resume_debug))


func monitor(box: Control) -> void:
	box.add_child(StyleKit.label("Variables now", 14, StyleKit.BLUE))
	var vars := StyleKit.label(_vars_text(), 12, StyleKit.TEXT)
	vars.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(vars)
	box.add_child(StyleKit.label("Event trace", 14, StyleKit.BLUE))
	var trace := RichTextLabel.new()
	trace.custom_minimum_size.y = 130
	trace.scroll_following = true
	trace.text = "\n".join(host.session.trace.slice(-16))
	box.add_child(trace)
	host.work.watch(host.session.updated, vars, func() -> void:
		if is_instance_valid(vars):
			vars.text = _vars_text()
	)
	host.work.watch(host.session.traced, trace, func(line: String) -> void:
		if is_instance_valid(trace):
			trace.text = (trace.text + "\n" + line).right(4000)
	)


func _vars_text() -> String:
	var parts := []
	for key in host.session.vars:
		parts.append("%s = %s" % [key, RuleText.value(host.session.vars[key])])
	return "   ·   ".join(parts) if parts else "(none)"


# ----------------------------------------------------------------------------- graph view
func _graph(box: Control) -> void:
	var graph := GraphEdit.new()
	graph.custom_minimum_size.y = 380
	graph.right_disconnects = true
	box.add_child(graph)
	var data := {}
	for j in host.p.rules.size():
		var rule: Dictionary = host.p.rules[j]
		var trigger := GraphNode.new()
		trigger.name = "rule_%d" % j
		trigger.title = RuleText.event(host.p, rule.event).left(40)
		trigger.position_offset = Vector2(24, 28 + j * 120)
		trigger.add_child(StyleKit.label(RuleText.condition(rule.get("if", {})) if rule.has("if") else "always", 12))
		trigger.set_slot(0, false, 0, StyleKit.BLUE, true, 0, StyleKit.BLUE)
		graph.add_child(trigger)
		data[str(trigger.name)] = rule
		for i in rule.actions.size():
			var action: Dictionary = rule.actions[i]
			var node := GraphNode.new()
			node.name = "a_%d_%d" % [j, i]
			node.title = RuleText.ACTIONS.get(action.op, action.op)
			node.position_offset = Vector2(360 + i * 220, 28 + j * 120)
			node.add_child(StyleKit.label(str(action.get("target", "")), 12))
			node.set_slot(0, true, 0, StyleKit.BLUE, false, 0, StyleKit.BLUE)
			graph.add_child(node)
			data[str(node.name)] = action
			graph.connect_node(trigger.name, 0, node.name, 0)
	graph.connection_request.connect(func(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
		var rule: Dictionary = data.get(str(from), {})
		var action: Dictionary = data.get(str(to), {})
		if rule.has("actions") and action.has("op") and not action in rule.actions:
			host.mutate("Connect action", func() -> void: rule.actions.append(action.duplicate(true)))
	)
	graph.disconnection_request.connect(func(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
		var rule: Dictionary = data.get(str(from), {})
		if rule.has("actions"):
			host.mutate("Disconnect action", func() -> void: rule.actions.erase(data.get(str(to), {})))
	)
	(
		box
		. add_child(
			_muted(
				"Drag from an event's output to an action to copy that action into the event's rule. Right-drag a connection to remove it."
			)
		)
	)

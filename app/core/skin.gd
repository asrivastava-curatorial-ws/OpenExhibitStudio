extends RefCounted

const MONO = preload("res://assets/JetBrainsMono-Regular.woff2")
const BN = preload("res://assets/NotoSansBengali-Regular.ttf")
const HI = preload("res://assets/NotoSansDevanagari-Regular.ttf")
const BG = Color("#0d1117")
const PANEL = Color("#161b22")
const LINE = Color("#30363d")
const TEXT = Color("#d9e2f0")
const MUTED = Color("#92a2b5")
const MINT = Color("#71e4ca")
const BLUE = Color("#79b8ff")


static func box(fill: Color, border = Color.TRANSPARENT, radius = 5, pad = 6) -> StyleBoxFlat:
	var b = StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(1 if border.a > 0 else 0)
	b.set_corner_radius_all(radius)
	b.content_margin_left = pad + 3
	b.content_margin_right = pad + 3
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	return b


static func font() -> Font:
	var f = FontVariation.new()
	f.base_font = MONO
	f.fallbacks = [BN, HI]
	return f


static func theme() -> Theme:
	var t = Theme.new()
	t.default_font = font()
	t.default_font_size = 13
	for node in [
		"Label",
		"Button",
		"LineEdit",
		"TextEdit",
		"Tree",
		"OptionButton",
		"PopupMenu",
		"CheckButton",
		"TabContainer",
		"ItemList"
	]:
		t.set_color("font_color", node, TEXT)
		t.set_color("font_hover_color", node, Color.WHITE)
		t.set_color("font_focus_color", node, Color.WHITE)
	for node in ["Button", "OptionButton", "MenuButton", "TabBar"]:
		t.set_stylebox("normal", node, box(Color("#1d252f"), LINE, 5, 6))
		t.set_stylebox("hover", node, box(Color("#253447"), BLUE, 5, 6))
		t.set_stylebox("pressed", node, box(Color("#17374a"), BLUE, 5, 6))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 6, 8))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, LINE, 5, 4))
	for node in ["LineEdit", "TextEdit", "Tree", "ItemList"]:
		t.set_stylebox("normal", node, box(Color("#0d131c"), LINE, 4, 5))
		t.set_stylebox("focus", node, box(Color("#101a27"), BLUE, 4, 5))
	t.set_constant("separation", "HBoxContainer", 7)
	t.set_constant("separation", "VBoxContainer", 7)
	return t


static func label(s: String, fs = 13, color = TEXT) -> Label:
	var a = Label.new()
	a.text = s
	a.add_theme_font_size_override("font_size", fs)
	a.add_theme_color_override("font_color", color)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return a


static func button(s: String, cb: Callable, accent = false) -> Button:
	var b = Button.new()
	b.text = s
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	if accent:
		b.add_theme_stylebox_override("normal", box(Color("#183d36"), Color("#357263"), 5, 6))
		b.add_theme_color_override("font_color", MINT)
	return b


static func clear(parent: Node):
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


static func fill(c: Control):
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func stretch(c: Control):
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL


static func texture(file: String) -> Texture2D:
	var img = Image.new()
	if img.load(file) != OK:
		return null
	return ImageTexture.create_from_image(img)

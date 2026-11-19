extends Control
const Model=preload("res://core/project.gd")
const StyleKit=preload("res://core/skin.gd")
const Graphic=preload("res://core/graphic.gd")
const ModelView=preload("res://core/model_view.gd")
var session
var folder=""
var scene_id=""
var nodes={}
var assets={}
var design=false
var muted=false
var bg=Color("#101d30")
var stroke=""
var previous_scene=""
var transition:Tween

func configure(s,dir: String,id: String,editing=false,quiet=false):
	session=s
	folder=dir
	scene_id=id
	design=editing
	muted=quiet
	clip_contents=true
	theme=StyleKit.theme()
	size=Vector2(s.project.canvas[0],s.project.canvas[1])
	rebuild()
	session.updated.connect(refresh)
	session.clock_changed.connect(animate)
	if scene_id=="@live": session.scene_changed.connect(func(_id): rebuild())

func current() -> Dictionary:
	return Model.lookup(session.project.scenes,session.scene if scene_id=="@live" else scene_id)

func rebuild():
	if not session: return
	var sc=current()
	if sc.is_empty(): return
	var changing=previous_scene!="" and previous_scene!=sc.id and not design
	previous_scene=sc.id
	StyleKit.clear(self)
	nodes.clear()
	bg=Color.from_string(sc.get("background","#101d30"),StyleKit.BG)
	for o in sc.objects:
		var node=component(o)
		if not node: continue
		node.name=o.id
		add_child(node)
		nodes[o.id]=node
		node.position=Vector2(o.rect[0],o.rect[1])
		node.size=Vector2(o.rect[2],o.rect[3])
		node.pivot_offset=node.size/2
		node.clip_contents=true
	refresh()
	queue_redraw()
	if changing and sc.get("transition","cut") in ["fade","slide"]:
		if transition: transition.kill()
		transition=create_tween().set_parallel(true)
		for n in nodes.values():
			if sc.transition=="fade":
				n.modulate.a=0
				transition.tween_property(n,"modulate:a",1,0.35)
			else:
				var p=n.position
				n.position.x+=size.x*0.12
				transition.tween_property(n,"position",p,0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _draw(): draw_rect(Rect2(Vector2.ZERO,size),bg)

func component(o: Dictionary) -> Control:
	var path=""
	if o.has("asset") and session.project.assets.has(o.asset): path=folder.path_join(session.project.assets[o.asset].path)
	var color=Color.from_string(o.get("color","#dae7f3"),StyleKit.TEXT)
	match o.kind:
		"text":
			var n=StyleKit.label("",int(o.get("font",30)),color)
			n.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			n.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			n.horizontal_alignment=int(o.get("align",0))
			return n
		"panel":
			var n=Panel.new()
			n.add_theme_stylebox_override("panel",StyleKit.box(color,Color.from_string(o.get("border","#00000000"),Color.TRANSPARENT),int(o.get("radius",12)),0))
			n.mouse_filter=Control.MOUSE_FILTER_IGNORE
			return n
		"button":
			var n=StyleKit.button("",func():session.dispatch(o.get("event","tap."+o.id),o.get("value",1),true))
			n.add_theme_font_size_override("font_size",int(o.get("font",22)))
			var fill=Color.from_string(o.get("fill","#1a3841"),StyleKit.PANEL)
			n.add_theme_stylebox_override("normal",StyleKit.box(fill,Color.from_string(o.get("border","#34616a"),StyleKit.LINE),int(o.get("radius",9)),5))
			n.add_theme_color_override("font_color",color)
			n.disabled=design
			if design:
				n.add_theme_stylebox_override("disabled",n.get_theme_stylebox("normal"))
				n.add_theme_color_override("font_disabled_color",color)
			return n
		"image":
			var n=TextureRect.new()
			if not assets.has(path) and path: assets[path]=StyleKit.texture(path)
			n.texture=assets.get(path)
			n.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			n.stretch_mode=TextureRect.STRETCH_SCALE if o.get("stretch",false) else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			n.mouse_filter=Control.MOUSE_FILTER_IGNORE
			return n
		"entry":
			var n=LineEdit.new()
			n.placeholder_text=o.get("text","Type here")
			n.max_length=200
			n.editable=not design and not o.get("readonly",false)
			n.add_theme_font_size_override("font_size",int(o.get("font",24)))
			n.text_changed.connect(func(v): session.dispatch(o.get("event","change."+o.id),v,true))
			n.text_submitted.connect(func(v):session.dispatch("submit."+o.id,v,true))
			return n
		"slider":
			var n=HSlider.new()
			n.min_value=o.get("min",0)
			n.max_value=o.get("max",100)
			n.step=o.get("step",1)
			n.editable=not design
			n.value_changed.connect(func(v):session.sensor(o.get("channel",o.id),v))
			return n
		"contest":
			var board=preload("res://core/contest_board.gd").new()
			board.design=design
			return board
		"model":
			var n=ModelView.new()
			n.setup()
			if path:
				var err=n.load_model(path)
				if err: session.log_line(err)
			return n
		"video":
			var n=VideoStreamPlayer.new()
			n.expand=true
			n.volume_db=-80 if muted or design else float(o.get("volume_db",0))
			n.loop=o.get("loop",true)
			if path and path.get_extension().to_lower()=="ogv":
				var v=VideoStreamTheora.new()
				v.file=path
				n.stream=v
				if not design: n.call_deferred("play")
			if design: n.add_child(StyleKit.label("▶  "+path.get_file(),20,StyleKit.BLUE))
			return n
		"audio":
			var n=Control.new()
			var player=AudioStreamPlayer.new()
			n.add_child(player)
			if not design and not muted and path:
				match path.get_extension().to_lower():
					"mp3": player.stream=AudioStreamMP3.load_from_file(path)
					"ogg": player.stream=AudioStreamOggVorbis.load_from_file(path)
					"wav": player.stream=AudioStreamWAV.load_from_file(path)
				if player.stream:
					player.volume_db=float(o.get("volume_db",0))
					if o.get("loop",false): player.finished.connect(player.play)
					player.call_deferred("play")
			if design: n.add_child(StyleKit.label("♪  "+path.get_file(),18,StyleKit.BLUE))
			return n
		_:
			var n=Graphic.new()
			n.data=o
			n.session=session
			n.mouse_filter=Control.MOUSE_FILTER_IGNORE
			if o.kind=="drawing" and not design and not o.get("readonly",false):
				n.mouse_filter=Control.MOUSE_FILTER_STOP
				n.gui_input.connect(func(ev):ink(ev,n,o))
			return n

func ink(ev: InputEvent, n: Control,o: Dictionary):
	var binding=str(o.get("bind","ink"))
	if not session.vars.get(binding) is Array: session.vars[binding]=[]
	var points=session.vars[binding]
	if ev is InputEventMouseButton and ev.button_index==MOUSE_BUTTON_LEFT:
		stroke=o.id if ev.pressed else ""
		if ev.pressed and points.size()<2048: points.append(null)
	if (ev is InputEventMouseMotion or ev is InputEventMouseButton) and stroke==o.id and points.size()<2048:
		var q=ev.position/n.size
		points.append([clampf(q.x,0,1),clampf(q.y,0,1)])
		session.idle=0
		session.updated.emit()

func refresh():
	var sc=current()
	for o in sc.get("objects",[]):
		if not nodes.has(o.id): continue
		var n=nodes[o.id]
		match o.kind:
			"text","button": n.text=session.expand(o.get("text",o.id))
			"slider": n.set_value_no_signal(float(session.vars.get(o.get("bind",o.id),n.min_value)))
			"entry":
				var txt=str(session.vars.get(o.get("bind",o.id),""))
				if n.text!=txt: n.text=txt
			_: n.queue_redraw()
		n.visible=not o.get("hidden",false)
	animate()

func animate():
	var sc=current()
	for o in sc.get("objects",[]):
		if not nodes.has(o.id): continue
		var k=sc.id+"/"+o.id+"/"
		var n=nodes[o.id]
		if session.overlay.has(k+"x"): n.position.x=session.overlay[k+"x"]
		if session.overlay.has(k+"y"): n.position.y=session.overlay[k+"y"]
		if session.overlay.has(k+"rotation"): n.rotation_degrees=session.overlay[k+"rotation"]
		if session.overlay.has(k+"opacity"): n.modulate.a=clampf(session.overlay[k+"opacity"],0,1)

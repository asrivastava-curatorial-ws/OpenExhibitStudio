extends Control
const Model=preload("res://core/project.gd")
const Storage=preload("res://core/storage.gd")
const Session=preload("res://core/session.gd")
const Paths=preload("res://core/paths.gd")
const StyleKit=preload("res://core/skin.gd")
const Canvas=preload("res://studio/canvas.gd")
const Workspaces=preload("res://studio/workspaces.gd")
const Gateway=preload("res://core/gateway_client.gd")
const SPACES=["Canvas","Installation","3D scene","Mapping","Timeline","Logic","Hardware","Flipbook","Science","Assets","Test","Deployment","Live quiz"]
const SYMBOLS=["▦","⌂","◇","▱","▷","⑂","⊞","▤","∿","▧","◎","⇧","?"]
var p:Dictionary
var io=Storage.new()
var session
var gateway
var work
var edit_scene=""
var selected=""
var space="Canvas"
var dirty=false
var undo_stack=[]
var redo_stack=[]
var status:Label
var title_label:Label
var mode_label:Label
var header:Label
var layers:ItemList
var pages:OptionButton
var center:VBoxContainer
var inspector:VBoxContainer
var expanded:Window
var right_scroll:ScrollContainer
var split:HSplitContainer
var canvas
var snap_on=true
var msg=""
var next_save=0
var journal=""
var command_list=[]
var nav_buttons={}
var booted=false
var touch_start=Vector2.ZERO

func _ready():
	theme=StyleKit.theme()
	get_window().min_size=Vector2i(930,610)
	get_window().title="OpenExhibit Studio"
	gateway=Gateway.new()
	add_child(gateway)
	work=Workspaces.new(self)
	get_viewport().files_dropped.connect(dropped)
	var src=Paths.first_project()
	var loaded=io.open(src) if src and FileAccess.file_exists(src) else {}
	var initial_error=io.error
	if loaded.is_empty():
		p=Model.fresh()
		io.folder=Storage.absolute("user://working/"+Model.uid("draft"))
		DirAccess.make_dir_recursive_absolute(io.folder)
	else: p=loaded
	edit_scene=p.start
	journal=Storage.absolute("user://recovery/last.json")
	var recovery=Storage.json_at(journal)
	build_shell()
	reset_session()
	refresh()
	booted=true
	if initial_error: tell(initial_error)
	if recovery is Dictionary and recovery.has("project") and Model.validate(recovery.project)=="":
		var w=ConfirmationDialog.new()
		add_child(w)
		w.title="Restore unsaved exhibit?"
		w.dialog_text="Recovered edits to “"+str(recovery.project.title)+"”. Restore them in Studio?"
		w.ok_button_text="Restore"
		w.cancel_button_text="Keep current project"
		w.confirmed.connect(func():
			p=recovery.project
			io.folder=recovery.get("folder","")
			io.path=recovery.get("path","")
			io.revision=recovery.get("revision","")
			io.packaged=recovery.get("packaged",false)
			edit_scene=p.start
			selected=""
			dirty=true
			reset_session()
			refresh()
			tell("Recovered unsaved edits.")
		)
		w.canceled.connect(func(): DirAccess.remove_absolute(journal))
		w.popup_centered()

func reset_session():
	session=Session.new(p)
	gateway.attach(session)

func build_shell():
	var background=ColorRect.new()
	background.color=StyleKit.BG
	add_child(background)
	StyleKit.fill(background)
	var root=VBoxContainer.new()
	add_child(root)
	StyleKit.fill(root)
	root.add_theme_constant_override("separation",0)
	var top=PanelContainer.new()
	top.add_theme_stylebox_override("panel",StyleKit.box(Color("#111820"),StyleKit.LINE,0,9))
	root.add_child(top)
	var bar=HBoxContainer.new()
	top.add_child(bar)
	var logo=TextureRect.new()
	logo.texture=preload("res://assets/icon.svg")
	logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	logo.custom_minimum_size=Vector2(27,27)
	bar.add_child(logo)
	bar.add_child(StyleKit.label("OpenExhibit",17,Color.WHITE))
	bar.add_child(StyleKit.label("STUDIO",12,StyleKit.MINT))
	bar.add_child(VSeparator.new())
	menu(bar,"File",{"New project":new_project,"Open project…":open_project,"Examples…":examples_dialog,"Save":save,"Save as…":save_as,"Export package…":pack_project})
	menu(bar,"Edit",{"Undo":undo,"Redo":redo,"Duplicate object":duplicate_object,"Delete object":delete_object,"Command palette…":commands})
	menu(bar,"View",{"Detach inspector":float_inspector,"Run exhibit":toggle_test,"Global settings…":settings_dialog,"Live quiz contest":set_space.bind("Live quiz"),"User guide":guide})
	title_label=StyleKit.label("",12,StyleKit.MUTED)
	title_label.size_flags_horizontal=SIZE_EXPAND_FILL
	title_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(title_label)
	bar.add_child(StyleKit.button("⌕  Commands",commands))
	bar.add_child(StyleKit.button("▶  Test exhibit",toggle_test,true))
	var body=HBoxContainer.new()
	StyleKit.stretch(body)
	body.add_theme_constant_override("separation",0)
	root.add_child(body)
	var rail=PanelContainer.new()
	rail.add_theme_stylebox_override("panel",StyleKit.box(Color("#10151c"),StyleKit.LINE,0,3))
	body.add_child(rail)
	var scrollrail=ScrollContainer.new()
	scrollrail.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	rail.add_child(scrollrail)
	var modes=VBoxContainer.new()
	modes.add_theme_constant_override("separation",3)
	scrollrail.add_child(modes)
	for i in SPACES.size():
		var name_=SPACES[i]
		var b=StyleKit.button(SYMBOLS[i],set_space.bind(name_))
		b.add_theme_font_size_override("font_size",21)
		b.tooltip_text=name_
		b.custom_minimum_size=Vector2(40,35)
		b.add_theme_stylebox_override("normal",StyleKit.box(Color.TRANSPARENT,Color.TRANSPARENT,4,2))
		modes.add_child(b)
		nav_buttons[name_]=b
	var left_split=HSplitContainer.new()
	StyleKit.stretch(left_split)
	body.add_child(left_split)
	var left=PanelContainer.new()
	left.custom_minimum_size.x=180
	left.add_theme_stylebox_override("panel",StyleKit.box(StyleKit.PANEL,Color.TRANSPARENT,0,10))
	left_split.add_child(left)
	var explorer=VBoxContainer.new()
	left.add_child(explorer)
	explorer.add_child(StyleKit.label("EXPLORER",12,StyleKit.MUTED))
	explorer.add_child(HSeparator.new())
	explorer.add_child(StyleKit.label("Scenes",14))
	pages=OptionButton.new()
	pages.item_selected.connect(func(i):
		edit_scene=p.scenes[i].id
		selected=""
		set_space("Canvas")
	)
	explorer.add_child(pages)
	explorer.add_child(StyleKit.button("+  New scene",add_scene))
	explorer.add_child(HSeparator.new())
	var layer_head=HBoxContainer.new()
	explorer.add_child(layer_head)
	layer_head.add_child(StyleKit.label("Layers",14))
	var spacer=Control.new()
	spacer.size_flags_horizontal=SIZE_EXPAND_FILL
	layer_head.add_child(spacer)
	layer_head.add_child(StyleKit.button("+",add_menu))
	layers=ItemList.new()
	StyleKit.stretch(layers)
	layers.allow_reselect=true
	layers.item_selected.connect(func(i):pick(str(layers.get_item_metadata(i))))
	explorer.add_child(layers)
	var layer_ops=HBoxContainer.new()
	explorer.add_child(layer_ops)
	layer_ops.add_child(StyleKit.button("↑",move_layer.bind(1)))
	layer_ops.add_child(StyleKit.button("↓",move_layer.bind(-1)))
	layer_ops.add_child(StyleKit.button("Copy",duplicate_object))
	explorer.add_child(StyleKit.button("Browse examples…",examples_dialog))
	split=HSplitContainer.new()
	StyleKit.stretch(split)
	left_split.add_child(split)
	var mid=VBoxContainer.new()
	StyleKit.stretch(mid)
	split.add_child(mid)
	var strip=PanelContainer.new()
	strip.add_theme_stylebox_override("panel",StyleKit.box(Color("#151b23"),StyleKit.LINE,0,7))
	mid.add_child(strip)
	var striprow=HBoxContainer.new()
	strip.add_child(striprow)
	mode_label=StyleKit.label("Canvas",14,StyleKit.MINT)
	striprow.add_child(mode_label)
	striprow.add_child(StyleKit.label("/",14,StyleKit.MUTED))
	header=StyleKit.label("",13)
	header.size_flags_horizontal=SIZE_EXPAND_FILL
	header.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	striprow.add_child(header)
	striprow.add_child(StyleKit.button("+  Object",add_menu))
	center=VBoxContainer.new()
	StyleKit.stretch(center)
	mid.add_child(center)
	right_scroll=ScrollContainer.new()
	right_scroll.custom_minimum_size.x=245
	right_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right_scroll)
	inspector=VBoxContainer.new()
	inspector.size_flags_horizontal=SIZE_EXPAND_FILL
	right_scroll.add_child(inspector)
	var bottom=PanelContainer.new()
	bottom.add_theme_stylebox_override("panel",StyleKit.box(Color("#142630"),Color.TRANSPARENT,0,3))
	root.add_child(bottom)
	var foot=HBoxContainer.new()
	bottom.add_child(foot)
	status=StyleKit.label("Ready",12,StyleKit.MINT)
	status.size_flags_horizontal=SIZE_EXPAND_FILL
	status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(status)
	foot.add_child(StyleKit.label("OpenExhibit  0.1.0",11,StyleKit.MUTED))

func menu(parent,name_:String,actions:Dictionary):
	var m=MenuButton.new()
	m.text=name_
	parent.add_child(m)
	var keys=actions.keys()
	for key in keys: m.get_popup().add_item(key)
	m.get_popup().id_pressed.connect(func(i): actions[keys[i]].call())

func refresh():
	pages.clear()
	for i in p.scenes.size():
		pages.add_item(p.scenes[i].name)
		if p.scenes[i].id==edit_scene: pages.select(i)
	layers.clear()
	var objs=scene_data().get("objects",[])
	for i in range(objs.size()-1,-1,-1):
		var o=objs[i]
		layers.add_item(o.get("name",o.id))
		layers.set_item_metadata(layers.item_count-1,o.id)
		layers.set_item_tooltip(layers.item_count-1,o.kind+"  /  "+o.id)
		if o.id==selected: layers.select(layers.item_count-1)
	header.text=scene_data().get("name","")
	title_label.text=p.title+("  ●" if dirty else "")
	get_window().title=p.title+(" *" if dirty else "")+" — OpenExhibit Studio"
	mode_label.text=space
	for k in nav_buttons:
		nav_buttons[k].add_theme_stylebox_override("normal",StyleKit.box(Color("#183837") if k==space else Color.TRANSPARENT,Color.TRANSPARENT,4,2))
		nav_buttons[k].add_theme_color_override("font_color",StyleKit.MINT if k==space else StyleKit.MUTED)
	StyleKit.clear(center)
	canvas=null
	if space in ["Canvas","Test"]:
		canvas=Canvas.new()
		StyleKit.stretch(canvas)
		center.add_child(canvas)
		canvas.snap=snap_on
		canvas.picked.connect(pick)
		canvas.transformed.connect(func(id,r): mutate("Move / resize",func():Model.lookup(scene_data().objects,id).rect=r))
		canvas.configure(session,io.folder,edit_scene,selected,space=="Test")
		var toolsrow=HBoxContainer.new()
		center.add_child(toolsrow)
		toolsrow.add_child(StyleKit.button("−",func():canvas.zoom=maxf(0.3,canvas.zoom/1.2);canvas.layout_view()))
		toolsrow.add_child(StyleKit.button("Fit",func():canvas.zoom=1;canvas.layout_view()))
		toolsrow.add_child(StyleKit.button("+",func():canvas.zoom=minf(3,canvas.zoom*1.2);canvas.layout_view()))
		var snapping=CheckButton.new()
		snapping.text="Snap 8 px"
		snapping.button_pressed=snap_on
		snapping.toggled.connect(func(v):snap_on=v;canvas.snap=v)
		toolsrow.add_child(snapping)
		toolsrow.add_child(StyleKit.label("%d × %d"%p.canvas,12,StyleKit.MUTED))
		if space=="Test": toolsrow.add_child(StyleKit.button("Reset visit",session.reset))
	else: work.show_space(space,center)
	inspect()
	tell(msg if msg else "Ready · local project")

func scene_data(): return Model.lookup(p.scenes,edit_scene)
func obj(): return Model.lookup(scene_data().get("objects",[]),selected)

func set_space(k:String):
	if space=="Test" and k!="Test": reset_session()
	if k=="Test" and space!="Test":
		reset_session()
		session.scene=edit_scene
	space=k
	refresh()

func pick(id:String):
	selected=id
	if is_instance_valid(canvas):
		canvas.active=id
		if canvas.overlay: canvas.overlay.queue_redraw()
	layers.deselect_all()
	for i in layers.item_count:
		if layers.get_item_metadata(i)==id: layers.select(i)
	inspect()

func inspect():
	StyleKit.clear(inspector)
	var panel=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",StyleKit.box(StyleKit.PANEL,Color.TRANSPARENT,0,10))
	inspector.add_child(panel)
	var box=VBoxContainer.new()
	panel.add_child(box)
	box.add_child(StyleKit.label("INSPECTOR",12,StyleKit.MUTED))
	box.add_child(HSeparator.new())
	var o=obj()
	if not o.is_empty():
		box.add_child(StyleKit.label(o.get("name",o.id),16,StyleKit.TEXT))
		box.add_child(StyleKit.label(o.kind+"  /  "+o.id,11,StyleKit.MUTED))
		var namefield=field(box,"Layer name",o.get("name",o.id))
		var fields=[]
		if o.kind in ["text","button","entry"]: fields.append(["text",field(box,"Text",o.get("text",""))])
		if o.kind in ["text","panel","button","drawing","gauge","plot"]: fields.append(["color",field(box,"Colour · hex",o.get("color","#d9e2f0"))])
		if o.kind in ["text","button","entry"]: fields.append(["font",number(box,"Font size",o.get("font",24),7,180,1)])
		if o.kind in ["entry","slider","plot","gauge","drawing","fractal"]: fields.append(["bind",field(box,"Variable",o.get("bind",o.id))])
		if o.kind=="button": fields.append(["event",field(box,"On press",o.get("event","tap."+o.id))])
		box.add_child(StyleKit.label("Transform",14,StyleKit.BLUE))
		var dims=[]
		for j in 4: dims.append(number(box,["X","Y","Width","Height"][j],o.rect[j],1 if j>=2 else -8192,16384,1))
		box.add_child(StyleKit.button("Apply changes",func():
			mutate("Edit "+o.id,func():
				o.name=namefield.text
				for pair in fields: o[pair[0]]=pair[1].text if pair[1] is LineEdit else pair[1].value
				for j in 4: o.rect[j]=dims[j].value
			)
		,true))
		box.add_child(StyleKit.button("Delete layer",delete_object))
	else:
		box.add_child(StyleKit.label("Exhibit settings",17))
		box.add_child(StyleKit.label("Project",12,StyleKit.MUTED))
		var title=StyleKit.label(p.title,14)
		title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		box.add_child(title)
		box.add_child(StyleKit.label("Installation",12,StyleKit.MUTED))
		box.add_child(StyleKit.label(p.installation.get("preset","Custom"),14,StyleKit.MINT))
		box.add_child(StyleKit.label("%d scenes   %d outputs"%[p.scenes.size(),p.installation.outputs.size()],12))
		box.add_child(StyleKit.button("Project settings…",settings_dialog))
		box.add_child(HSeparator.new())
		box.add_child(StyleKit.label("Scene",14,StyleKit.BLUE))
		var sc=scene_data()
		var namefield=field(box,"Name",sc.name)
		var bg=field(box,"Background",sc.get("background","#101d30"))
		var tr=choice(box,"Transition",["cut","fade","slide"],sc.get("transition","cut"))
		box.add_child(StyleKit.button("Apply scene",func(): mutate("Edit scene",func():sc.name=namefield.text;sc.background=bg.text;sc.transition=tr.get_item_text(tr.selected))))
		box.add_child(StyleKit.button("Select a layer",func():if layers.item_count>0:pick(layers.get_item_metadata(0))))
	box.add_child(HSeparator.new())
	box.add_child(StyleKit.button("Detach / dock panel",float_inspector))

func float_inspector():
	if expanded:
		inspector.reparent(right_scroll)
		expanded.queue_free()
		expanded=null
		right_scroll.show()
	else:
		expanded=Window.new()
		expanded.title="OpenExhibit · Inspector"
		expanded.size=Vector2i(310,640)
		add_child(expanded)
		var scroll=ScrollContainer.new()
		expanded.add_child(scroll)
		StyleKit.fill(scroll)
		inspector.reparent(scroll)
		right_scroll.hide()
		expanded.close_requested.connect(float_inspector)

func tell(s:String):
	msg=s
	if status: status.text=s

func mutate(label:String,change:Callable):
	var before=p.duplicate(true)
	var old_scene=edit_scene
	var old_sel=selected
	change.call()
	var err=Model.validate(p)
	if err:
		p=before
		edit_scene=old_scene if not Model.lookup(p.scenes,old_scene).is_empty() else p.start
		selected=old_sel
		reset_session()
		refresh()
		tell(err)
		return
	undo_stack.append([before,old_scene,old_sel])
	if undo_stack.size()>60: undo_stack.pop_front()
	redo_stack.clear()
	dirty=true
	next_save=Time.get_ticks_msec()+700
	msg=label
	reset_session()
	refresh()

func historical(a:Array,b:Array):
	if a.is_empty(): return
	b.append([p.duplicate(true),edit_scene,selected])
	var previous=a.pop_back()
	p=previous[0]
	edit_scene=previous[1]
	selected=previous[2]
	dirty=true
	next_save=Time.get_ticks_msec()+500
	reset_session()
	refresh()
func undo(): historical(undo_stack,redo_stack)
func redo(): historical(redo_stack,undo_stack)

func field(box:Control,caption:String,value) -> LineEdit:
	box.add_child(StyleKit.label(caption,12,StyleKit.MUTED))
	var line=LineEdit.new()
	line.text=str(value)
	box.add_child(line)
	return line
func number(box:Control,caption:String,value,lo,hi,step=0.1) -> SpinBox:
	var line=HBoxContainer.new()
	box.add_child(line)
	var label=StyleKit.label(caption,12,StyleKit.MUTED)
	label.size_flags_horizontal=SIZE_EXPAND_FILL
	line.add_child(label)
	var spin=SpinBox.new()
	spin.min_value=lo
	spin.max_value=hi
	spin.step=step
	spin.value=value
	spin.custom_minimum_size.x=94
	line.add_child(spin)
	return spin
func choice(box:Control,caption:String,items:Array,current="") -> OptionButton:
	if caption: box.add_child(StyleKit.label(caption,12,StyleKit.MUTED))
	var c=OptionButton.new()
	for item in items: c.add_item(str(item))
	c.select(maxi(0,items.find(current)))
	box.add_child(c)
	return c
func dialog(title:String,w=520,h=480) -> VBoxContainer:
	var d=Window.new()
	d.title=title
	d.transient=true
	d.exclusive=true
	d.size=Vector2i(w,h)
	d.min_size=Vector2i(mini(400,w),240)
	add_child(d)
	d.close_requested.connect(d.queue_free)
	var sc=ScrollContainer.new()
	d.add_child(sc)
	StyleKit.fill(sc)
	var panel=PanelContainer.new()
	panel.size_flags_horizontal=SIZE_EXPAND_FILL
	sc.add_child(panel)
	var vb=VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(StyleKit.label(title,18,StyleKit.MINT))
	d.popup_centered()
	return vb
func file_dialog(title:String,mode,filters:Array,cb:Callable):
	var f=FileDialog.new()
	add_child(f)
	f.title=title
	f.access=FileDialog.ACCESS_FILESYSTEM
	f.file_mode=mode
	f.filters=PackedStringArray(filters)
	if io.folder and DirAccess.dir_exists_absolute(io.folder): f.current_dir=io.folder
	if mode==FileDialog.FILE_MODE_SAVE_FILE: f.current_file="exhibit.oex" if "*.oex" in str(filters) else "project.oes.json"
	f.file_selected.connect(func(path):cb.call(path);f.queue_free())
	f.canceled.connect(f.queue_free)
	f.popup_centered_ratio(0.72)

func discard_then(cb:Callable):
	if not dirty:
		cb.call()
		return
	var d=ConfirmationDialog.new()
	d.title="Discard unsaved edits?"
	d.dialog_text="Save your work first to keep these changes."
	d.ok_button_text="Discard and continue"
	add_child(d)
	d.confirmed.connect(func():cb.call();d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()
func new_project():
	discard_then(func():
		io=Storage.new()
		io.folder=Storage.absolute("user://working/"+Model.uid("draft"))
		DirAccess.make_dir_recursive_absolute(io.folder)
		switch_project(Model.fresh())
	)
func switch_project(value:Dictionary):
	p=value
	edit_scene=p.start
	selected=""
	space="Canvas"
	dirty=false
	next_save=0
	undo_stack.clear()
	redo_stack.clear()
	if FileAccess.file_exists(journal): DirAccess.remove_absolute(journal)
	reset_session()
	msg=""
	refresh()
func open_project(): file_dialog("Open exhibit",FileDialog.FILE_MODE_OPEN_FILE,["*.json,*.oex ; Projects and packages"],request_open)
func request_open(path:String):
	discard_then(func():
		var next=Storage.new()
		var loaded=next.open(path)
		if loaded.is_empty(): tell(next.error); return
		io=next
		switch_project(loaded)
	)
func save():
	if not io.path or io.packaged or (Paths.examples() and io.path.begins_with(Paths.examples()+"/")): save_as()
	else: save_to(io.path)
func save_as(): file_dialog("Save editable exhibit",FileDialog.FILE_MODE_SAVE_FILE,["*.json ; Project JSON"],save_to)
func save_to(path:String):
	if not path.to_lower().ends_with(".json"): path+=".oes.json"
	if io.save(p,path):
		dirty=false
		next_save=0
		if FileAccess.file_exists(journal): DirAccess.remove_absolute(journal)
		msg="Saved "+io.path
		refresh()
	else: tell(io.error)
func pack_project():
	file_dialog("Export portable exhibit",FileDialog.FILE_MODE_SAVE_FILE,["*.oex ; Portable exhibit"],func(path):
		if not path.to_lower().ends_with(".oex"): path+=".oex"
		tell("Exported "+path if io.pack(p,path) else io.error)
	)
func examples_dialog():
	var box=dialog("Example projects",590,620)
	var root=Paths.examples()
	if not root: box.add_child(StyleKit.label("No example directory found.")); return
	var dirs=DirAccess.get_directories_at(root)
	dirs.sort()
	for sub in dirs:
		var path=root.path_join(sub).path_join("project.oes.json")
		var p0=Storage.json_at(path)
		if p0 is Dictionary: box.add_child(StyleKit.button(sub.get_slice("-",0)+"   "+p0.title,func():box.get_window().queue_free();request_open(path)))
func add_scene():
	var box=dialog("New scene",430,260)
	var namefield=field(box,"Scene name","New scene")
	box.add_child(StyleKit.button("Create scene",func():
		var name_=namefield.text.strip_edges()
		if not name_:return
		box.get_window().queue_free()
		mutate("New scene",func():
			edit_scene=Model.uid("scene")
			p.scenes.append({"id":edit_scene,"name":name_,"background":"#101d30","objects":[]})
			selected=""
		)
	,true))
func add_menu():
	var box=dialog("Add component",420,540)
	for k in Model.KINDS:
		box.add_child(StyleKit.button(k.capitalize(),func():
			box.get_window().queue_free()
			if k in ["image","audio","video","model"]: import_media(k)
			else: add_object(k)
		))
func add_object(k:String,asset=""):
	mutate("Add "+k,func():
		selected=Model.uid(k)
		var o={"id":selected,"name":k.capitalize(),"kind":k,"rect":[80,80,340,96]}
		if k in ["text","button","entry"]: o.text="New "+k
		if k=="panel": o.color="#234259"
		if k in ["orbit","image","drawing","model","video","particles","fractal"]: o.rect=[100,90,540,340]
		if k=="contest":o.rect=[40,32,p.canvas[0]-80,p.canvas[1]-64]
		if k in ["entry","slider","drawing","gauge","fractal"]: o.bind=selected
		if k in ["entry","slider"]:
			var ev=("change." if k=="entry" else "input.")+selected
			p.rules.append({"id":Model.uid("rule"),"event":ev,"actions":[{"op":"set","target":selected,"value":"$value"}]})
		if asset: o.asset=asset
		scene_data().objects.append(o)
		space="Canvas"
	)
func import_media(k:String):
	var ext={"image":"*.png,*.jpg,*.jpeg,*.webp,*.svg","audio":"*.ogg,*.mp3,*.wav","video":"*.ogv","model":"*.glb,*.gltf,*.obj"}
	file_dialog("Import "+k,FileDialog.FILE_MODE_OPEN_FILE,[ext[k]],func(path): add_asset_path(path,k))
func add_asset_path(path:String,k:String):
	var id=io.import_asset(path,p)
	if id: add_object(k,id)
	else: tell(io.error)
func dropped(files:PackedStringArray):
	for file in files:
		var ext=file.get_extension().to_lower()
		if ext in ["json","oex"]: request_open(file);return
		if ext in ["png","jpg","jpeg","svg","webp"]: add_asset_path(file,"image")
		elif ext in ["wav","ogg","mp3"]: add_asset_path(file,"audio")
		elif ext=="ogv": add_asset_path(file,"video")
		elif ext in ["glb","gltf","obj"]: add_asset_path(file,"model")
		else: tell("Unsupported format: "+ext)
func delete_object():
	if obj().is_empty(): return
	mutate("Delete layer",func():
		scene_data().objects.erase(obj())
		for t in p.timelines:
			t.keys=t.get("keys",[]).filter(func(k):return k.object!=selected or k.scene!=edit_scene)
		selected=""
	)
func duplicate_object():
	if obj().is_empty(): return
	mutate("Duplicate layer",func():
		var copy=obj().duplicate(true)
		selected=Model.uid(copy.kind)
		copy.id=selected
		copy.name=copy.get("name",copy.kind)+" copy"
		copy.rect[0]+=16
		copy.rect[1]+=16
		scene_data().objects.append(copy)
	)
func move_layer(d:int):
	var o=obj()
	if o.is_empty(): return
	mutate("Reorder layer",func():
		var a=scene_data().objects
		var i=a.find(o)
		a.remove_at(i)
		a.insert(clampi(i+d,0,a.size()),o)
	)
func toggle_test(): set_space("Canvas" if space=="Test" else "Test")
func settings_dialog():
	var box=dialog("Project settings",460,510)
	var title=field(box,"Exhibit title",p.title)
	var expr=CheckButton.new()
	expr.text="Enable bounded math expressions"
	expr.button_pressed=p.settings.get("expressions",false)
	box.add_child(expr)
	var w=number(box,"Design width · px",p.canvas[0],32,8192,1)
	var h=number(box,"Design height · px",p.canvas[1],32,8192,1)
	var idle=number(box,"Idle reset · seconds (0 = off)",p.settings.get("idle_seconds",0),0,86400,1)
	var opts=p.scenes.map(func(s):return s.id)
	var start=choice(box,"First scene",opts,p.start)
	var tracks=[""]+p.timelines.map(func(t):return t.id)
	var auto=choice(box,"Startup timeline",tracks,p.settings.get("autoplay",""))
	box.add_child(StyleKit.button("Apply",func():
		box.get_window().queue_free()
		mutate("Project settings",func():p.settings.expressions=expr.button_pressed;p.title=title.text;p.canvas=[w.value,h.value];p.settings.idle_seconds=idle.value;p.start=opts[start.selected];p.settings.autoplay=tracks[auto.selected])
	,true))
func commands():
	var box=dialog("Command palette",500,530)
	var search=field(box,"Search commands","")
	var list=VBoxContainer.new()
	box.add_child(list)
	var options={"Save project":save,"Open project":open_project,"Export package":pack_project,"Add component":add_menu,"New scene":add_scene,"Examples":examples_dialog,"Undo":undo,"Redo":redo,"Project settings":settings_dialog}
	for k in SPACES: options["Workspace · "+k]=set_space.bind(k)
	var filter=func(q):
		StyleKit.clear(list)
		for k in options:
			if q.to_lower() in k.to_lower(): list.add_child(StyleKit.button(k,func():box.get_window().queue_free();options[k].call()))
	search.text_changed.connect(filter)
	filter.call("")
	search.grab_focus()
func guide():
	var box=dialog("Studio quick guide",580,430)
	for s in ["1. Open File → Examples and choose an exhibit.","2. Select a layer in Explorer or directly on the canvas.","3. Drag to move. Drag the bottom-right handle to resize.","4. Edit Inspector fields and choose Apply changes.","5. Use Logic to connect a press or sensor to an action.","6. Test exhibit starts a private visitor session.","7. Save As in a new folder. Export .oex for the player.","The full operator manual is in docs/USER-MANUAL.md."]:
		var label=StyleKit.label(s,13)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
func _process(_dt):
	if not booted: return
	if space in ["Test","Timeline","Hardware","Logic","Mapping","Flipbook","Science"]: session.wall_tick()
	if dirty and next_save and Time.get_ticks_msec()>=next_save:
		next_save=0
		var err=Storage.write_json(journal,{"project":p,"path":io.path,"folder":io.folder,"revision":io.revision,"packaged":io.packaged})
		if err: tell("Recovery write failed · "+err)
func _unhandled_key_input(ev):
	if not ev is InputEventKey or not ev.pressed or ev.echo: return
	var mod=ev.ctrl_pressed or ev.meta_pressed
	if mod:
		match ev.keycode:
			KEY_S: if ev.shift_pressed:save_as()
			KEY_O: open_project()
			KEY_Z: if ev.shift_pressed:redo()
			KEY_Y: redo()
			KEY_P: commands()
			KEY_D: duplicate_object()
			_: return
		if ev.keycode==KEY_S and not ev.shift_pressed: save()
		if ev.keycode==KEY_Z and not ev.shift_pressed: undo()
	elif ev.keycode==KEY_F5: toggle_test()
	elif ev.keycode==KEY_DELETE and space=="Canvas": delete_object()
	else: return
	get_viewport().set_input_as_handled()

func _notification(what):
	if what==NOTIFICATION_WM_CLOSE_REQUEST and booted and dirty:
		Storage.write_json(journal,{"project":p,"path":io.path,"folder":io.folder,"revision":io.revision,"packaged":io.packaged})


func _input(ev):
	if not booted or space!="Test":return
	if ev is InputEventScreenTouch:
		if ev.pressed:touch_start=ev.position
		elif absf(ev.position.x-touch_start.x)>110 and absf(ev.position.y-touch_start.y)<80:
			session.dispatch("book.next" if ev.position.x<touch_start.x else "book.prev",1,true)
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode in [KEY_RIGHT,KEY_LEFT]:
		session.dispatch("book.next" if ev.keycode==KEY_RIGHT else "book.prev",1,true)

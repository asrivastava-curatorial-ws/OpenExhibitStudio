extends RefCounted
const StyleKit=preload("res://core/skin.gd")
const Model=preload("res://core/project.gd")
const Store=preload("res://core/storage.gd")
const Mapping=preload("res://core/mapping.gd")
const ModelView=preload("res://core/model_view.gd")
const Stage=preload("res://core/stage.gd")
const Feed=preload("res://core/feed.gd")
const PinPlanner=preload("res://studio/pin_planner.gd")
const Pad=preload("res://studio/calibration_pad.gd")
const ContestTools=preload("res://studio/contest_tools.gd")
var contest
var host
var out_index=0
var pattern=0
var mesh_edit=false
var track_index=0
var graph_mode=false
func _init(h):
	host=h
	contest=ContestTools.new(self)

# Transient workspace widgets unsubscribe as soon as a tab is rebuilt.
func watch(signal_:Signal,widget:Node,callback:Callable):
	signal_.connect(callback)
	widget.tree_exiting.connect(func():
		if not signal_.is_null() and signal_.is_connected(callback):signal_.disconnect(callback)
	,CONNECT_ONE_SHOT)
func show_space(k:String,parent:Control):
	var sc=ScrollContainer.new()
	StyleKit.stretch(sc)
	sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var panel=PanelContainer.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",StyleKit.box(StyleKit.BG,Color.TRANSPARENT,0,14))
	sc.add_child(panel)
	var box=VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	panel.add_child(box)
	match k:
		"Installation","3D scene": installation(box,k=="3D scene")
		"Mapping": mapping(box)
		"Timeline": timeline(box)
		"Live quiz": contest.workspace(box)
		"Logic": logic(box)
		"Hardware": hardware(box)
		"Flipbook": book(box)
		"Science": science(box)
		"Assets": assets(box)
		"Deployment": deployment(box)
func heading(b:Control,title:String,desc:String):
	b.add_child(StyleKit.label(title,23,Color.WHITE))
	note(b,desc)
func note(b:Control,txt:String):
	var n=StyleKit.label(txt,12,StyleKit.MUTED)
	n.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	b.add_child(n)
	return n
func row(b:Control) -> HFlowContainer:
	var a=HFlowContainer.new()
	b.add_child(a)
	return a
func btn(b:Control,label:String,cb:Callable,hi=false):
	b.add_child(StyleKit.button(label,cb,hi))
func text_value(c:OptionButton):return c.get_item_text(c.selected)
func json_value(v:String):
	var j=JSON.new()
	return j.data if j.parse(v)==OK else v
func out():
	out_index=clampi(out_index,0,host.p.installation.outputs.size()-1)
	return host.p.installation.outputs[out_index]
func output_select(box):
	var outputs=host.p.installation.outputs
	var o=out()
	var ids=outputs.map(func(v):return v.id)
	var sel=host.choice(box,"Output",ids,o.id)
	sel.item_selected.connect(func(i):out_index=i;host.refresh())

func installation(box,scene3d):
	heading(box,"Installation designer" if not scene3d else "3D scene","Drag the model to orbit. Use the mouse wheel to change distance. Dimensions are in metres.")
	var m=ModelView.new()
	m.custom_minimum_size.y=240
	box.add_child(m)
	m.setup()
	m.installation(host.p.installation)
	if scene3d:
		for o in host.scene_data().objects:
			if o.kind=="model" and host.p.assets.has(o.get("asset","")):
				var err=m.load_model(host.io.folder.path_join(host.p.assets[o.asset].path))
				if err: note(box,err)
		btn(box,"Import 3D model…",host.import_media.bind("model"))
		note(box,"OBJ triangles, embedded glTF and GLB scene assets can also be placed as interactive objects on the canvas.")
	var layout=host.choice(box,"Installation preset",Mapping.PRESETS,host.p.installation.get("preset","Kiosk"))
	var count=host.number(box,"Outputs · 0 uses preset count",0,0,32,1)
	var s=host.p.installation.surfaces[0]
	var radius=host.number(box,"Radius · m",s.get("radius",2),0.1,100,0.1)
	var height=host.number(box,"Physical height · m",s.get("height",2.4),0.1,100,0.1)
	var arc=host.number(box,"Cylinder coverage · degrees",s.get("arc",180),10,360,1)
	btn(box,"Apply installation layout",func():
		host.mutate("Replace installation layout",func():host.p.installation=Mapping.make(text_value(layout),int(count.value),radius.value,height.value,arc.value);out_index=0)
	,true)
	note(box,"Applying a layout replaces the installation’s outputs and calibration. Undo restores the previous layout. Attach a UV-mapped mesh to a custom-object or relief layout to render it from the projector position.")
	if s.kind in ["sphere","dome"]:
		var texture_type=host.choice(box,"Surface texture layout",["equirectangular","cubemap_cross"],s.get("source_layout","equirectangular"))
		texture_type.item_selected.connect(func(i):host.mutate("Set texture layout",func():s.source_layout=["equirectangular","cubemap_cross"][i]))
	if s.kind=="mesh":
		btn(box,"Assign surface mesh…",func():host.file_dialog("Attach UV-mapped surface",FileDialog.FILE_MODE_OPEN_FILE,["*.obj,*.gltf,*.glb"],func(path):
			var id=host.io.import_asset(path,host.p)
			if id:host.mutate("Assign projection mesh",func():s.asset=id)
			else:host.tell(host.io.error)))
	btn(box,"Edit surface geometry…",func():json_editor("Surface definitions",host.p.installation.surfaces,func(v):host.p.installation.surfaces=v))
func json_editor(title:String,original,apply:Callable):
	var box=host.dialog(title,690,590)
	var t=TextEdit.new()
	t.custom_minimum_size=Vector2(360,330)
	t.text=JSON.stringify(original,"  ",false)
	box.add_child(t)
	var err=note(box,"Changes are validated before they enter the project.")
	btn(box,"Validate and apply",func():
		var parser=JSON.new()
		if parser.parse(t.text)!=OK:
			err.text="Line %d · %s"%[parser.get_error_line(),parser.get_error_message()]
			return
		if typeof(parser.data)!=typeof(original): err.text="Use the original JSON value type.";return
		box.get_window().queue_free()
		host.mutate(title,apply.bind(parser.data))
	,true)
func mapping(box):
	heading(box,"Projection calibration","Check each output against the reference grid. Drag the cyan quadrilateral’s corners to set its perspective transform.")
	output_select(box)
	var o=out()
	var s=Model.lookup(host.p.installation.surfaces,o.surface)
	var surface_label=s.get("name",s.id)+"   /   "+s.kind
	note(box,surface_label+"   ·   optical calibration unverified")
	var modes=host.choice(box,"Preview",["Exhibit content","Alignment grid","Colour bars"],["Exhibit content","Alignment grid","Colour bars"][pattern])
	var vp=SubViewport.new()
	vp.size=Vector2i(host.p.canvas[0],host.p.canvas[1])
	vp.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(vp)
	var stage=Stage.new()
	vp.add_child(stage)
	stage.configure(host.session,host.io.folder,o.get("scene","@live"),false,true)
	var frame=AspectRatioContainer.new()
	frame.ratio=float(o.size[0])/o.size[1]
	frame.custom_minimum_size.y=180
	box.add_child(frame)
	var feed=Feed.new()
	frame.add_child(feed)
	feed.custom_minimum_size=Vector2(160,120)
	feed.pattern=pattern
	feed.configure(vp,stage,o,s,host.session,host.io.folder)
	modes.item_selected.connect(func(i):pattern=i;feed.pattern=i;feed.calibrate())
	var wp=host.choice(box,"Warp handles",["Corner pin","3 × 3 mesh"],"3 × 3 mesh" if mesh_edit else "Corner pin")
	wp.item_selected.connect(func(i):mesh_edit=i==1;host.refresh())
	var pad=Pad.new()
	pad.custom_minimum_size.y=135
	pad.points=(o.get("mesh",Mapping.lattice_default()) if mesh_edit else o.warp).duplicate(true)
	box.add_child(pad)
	pad.changed.connect(func(w):host.mutate("Warp calibration",func():o["mesh" if mesh_edit else "warp"]=w;o.erase("capture_check")))
	var r=row(box)
	btn(r,"Output settings…",output_settings)
	btn(box,"Import surveyed pose or luminance response…",func():host.file_dialog("Optical measurement report",FileDialog.FILE_MODE_OPEN_FILE,["*.json"],func(path):contest.apply_optical(o,path)))
	if s.kind=="plane":
		btn(box,"Camera calibration wizard…",contest.calibration_wizard.bind(o))
		btn(box,"Apply measured warp (replaces manual mesh)…",func():host.file_dialog("Measured planar warp",FileDialog.FILE_MODE_OPEN_FILE,["*.json"],func(path):contest.import_warp(o,s,path)))
		if o.has("capture_check"):note(box,"Imported optical check · %.3f px p95 on independent dots"%o.capture_check.independent_dots.p95_px)
	if s.kind in ["sphere","cylinder"]:btn(r,"Coverage analysis",func():coverage(s))
	btn(r,"Save profile…",func():host.file_dialog("Save calibration profile",FileDialog.FILE_MODE_SAVE_FILE,["*.json"],func(path):
		var err=Store.write_json(path,{"format":"openexhibit-calibration","version":1,"installation":host.p.installation})
		host.tell(err if err else "Saved calibration profile.")))
	btn(r,"Load profile…",func():host.file_dialog("Load calibration profile",FileDialog.FILE_MODE_OPEN_FILE,["*.json"],func(path):
		var v=Store.json_at(path)
		if v is Dictionary and v.get("format")=="openexhibit-calibration" and v.get("version")==1 and v.has("installation"):
			host.mutate("Load calibration profile",func():host.p.installation=v.installation)
		else:host.tell("Invalid calibration profile.")))
	btn(r,"Save preview PNG…",func():host.file_dialog("Save warped output still",FileDialog.FILE_MODE_SAVE_FILE,["*.png"],func(path):save_still(o,s,vp,stage,path)))
func save_still(o,s,vp,stage,path):
	if DisplayServer.get_name()=="headless":host.tell("A graphics display is needed for image export.");return
	var out_vp=SubViewport.new()
	out_vp.size=Vector2i(o.size[0],o.size[1])
	out_vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	host.add_child(out_vp)
	var feed=Feed.new()
	out_vp.add_child(feed)
	feed.size=Vector2(out_vp.size)
	feed.pattern=pattern
	feed.configure(vp,stage,o,s,host.session,host.io.folder)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img=out_vp.get_texture().get_image()
	host.tell("Saved warped still: "+path if img and img.save_png(path)==OK else "Could not export the output image.")
	out_vp.queue_free()
func output_settings():
	var o=out()
	var b=host.dialog("Output "+o.id,550,650)
	var screens=host.number(b,"Operating-system screen index",o.screen,0,63,1)
	var w=host.number(b,"Width · px",o.size[0],32,8192,1)
	var h=host.number(b,"Height · px",o.size[1],32,8192,1)
	var opts=["@live"]+host.p.scenes.map(func(v):return v.id)
	var scene=host.choice(b,"Content scene",opts,o.get("scene","@live"))
	var gamma=host.number(b,"Gamma",o.get("gamma",1),0.1,4)
	var black=host.number(b,"Black lift",o.get("black",0),0,0.8,0.01)
	var power=host.number(b,"Blend exponent",o.get("blend_power",1),0.1,5)
	var thr=host.number(b,"Throw ratio",o.get("throw",1),0.02,20,0.01)
	var edges=[]
	for j in 4: edges.append(host.number(b,"Blend "+["left","right","top","bottom"][j],o.blend[j],0,1,0.01))
	btn(b,"Apply output",func():
		b.get_window().queue_free()
		host.mutate("Edit output",func():
			o.screen=int(screens.value);o.size=[w.value,h.value];o.scene=text_value(scene);o.gamma=gamma.value;o.black=black.value;o.blend_power=power.value;o.throw=thr.value
			for j in 4:o.blend[j]=edges[j].value
		)
	,true)
	btn(b,"Optical position, aim, shift, gain, mask and view…",func():b.get_window().queue_free();json_editor("Output calibration",o,func(v):host.p.installation.outputs[out_index]=v))

func logic(box):
	heading(box,"Visual logic","Connect a visitor event or input channel to an action. Each matching rule can operate more than one device or scene.")
	var bar=row(box)
	btn(bar,"+ When–If–Do rule",func():rule_form({}),true)
	btn(bar,"Variables…",func():json_editor("Initial variables",host.p.variables,func(v):host.p.variables=v))
	btn(bar,"Rule list" if graph_mode else "Node graph",func():graph_mode=not graph_mode;host.refresh())
	if graph_mode: graph(box)
	else:
		for rule in host.p.rules:
			var r=row(box)
			btn(r,rule.event+" → "+str(rule.actions.size())+" actions",rule_form.bind(rule))
			btn(r,"Break" if not host.session.breaks.has(rule.id) else "Unbreak",func():
				if host.session.breaks.has(rule.id):host.session.breaks.erase(rule.id)
				else: host.session.breaks[rule.id]=true
				host.refresh())
	var event=host.field(box,"Test event","tap.answer")
	var value=host.field(box,"Value","1")
	var r=row(box)
	btn(r,"Send event",func():host.session.dispatch(event.text,json_value(value.text),true))
	btn(r,"Resume breakpoint",host.session.resume_debug)
	monitor(box)
func rule_form(existing:Dictionary):
	var b=host.dialog("When–If–Do rule",530,620)
	var event=host.field(b,"When · event ID",existing.get("event","tap."+str(host.selected if host.selected else "button")))
	var c=existing.get("if",{})
	var left=host.field(b,"If · left operand",c.get("left","$value"))
	var op=host.choice(b,"Comparison",Model.TESTS,c.get("op","always"))
	var right=host.field(b,"Right operand",c.get("right",0))
	var first=existing.get("actions",[{}])
	var a=first[0] if first.size() else {}
	var action=host.choice(b,"Do · action",Model.OPS,a.get("op","set"))
	var dest=host.field(b,"Target variable, channel, event or scene",a.get("target","score"))
	var value=host.field(b,"Value · literal, $value or $variable",a.get("value","$value"))
	btn(b,"Save rule",func():
		var rule=existing.duplicate(true)
		rule.id=rule.get("id",Model.uid("rule"));rule.event=event.text.strip_edges();rule["if"]={"op":text_value(op),"left":json_value(left.text),"right":json_value(right.text)}
		var act={"op":text_value(action),"target":dest.text,"value":json_value(value.text)}
		if not rule.has("actions") or rule.actions.is_empty():rule.actions=[act]
		else:rule.actions[0]=act
		b.get_window().queue_free()
		host.mutate("Save visual rule",func():
			if existing.is_empty():host.p.rules.append(rule)
			else:host.p.rules[host.p.rules.find(existing)]=rule)
	,true)
	if not existing.is_empty():
		btn(b,"Edit all actions…",func():b.get_window().queue_free();json_editor("Action sequence",existing.actions,func(v):existing.actions=v))
		btn(b,"Delete rule",func():b.get_window().queue_free();host.mutate("Delete rule",func():host.p.rules.erase(existing)))
func graph(box):
	var g=GraphEdit.new()
	g.custom_minimum_size.y=340
	box.add_child(g)
	var data={}
	for j in host.p.rules.size():
		var rule=host.p.rules[j]
		var trigger=GraphNode.new()
		trigger.name="rule_"+str(j)
		trigger.title=rule.event
		trigger.position_offset=Vector2(24,28+j*119)
		g.add_child(trigger)
		trigger.add_child(StyleKit.label("IF  "+str(rule.get("if",{}).get("op","always")),12))
		trigger.set_slot(0,false,0,StyleKit.BLUE,true,0,StyleKit.MINT)
		data[str(trigger.name)]=rule
		for i in rule.actions.size():
			var act=rule.actions[i]
			var node=GraphNode.new()
			node.name="a_%d_%d"%[j,i]
			node.title=act.op
			node.position_offset=Vector2(320+i*190,28+j*119)
			g.add_child(node)
			node.add_child(StyleKit.label(str(act.get("target",""))))
			node.set_slot(0,true,0,StyleKit.BLUE,false,0,StyleKit.MINT)
			data[str(node.name)]=act
			g.connect_node(trigger.name,0,node.name,0)
	g.connection_request.connect(func(fr,_fp,to,_tp):
		var a=data.get(str(fr),{})
		var dest=data.get(str(to),{})
		if a.has("actions") and dest.has("op") and not dest in a.actions:host.mutate("Connect graph action",func():a.actions.append(dest.duplicate(true))))
	g.disconnection_request.connect(func(fr,_fp,to,_tp):
		var rule=data.get(str(fr),{})
		if rule.has("actions"):host.mutate("Disconnect graph action",func():rule.actions.erase(data.get(str(to),{}))))
	g.right_disconnects=true
	note(box,"Drag an event output to an existing action to add that action to the rule. Drag off an action’s input port to disconnect.")
func monitor(box):
	var v=StyleKit.label(JSON.stringify(host.session.vars),12,StyleKit.MINT)
	v.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(v)
	var log_=RichTextLabel.new()
	log_.custom_minimum_size.y=110
	log_.scroll_following=true
	log_.text="\n".join(host.session.trace.slice(-16))
	box.add_child(log_)
	watch(host.session.updated,v,func():if is_instance_valid(v):v.text=JSON.stringify(host.session.vars).left(1200))
	watch(host.session.traced,log_,func(line):if is_instance_valid(log_):log_.text=(log_.text+"\n"+line).right(3600))

func hardware(box):
	heading(box,"Hardware studio","Inject a virtual channel, inspect the event trace or connect to the authenticated local gateway.")
	var plan=PinPlanner.new(host)
	btn(box,"Board pins and component profiles…",plan.open)
	var channels=[]
	for d in host.p.devices:
		for c in d.get("channels",[]):
			if c is Dictionary and c.get("direction","input")=="input": channels.append(str(c.id))
	if channels.is_empty():channels=["dial","button","page"]
	var sel=host.choice(box,"Virtual input",channels)
	var v=host.number(box,"Input value",0,-65535,65535,0.1)
	var r=row(box)
	btn(r,"Inject sample",func():host.session.sensor(text_value(sel),v.value),true)
	btn(r,"Pulse button",func():host.session.sensor("button",1);host.session.sensor("button",0))
	btn(r,"Arm virtual outputs",func():host.session.virtual_armed=true;host.tell("Virtual outputs armed."))
	btn(r,"Disarm all",func():host.session.disarm();host.tell("Outputs disarmed."))
	var out_text=note(box,"Virtual outputs · "+JSON.stringify(host.session.virtual_outputs))
	watch(host.session.updated,out_text,func():if is_instance_valid(out_text):out_text.text="Virtual outputs · "+JSON.stringify(host.session.virtual_outputs))
	box.add_child(HSeparator.new())
	var state=note(box,host.gateway.status)
	watch(host.gateway.status_changed,state,func(s):if is_instance_valid(state):state.text=s)
	var token=host.field(box,"Gateway token",OS.get_environment("OPENEXHIBIT_TOKEN"))
	token.secret=true
	var port=host.number(box,"Loopback port",18440,1024,65535,1)
	var row2=row(box)
	btn(row2,"Connect",func():host.gateway.connect_local(token.text,int(port.value)))
	btn(row2,"Arm physical outputs",host.gateway.arm)
	btn(row2,"Disconnect",host.gateway.close)
	btn(row2,"Edit channel profiles…",func():json_editor("Logical devices",host.p.devices,func(val):host.p.devices=val))
	monitor(box)

func timeline(box):
	heading(box,"Show timeline","Cues fire on forward playback. Seeking samples animation and disarms outputs.")
	var r=row(box)
	btn(r,"+ Timeline",func():host.mutate("Add timeline",func():host.p.timelines.append({"id":Model.uid("show"),"name":"New show","duration":30,"loop":false,"cues":[],"keys":[]});track_index=host.p.timelines.size()-1))
	if host.p.timelines.is_empty():return
	track_index=clampi(track_index,0,host.p.timelines.size()-1)
	var t=host.p.timelines[track_index]
	var tracks=host.p.timelines.map(func(a):return a.get("name",a.id))
	var choose=host.choice(box,"Show",tracks,tracks[track_index])
	choose.item_selected.connect(func(i):track_index=i;host.refresh())
	var line=row(box)
	btn(line,"▶ Play / restart",func():host.session.play(t.id),true)
	btn(line,"Pause / resume",func():if host.session.timeline==t.id:host.session.playing=not host.session.playing)
	var read=StyleKit.label("0.00 / %.2f s"%t.duration,13,StyleKit.MINT)
	box.add_child(read)
	var scrub=HSlider.new()
	scrub.max_value=t.duration;scrub.step=0.01
	box.add_child(scrub)
	scrub.value_changed.connect(func(x):host.session.timeline=t.id;host.session.seek(x))
	watch(host.session.clock_changed,scrub,func():
		if is_instance_valid(scrub) and host.session.timeline==t.id:scrub.set_value_no_signal(host.session.head);read.text="%.2f / %.2f s"%[host.session.head,t.duration])
	var rr=row(box)
	btn(rr,"+ Cue…",func():cue_form(t,scrub.value))
	btn(rr,"+ Animation key…",func():key_form(t,scrub.value))
	btn(rr,"Edit tracks…",func():json_editor("Show tracks",t,func(v):host.p.timelines[track_index]=v))
	var sorted=t.get("cues",[]).duplicate()
	sorted.sort_custom(func(a,b):return a.at<b.at)
	for c in sorted:box.add_child(StyleKit.label("%6.2f s   %s   %s"%[c.at,c.action.op,c.action.get("target","")],13))
	monitor(box)
func cue_form(t,at):
	var b=host.dialog("Add show cue",450,370)
	var when=host.number(b,"Time · seconds",at,0,t.duration,0.01)
	var op=host.choice(b,"Action",Model.OPS,"goto")
	var target=host.field(b,"Target",host.edit_scene)
	var value=host.field(b,"Value","1")
	btn(b,"Add cue",func():b.get_window().queue_free();host.mutate("Add timeline cue",func():t.cues.append({"at":when.value,"action":{"op":text_value(op),"target":target.text,"value":json_value(value.text)}})),true)
func key_form(t,at):
	var objs=host.scene_data().objects
	if objs.is_empty():host.tell("Add a canvas object first.");return
	var b=host.dialog("Add animation key",450,420)
	var obj=host.choice(b,"Object",objs.map(func(v):return v.id),host.selected)
	var prop=host.choice(b,"Property",["x","y","opacity","rotation"])
	var when=host.number(b,"Time · seconds",at,0,t.duration,0.01)
	var value=host.number(b,"Value",0,-8192,8192,0.01)
	var curve=host.choice(b,"Curve to next key",["linear","smooth","step"])
	btn(b,"Add key",func():b.get_window().queue_free();host.mutate("Add animation key",func():t.keys.append({"at":when.value,"scene":host.edit_scene,"object":text_value(obj),"property":text_value(prop),"value":value.value,"curve":text_value(curve)})),true)

func book(box):
	heading(box,"Flipbook pages","Pages use ordinary scenes. Link them in reading order and reuse the same book on a touchscreen or two calibrated projector feeds.")
	for sc in host.p.scenes:
		btn(box,sc.name,func():host.edit_scene=sc.id;host.selected="";host.set_space("Canvas"))
	var r=row(box)
	btn(r,"+ Blank page",host.add_scene)
	btn(r,"Import image page…",func():host.file_dialog("Import page image",FileDialog.FILE_MODE_OPEN_FILE,["*.jpg,*.png,*.webp"],image_page))
	btn(r,"Build page navigation",link_book,true)
	note(box,"The supplied PDF importer creates one scene per PDF page. The Player accepts right and left arrow keys. Physical page IDs use the page input channel.")
func image_page(path):
	var id=host.io.import_asset(path,host.p)
	if not id:host.tell(host.io.error);return
	host.mutate("Import book page",func():
		var page=Model.uid("page")
		host.p.scenes.append({"id":page,"name":path.get_file().get_basename(),"transition":"slide","objects":[{"id":"page_art","kind":"image","asset":id,"rect":[0,0,host.p.canvas[0],host.p.canvas[1]]}]})
		host.edit_scene=page)
func link_book():
	host.mutate("Link book pages",func():
		var scenes=host.p.scenes
		host.p.rules=host.p.rules.filter(func(v):return not v.id.begins_with("booklink_"))
		for j in scenes.size():
			var s=scenes[j]
			s.objects=s.objects.filter(func(o):return not o.id in ["booklink_prev","booklink_next"])
			for side in ["prev","next"]:
				var dest=scenes[clampi(j+(-1 if side=="prev" else 1),0,scenes.size()-1)].id
				var event="book."+side+"."+s.id
				s.objects.append({"id":"booklink_"+side,"kind":"button","text":"‹" if side=="prev" else "›","event":event,"rect":[12 if side=="prev" else host.p.canvas[0]-82,host.p.canvas[1]-70,70,56]})
				var act=[{"op":"goto","target":dest}]
				host.p.rules.append({"id":Model.uid("booklink_nav"),"event":event,"actions":act})
				host.p.rules.append({"id":Model.uid("booklink_key"),"event":"book."+side,"if":{"left":"$current_page","op":"==","right":s.id},"actions":[{"op":"emit","target":event}]})
			host.p.rules.append({"id":Model.uid("booklink_enter"),"event":"enter."+s.id,"actions":[{"op":"set","target":"current_page","value":s.id}]})
			host.p.rules.append({"id":Model.uid("booklink_sensor"),"event":"input.page","if":{"op":"==","right":j+1},"actions":[{"op":"goto","target":s.id}]})
		host.p.variables.current_page=host.p.start)
func science(box):
	heading(box,"Scientific components","Place an interactive model on the active scene. The component inspector controls its variable binding and size.")
	for item in [["orbit","Orbital periods","Eight planets advance using relative sidereal periods. Orbit radii and planet sizes are illustrative."],["fractal","Sierpiński triangle","Set the bound variable to a recursion depth between zero and seven."],["plot","Live sensor plot","Plot up to 160 recent samples from the configured channel."],["particles","Motion field","Set motion_x and motion_y between zero and one to move the particle origin."],["gauge","Linear gauge","Map a numeric variable onto a bounded scale."]]:
		btn(box,"+ "+item[1],host.add_object.bind(item[0]))
		note(box,item[2])
func assets(box):
	heading(box,"Asset library","Imported files travel with the project. SHA-256 digests are checked on open and export.")
	var r=row(box)
	for k in ["image","audio","video","model"]:btn(r,"+ "+k.capitalize(),host.import_media.bind(k))
	for id in host.p.assets:
		var a=host.p.assets[id]
		box.add_child(StyleKit.label(a.path.get_file(),13))
		note(box,id+"  ·  "+a.sha256.left(20))
	btn(box,"Browse exhibit templates",host.examples_dialog)
func deployment(box):
	heading(box,"Deployment manager","Export the exhibit and open it on a player. Each output carries its own display index, scene and resolution.")
	for o in host.p.installation.outputs:
		box.add_child(StyleKit.label("%s  ·  screen %d  ·  %d × %d"%[o.id,o.screen,o.size[0],o.size[1]],13))
	var r=row(box)
	btn(r,"Export .oex package…",host.pack_project,true)
	btn(r,"Verify project assets",func():
		var err=Model.validate(host.p)
		for a in host.p.assets.values():
			if FileAccess.get_sha256(host.io.folder.path_join(a.path))!=a.sha256:err="Failed checksum: "+a.path;break
		host.tell(err if err else "Verified project and %d asset checksums."%host.p.assets.size()))
	btn(r,"Launch standalone preview",launch_player)
	note(box,"F2 cycles output patterns. F5 resets the visitor session. F11 toggles full screen. Escape leaves full screen and then closes the player.")
func launch_player():
	var path=Store.absolute("user://previews/"+Model.uid("exhibit")+".oex")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if not host.io.pack(host.p,path):host.tell(host.io.error);return
	var engine=OS.get_executable_path()
	var args=[]
	var pack=engine.get_base_dir().path_join("player.pck")
	if FileAccess.file_exists(pack):args=["--main-pack",pack]
	elif not OS.has_feature("editor"):
		var sibling=engine.get_base_dir().path_join("OpenExhibitPlayer"+(".exe" if OS.get_name()=="Windows" else ""))
		if not FileAccess.file_exists(sibling):host.tell("Install the Player beside Studio to launch a preview.");return
		engine=sibling
	else:args=["--path",ProjectSettings.globalize_path("res://"),"res://player/player.tscn"]
	args.append_array(["--","--project",path])
	var pid=OS.create_process(engine,PackedStringArray(args))
	host.tell("Player launched · process "+str(pid) if pid>0 else "Could not launch the Player.")

func coverage(s):
	var box=host.dialog("Projector coverage",690,490)
	var img=Image.create_empty(144,72,false,Image.FORMAT_RGB8)
	var total=0.0
	var dark=0.0
	var overlap=0.0
	var center=Mapping.v3(s.get("position",[0,0,0]))
	var outputs=host.p.installation.outputs.filter(func(o):return o.surface==s.id)
	for y in 72:
		var lat=PI*(.5-(y+.5)/72)
		var weight=cos(lat) if s.kind=="sphere" else 1.0
		for x in 144:
			var a=((x+.5)/144-.5)*(TAU if s.kind=="sphere" else deg_to_rad(s.arc))
			var point=Vector3(sin(a)*s.radius,0,cos(a)*s.radius)
			if s.kind=="sphere":point=Vector3(point.x*cos(lat),s.radius*sin(lat),point.z*cos(lat))
			else:point.y=(.5-(y+.5)/72)*s.height
			var count=0
			for o in outputs:
				if Mapping.sees(Mapping.local_frame(s)*point+center,o,s):count+=1
			img.set_pixel(x,y,[Color("#a54850"),StyleKit.MINT,Color("#ffc873")][mini(2,count)])
			total+=weight
			if count==0:dark+=weight
			if count>1:overlap+=weight
	var t=TextureRect.new()
	t.texture=ImageTexture.create_from_image(img)
	t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size.y=250
	box.add_child(t)
	note(box,"Red = unlit   ·   Teal = one projector   ·   Amber = overlap")
	note(box,"Estimated unlit area %.1f%%  ·  overlap %.1f%%"%[100*dark/total,100*overlap/total])
	if s.kind=="sphere":
		for pole in [-1,1]:
			var covered=false
			for o in outputs:covered=covered or Mapping.sees(center+Vector3(0,s.radius*pole,0),o,s)
			note(box,("North" if pole>0 else "South")+" pole · "+("covered" if covered else "unlit"))
	note(box,"Ideal geometry before digital masking and warping. Occlusion by visitors, mounts and nearby objects requires an on-site survey.")

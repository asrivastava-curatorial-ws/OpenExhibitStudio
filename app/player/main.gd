extends Control
const Storage=preload("res://core/storage.gd")
const Model=preload("res://core/project.gd")
const Session=preload("res://core/session.gd")
const Stage=preload("res://core/stage.gd")
const Feed=preload("res://core/feed.gd")
const StyleKit=preload("res://core/skin.gd")
const Paths=preload("res://core/paths.gd")
const ClockFollower=preload("res://core/lan_clock.gd")
const Gateway=preload("res://core/gateway_client.gd")
var store=Storage.new()
var session
var sources={}
var windows=[]
var feeds=[]
var gateway
var preview=false
var browse:FileDialog
var notice:Label
var picker=false
var clock_owner=true
var fixed_step=0.0
var touch_start=Vector2.ZERO
var follower
var operator_window:Window
var kiosk=false

func _ready():
	if session: return
	theme=StyleKit.theme()
	get_window().title="OpenExhibit Player"
	var path=Paths.first_project()
	kiosk="--kiosk" in OS.get_cmdline_user_args()
	var rate=float(Paths.option("--render-fps","0"))
	fixed_step=1.0/rate if rate>=1 and rate<=120 else 0.0
	var deployment=Paths.option("--deployment")
	if deployment:
		path=""
		var state=Storage.json_at(deployment.path_join("current.json"))
		if state is Dictionary:
			for k in ["active","previous"]:
				var name_=str(state.get(k,""))
				if name_.length()==68 and name_.ends_with(".oex") and name_.left(64).is_valid_hex_number(false):
					var candidate=deployment.path_join(name_)
					if FileAccess.file_exists(candidate) and FileAccess.get_sha256(candidate)==name_.left(64):
						path=candidate
						break
	if path=="" or not FileAccess.file_exists(path):
		choose("Open an exhibit package or project.")
		return
	load_path(path)

func choose(message: String):
	StyleKit.clear(self)
	var center=CenterContainer.new()
	add_child(center)
	StyleKit.fill(center)
	var box=VBoxContainer.new()
	center.add_child(box)
	box.add_child(StyleKit.label("OpenExhibit Player",26,StyleKit.MINT))
	box.add_child(StyleKit.label(message))
	box.add_child(StyleKit.button("Open exhibit…",open_dialog,true))
	picker=true

func open_dialog():
	browse=FileDialog.new()
	add_child(browse)
	browse.access=FileDialog.ACCESS_FILESYSTEM
	browse.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	browse.filters=PackedStringArray(["*.oex,*.json ; OpenExhibit"])
	browse.file_selected.connect(load_path)
	browse.popup_centered_ratio(0.7)

func load_path(path: String):
	var p=store.open(path)
	if p.is_empty():
		printerr(store.error)
		choose(store.error)
		return
	picker=false
	StyleKit.clear(self)
	session=Session.new(p)
	gateway=Gateway.new()
	add_child(gateway)
	gateway.attach(session)
	var clock_host=Paths.option("--clock-host")
	if clock_host and fixed_step==0:
		follower=ClockFollower.new()
		add_child(follower)
		follower.start(session,clock_host,int(Paths.option("--clock-port","18442")),OS.get_environment("OES_CLOCK_KEY"))
	if fixed_step==0 and OS.get_environment("OPENEXHIBIT_TOKEN"):
		gateway.connect_local(OS.get_environment("OPENEXHIBIT_TOKEN"),int(Paths.option("--port","18440")))
	start_outputs(session,store.folder)

func start_outputs(s,dir: String):
	session=s
	var prj=s.project
	var active=Paths.option("--output")
	var fullscreen=kiosk or "--fullscreen" in OS.get_cmdline_user_args()
	var output_count=0
	for o in prj.installation.outputs:
		if active!="" and o.id!=active: continue
		var sc=o.get("scene","@live")
		if not sources.has(sc):
			var vp=SubViewport.new()
			vp.size=Vector2i(prj.canvas[0],prj.canvas[1])
			vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			vp.handle_input_locally=true
			add_child(vp)
			var stage=Stage.new()
			vp.add_child(stage)
			stage.configure(s,dir,sc,false,sources.size()>0)
			sources[sc]=[vp,stage]
		var f=Feed.new()
		var win=get_window() if output_count==0 else Window.new()
		if output_count>0:
			add_child(win)
			win.close_requested.connect(func(): get_tree().quit())
			windows.append(win)
			win.add_child(f)
		else: add_child(f)
		var screen=int(o.get("screen",0))
		var available=DisplayServer.get_screen_count()
		var has_screen=screen>=0 and screen<available
		if has_screen: win.current_screen=screen
		win.size=Vector2i(o.size[0],o.size[1])
		win.title=prj.title+"   /   "+o.id
		if fullscreen and has_screen: win.mode=Window.MODE_FULLSCREEN
		elif output_count>0: win.position=Vector2i(40+40*output_count,40+30*output_count)+DisplayServer.screen_get_position(clampi(screen,0,maxi(0,available-1)))
		if not has_screen: session.log_line("Display %d unavailable. %s opened as a window."%[screen,o.id])
		StyleKit.fill(f)
		f.configure(sources[sc][0],sources[sc][1],o,Model.lookup(prj.installation.surfaces,o.surface),s,dir)
		feeds.append(f)
		output_count+=1
	if output_count==0: choose("Unknown output ID: "+active)

func _process(_dt):
	if session and clock_owner:
		if fixed_step>0:session.tick(fixed_step)
		else:session.wall_tick()

func _input(ev):
	if not session:return
	if ev is InputEventScreenTouch:
		if ev.pressed:touch_start=ev.position
		elif absf(ev.position.x-touch_start.x)>110 and absf(ev.position.y-touch_start.y)<80:
			session.dispatch("book.next" if ev.position.x<touch_start.x else "book.prev",1,true)
	if not ev is InputEventKey or not ev.pressed or ev.echo: return
	if ev.keycode==KEY_F12:
		session.disarm()
		return
	if ev.keycode==KEY_F10:
		maintenance()
		return
	if kiosk and ev.keycode in [KEY_ESCAPE,KEY_F11,KEY_F2,KEY_F5]:return
	match ev.keycode:
		KEY_ESCAPE:
			if gateway: gateway.disarm()
			if get_window().mode==Window.MODE_FULLSCREEN:
				for w in [get_window()]+windows: w.mode=Window.MODE_WINDOWED
			else: get_tree().quit()
		KEY_F11:
			for w in [get_window()]+windows: w.mode=Window.MODE_WINDOWED if w.mode==Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		KEY_F2:
			for f in feeds:
				f.pattern=(f.pattern+1)%3
				f.calibrate()
		KEY_F5: session.reset()
		KEY_RIGHT: session.dispatch("book.next",1,true)
		KEY_LEFT: session.dispatch("book.prev",1,true)

func maintenance():
	if operator_window:
		operator_window.grab_focus()
		return
	operator_window=Window.new()
	operator_window.title="OpenExhibit · Operator"
	operator_window.size=Vector2i(480,420)
	operator_window.transient=true
	operator_window.exclusive=true
	add_child(operator_window)
	var panel=PanelContainer.new()
	operator_window.add_child(panel)
	StyleKit.fill(panel)
	var box=VBoxContainer.new()
	panel.add_child(box)
	var hint=StyleKit.label("Enter the site operator password.",14,StyleKit.MINT)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var password=LineEdit.new()
	password.secret=true
	box.add_child(password)
	var expected=OS.get_environment("OPENEXHIBIT_OPERATOR_KEY")
	var unlock=func():
		if expected.length()<16 or not Crypto.new().constant_time_compare(expected.to_utf8_buffer(),password.text.to_utf8_buffer()):
			hint.text="Set a site password of at least 16 characters in OPENEXHIBIT_OPERATOR_KEY." if expected.length()<16 else "Incorrect operator password."
			password.clear()
			return
		StyleKit.clear(box)
		box.add_child(StyleKit.label(session.project.title,20,StyleKit.MINT))
		var state=StyleKit.label(gateway.status if gateway else "Virtual playback",12)
		state.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		box.add_child(state)
		if gateway:
			gateway.status_changed.connect(state.set_text)
			box.add_child(StyleKit.button("Connect local hardware",func():gateway.connect_local(OS.get_environment("OPENEXHIBIT_TOKEN"),int(Paths.option("--port","18440")))))
			if not follower and fixed_step==0:box.add_child(StyleKit.button("Arm physical outputs",gateway.arm))
		box.add_child(StyleKit.button("Disarm outputs",session.disarm))
		box.add_child(StyleKit.button("Reset visitor session",session.reset))
		box.add_child(StyleKit.button("Cycle alignment pattern",func():
			for f in feeds:f.pattern=(f.pattern+1)%3;f.calibrate()))
		if follower:box.add_child(StyleKit.label("Clock RTT %.1f ms · drift %.1f ms"%[follower.rtt_ms,follower.drift_ms],12))
		box.add_child(StyleKit.button("Close player",func():session.disarm();get_tree().quit()))
	box.add_child(StyleKit.button("Unlock",unlock,true))
	password.text_submitted.connect(func(_v):unlock.call())
	operator_window.close_requested.connect(func():operator_window.queue_free();operator_window=null)
	operator_window.popup_centered()

func _exit_tree():
	if is_instance_valid(gateway):gateway.disarm()

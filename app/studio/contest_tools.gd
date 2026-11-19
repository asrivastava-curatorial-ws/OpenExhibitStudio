extends RefCounted
const Paths=preload("res://core/paths.gd")
const Store=preload("res://core/storage.gd")
const Model=preload("res://core/project.gd")
var _owner:WeakRef
var work:
	get:return _owner.get_ref()
var info={}
var info_file=""
var room_pid=-1
var address="127.0.0.1"
var self_paced=false
var resumed_db=""

func _init(owner):_owner=weakref(owner)

func tool_path(file:String)->String:
	return Paths.examples().get_base_dir().path_join("tools/"+file)

func python(desktop=false)->Array:
	var preferred=OS.get_environment("OPENEXHIBIT_PYTHON")
	if preferred:return [preferred,[]]
	if OS.get_name()=="Windows" and not desktop:
		for rel in ["bin/python/python.exe","bin/windows/python/python.exe"]:
			var embedded=Paths.examples().get_base_dir().path_join(rel)
			if FileAccess.file_exists(embedded):return [embedded,[]]
	return ["py",["-3"]] if OS.get_name()=="Windows" else ["python3",[]]

func launch(script:String,args:Array,check="")->int:
	var exec=python(check!="")
	var path=tool_path(script)
	if not FileAccess.file_exists(path):work.host.tell("Required installed tool is missing · "+path);return -1
	if check:
		var log_output=[]
		var failed=OS.execute(exec[0],PackedStringArray(exec[1]+["-c",check]),log_output,true)
		if failed!=0:
			work.host.tell("Calibration needs desktop Python, Tk, NumPy, Pillow and OpenCV. See docs/CALIBRATION.md.")
			return -1
	var pid=OS.create_process(exec[0],PackedStringArray(exec[1]+[path]+args))
	if pid<=0:work.host.tell("Python 3 could not start. Set OPENEXHIBIT_PYTHON to its executable.")
	return pid

func workspace(box):
	var host=work.host
	work.heading(box,"Live quiz","Run a contest on this computer or choose the local Wi-Fi interface for audience phones.")
	if room_pid>0 and not OS.is_process_running(room_pid):room_pid=-1;info={}
	var options:Array=["127.0.0.1"]
	for ip in IP.get_local_addresses():
		if ip.is_valid_ip_address() and ":" not in ip and not ip in options:
			var octets=ip.split(".")
			if ip.begins_with("10.") or ip.begins_with("192.168.") or ip.begins_with("169.254.") or (octets.size()==4 and octets[0]=="172" and int(octets[1])>=16 and int(octets[1])<=31):options.append(ip)
	var deck=host.p.get("extensions",{}).get("contest",{})
	work.note(box,"Contest deck   /   "+str(deck.get("title","Science after hours"))+"   ·   "+str(deck.get("questions",[]).size() if not deck.is_empty() else 10)+" rounds")
	var interfaces=host.choice(box,"Visitor network address · 127.0.0.1 for rehearsal",options,address)
	interfaces.item_selected.connect(func(i):address=options[i])
	var modes=host.choice(box,"Playback mode",["Host-paced live","Self-paced individual"],"Self-paced individual" if self_paced else "Host-paced live")
	modes.item_selected.connect(func(i):self_paced=i==1)
	var r=work.row(box)
	if room_pid<=0:
		work.btn(r,"Start new contest",func():start_room(""),true)
		work.btn(r,"Resume saved contest…",func():host.file_dialog("Resume local contest database",FileDialog.FILE_MODE_OPEN_FILE,["*.sqlite"],func(path):start_room(path)))
	else:
		work.btn(r,"Host console",func():if info.has("host"):OS.shell_open(info.host))
		work.btn(r,"Projector view",func():if info.has("display"):OS.shell_open(info.display))
		work.btn(r,"Stop contest service",stop_room)
	if info.has("join"):work.note(box,"Phones on the same network can join at "+info.join)
	if resumed_db:work.note(box,"Session database   /   "+resumed_db)
	work.btn(box,"Import deck into exhibit…",func():host.file_dialog("Attach quiz deck",FileDialog.FILE_MODE_OPEN_FILE,["*.json"],func(path):
		var data=Store.json_at(path)
		if not data is Dictionary or data.get("format")!="oes-quiz" or data.get("version")!=1 or not data.get("questions") is Array or data.questions.is_empty():host.tell("Choose a version 1 contest deck.");return
		host.mutate("Attach quiz deck",func():
			if not host.p.has("extensions"):host.p.extensions={}
			host.p.extensions["contest"]=data)))
	work.btn(box,"Add live scoreboard to current scene",func():host.add_object("contest"))
	work.note(box,"Edit rounds in the host console before starting. Download the edited deck there, import it here, then save to carry it inside the exhibit. The score layer uses the same output calibration as other exhibit content.")

func start_room(database:String):
	if room_pid>0 and OS.is_process_running(room_pid):return
	var dir=Store.absolute("user://contests")
	DirAccess.make_dir_recursive_absolute(dir)
	var stem=dir.path_join(Model.uid("room"))
	resumed_db=database if database!="" else stem+".sqlite"
	info_file=stem+"-host.json"
	var args=["--db",resumed_db,"--info",info_file,"--bind",address]
	if self_paced:args.append("--self-paced")
	var deck=work.host.p.get("extensions",{}).get("contest",{})
	if not deck.is_empty():
		var file=stem+"-deck.json"
		if Store.write_json(file,deck)!="":work.host.tell("Could not stage the contest deck.");return
		args.append_array(["--deck",file])
	room_pid=launch("quiz.py",args)
	if room_pid<=0:return
	for i in 60:
		await work.host.get_tree().create_timer(.1).timeout
		if FileAccess.file_exists(info_file):
			var v=Store.json_at(info_file)
			if v is Dictionary and v.has("error"):
				room_pid=-1;work.host.tell(str(v.error));return
			if v is Dictionary and v.has("host"):
				info=v
				work.host.refresh()
				work.host.tell("Contest running · "+info.join)
				OS.shell_open(info.host)
				return
		if not OS.is_process_running(room_pid):break
	work.host.tell("Contest startup failed. Check Python, ports 8786/8787 and the selected interface.")

func stop_room():
	if not info.has("host"):return
	var url=str(info.host)
	var call=HTTPRequest.new()
	work.host.add_child(call)
	call.timeout=4
	call.request_completed.connect(func(_a,code,_b,_c):
		call.queue_free()
		if code!=200:work.host.tell("The contest service could not be stopped.");return
		info={};room_pid=-1
		work.host.refresh()
		work.host.tell("Contest stopped. Its database is available for resume or export."))
	var destination=url.get_slice("/host#",0)+"/api/host/stop"
	call.request(destination,["Content-Type: application/json","Authorization: Bearer "+url.get_slice("#",1)],HTTPClient.METHOD_POST,"{}")

func calibration_wizard(output):
	var running=launch("calibration_wizard.py",["--size",str(int(output.size[0])),str(int(output.size[1]))],"import tkinter, numpy, PIL, cv2")
	if running>0:work.host.tell("Camera calibration wizard opened.")

func import_warp(output,surface:Dictionary,path:String):
	var host=work.host
	var v=Store.json_at(path)
	if surface.kind!="plane" or not v is Dictionary or v.get("format")!="oes-measured-warp" or v.get("version")!=1 or v.get("size")!=output.size or v.get("status")!="capture-validated" or not v.get("warp") is Array:
		host.tell("Choose a measured planar warp matching this output’s pixel dimensions.");return
	for key in ["independent_dots","spatial_holdout"]:
		var m=v.get(key)
		var limits=v.get("limits")
		if not m is Dictionary or not limits is Dictionary or not Model.numeric(m.get("p95_px")) or not Model.numeric(m.get("max_px")) or not Model.numeric(limits.get("p95_px")) or not Model.numeric(limits.get("max_px")):
			host.tell("The calibration report has incomplete residual measurements.");return
		if m.p95_px<0 or m.max_px<m.p95_px or limits.p95_px<=0 or limits.p95_px>10 or limits.max_px>3*limits.p95_px or m.p95_px>limits.p95_px or m.max_px>limits.max_px or m.get("samples",0)<6:
			host.tell("This report exceeds its calibration limits.");return
	host.mutate("Apply measured planar warp",func():
		output.warp=v.warp
		output.erase("mesh")
		output["capture_check"]={"method":v.get("method"),"independent_dots":v.independent_dots,"spatial_holdout":v.spatial_holdout})

func apply_optical(output,path:String):
	var v=Store.json_at(path)
	if not v is Dictionary or v.get("version")!=1:work.host.tell("Choose a version 1 pose or photometry report.");return
	if v.get("format")=="oes-survey-pose":
		if v.get("size")!=output.size or not Model.vector(v.get("position"),3) or not Model.vector(v.get("aim"),3) or not Model.vector(v.get("up"),3) or not Model.vector(v.get("shift"),2) or not Model.numeric(v.get("throw")):
			work.host.tell("Survey pose and square-pixel intrinsics must match this output.");return
		work.host.mutate("Apply surveyed projector pose",func():
			for key in ["position","aim","up","throw","shift"]:output[key]=v[key]
			output.erase("capture_check"))
	elif v.get("format")=="oes-photometry" and Model.numeric(v.get("gamma")) and Model.vector(v.get("gain"),3) and Model.numeric(v.get("max_fractional_error")) and Model.numeric(v.get("limit")) and v.max_fractional_error>=0 and v.max_fractional_error<=v.limit:
		work.host.mutate("Apply measured luminance response",func():output.gamma=v.gamma;output.gain=v.gain;output.black=0)
	else:work.host.tell("Invalid pose or measured luminance report.")

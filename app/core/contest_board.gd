extends Control
const StyleKit=preload("res://core/skin.gd")
const Paths=preload("res://core/paths.gd")
var qr_request:HTTPRequest
var qr_preview:TextureRect
var qr_texture:Texture2D
var qr_key=""
var request:HTTPRequest
var poll:Timer
var box:VBoxContainer
var base="http://127.0.0.1:8787"
var design=false
var snapshot:Dictionary={}
var last_layout=""
var clock_text:Label
var countdown_until=0

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	box=VBoxContainer.new()
	add_child(box)
	StyleKit.fill(box)
	box.add_theme_constant_override("separation",12)
	if design:
		box.add_child(StyleKit.label("LIVE QUIZ",20,StyleKit.MINT))
		box.add_child(StyleKit.label("Host questions and standings appear here during a contest.",23))
		return
	var override_base=Paths.option("--quiz-url",OS.get_environment("OPENEXHIBIT_QUIZ_URL"))
	if override_base:base=override_base.trim_suffix("/")
	qr_request=HTTPRequest.new()
	add_child(qr_request)
	qr_request.timeout=3
	qr_request.body_size_limit=262144
	qr_request.request_completed.connect(qr_received)
	request=HTTPRequest.new()
	add_child(request)
	request.timeout=2
	request.body_size_limit=2097152
	request.request_completed.connect(received)
	poll=Timer.new()
	add_child(poll)
	poll.wait_time=1.0
	poll.timeout.connect(fetch)
	poll.start()
	waiting()
	fetch()

func fetch():
	if request.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED:request.request(base+"/api/state")

func waiting():
	if last_layout=="offline":return
	last_layout="offline"
	snapshot={}
	clock_text=null
	StyleKit.clear(box)
	box.add_child(StyleKit.label("QUIZ CONTEST",22,StyleKit.MINT))
	box.add_child(StyleKit.label("Waiting for the host",40))
	box.add_child(line("Start a room from Studio’s Live quiz workspace.",24,StyleKit.MUTED))

func line(value:String,pt:int,color:Color)->Label:
	var label=StyleKit.label(value,pt,color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func received(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:waiting();return
	var s=JSON.parse_string(body.get_string_from_utf8())
	if not s is Dictionary or not s.has("phase") or not s.has("index"):waiting();return
	snapshot=s
	countdown_until=Time.get_ticks_msec()+int(float(s.get("seconds_left",0))*1000)
	var signature=JSON.stringify([s.phase,s.index,s.question,s.get("answer"),s.get("leaders"),s.get("team_leaders"),s.get("distribution"),s.get("code"),s.title,s.get("explanation","")])
	if signature!=last_layout:
		last_layout=signature
		clock_text=null
		StyleKit.clear(box)
		box.add_child(line(s.title+"    /    ROOM "+s.code,25,StyleKit.MINT))
		if s.phase in ["lobby","practice"]:
			box.add_child(line("Self-paced contest" if s.phase=="practice" else "Join the contest",57,Color.WHITE))
			box.add_child(line(s.get("join_url",""),32,StyleKit.BLUE))
			qr_preview=TextureRect.new()
			qr_preview.custom_minimum_size=Vector2(208,208)
			qr_preview.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			qr_preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			qr_preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.add_child(qr_preview)
			if qr_key!=s.get("join_url","") or qr_texture==null:
				qr_key=s.get("join_url","")
				qr_texture=null
				qr_request.cancel_request()
				qr_request.request(base+"/join.svg")
			else:qr_preview.texture=qr_texture
		elif s.phase in ["standings","finished"]:
			box.add_child(line("Final standings" if s.phase=="finished" else "Leaderboard",42,Color.WHITE))
			for group in ["team_leaders","leaders"]:
				var rows=s.get(group,[])
				if rows.size()>0:box.add_child(line("Teams" if group=="team_leaders" else "Players",21,StyleKit.MINT))
				for r in rows.slice(0,3):box.add_child(line("%d   %s     %d pts"%[r.rank,r.name,r.score],27,StyleKit.TEXT))
		else:
			var q=s.question
			box.add_child(line("ROUND %d / %d"%[int(s.index)+1,s.rounds],22,StyleKit.MUTED))
			box.add_child(line(q.prompt,41,Color.WHITE))
			if q.has("image"):
				var im=Image.new()
				var raw=Marshalls.base64_to_raw(str(q.image).get_slice(",",1))
				var err=im.load_png_from_buffer(raw) if str(q.image).begins_with("data:image/png") else im.load_jpg_from_buffer(raw)
				if err==OK:
					var pic=TextureRect.new()
					pic.texture=ImageTexture.create_from_image(im)
					pic.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
					pic.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					pic.custom_minimum_size.y=130
					box.add_child(pic)
			if q.has("options"):box.add_child(line("   •   ".join(q.options),29,StyleKit.TEXT))
			if q.has("labels"):box.add_child(line("Items   "+"   ·   ".join(q.labels),22,StyleKit.TEXT))
			if s.phase=="reveal":
				var answer=s.get("answer")
				if answer!=null:box.add_child(line("Answer   "+(" → ".join(answer) if answer is Array else str(answer)),30,StyleKit.MINT))
				if s.get("explanation",""):box.add_child(line(s.explanation,22,StyleKit.TEXT))
			for item in s.get("distribution",[]).slice(0,4):box.add_child(line("%s    %d"%[item[0],item[1]],20,StyleKit.BLUE))
		clock_text=line("",21,StyleKit.MUTED)
		box.add_child(clock_text)
	_process(0)

func qr_received(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:return
	var im=Image.new()
	if im.load_svg_from_buffer(body,6)!=OK:return
	qr_texture=ImageTexture.create_from_image(im)
	if is_instance_valid(qr_preview):qr_preview.texture=qr_texture

func _process(_dt):
	if not is_instance_valid(clock_text) or snapshot.is_empty():return
	if snapshot.phase=="lobby":clock_text.text=str(int(snapshot.players))+" joined"
	else:
		var phase_text={"open":"Accepting answers","paused":"Paused","closed":"Time is up","reveal":"Round result","standings":"Standings","finished":"Contest complete"}.get(snapshot.phase,"")
		var timer=("    %d s"%ceili(maxf(0,countdown_until-Time.get_ticks_msec())/1000.0)) if snapshot.phase=="open" else ""
		clock_text.text="%s%s    %d / %d answered"%[phase_text,timer,snapshot.received,snapshot.players]

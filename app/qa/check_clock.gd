extends SceneTree
const Model=preload("res://core/project.gd")
const Session=preload("res://core/session.gd")
const Follower=preload("res://core/lan_clock.gd")
const Paths=preload("res://core/paths.gd")
var now=0
var session
var link
func _initialize():
	var project=Model.fresh()
	project.timelines=[{"id":"sequence","duration":15,"cues":[],"keys":[]}]
	session=Session.new(project)
	link=Follower.new()
	root.add_child(link)
	link.start(session,"127.0.0.1",int(Paths.option("--port","18442")),OS.get_environment("OES_CLOCK_KEY"))
	now=Time.get_ticks_msec()
func _process(_delta):
	if session:session.wall_tick()
	if link and link.epoch and link.last_ok>now and session.timeline=="sequence" and session.playing:
		print("PASS native LAN clock follower + Python publisher, authenticated reply, timeline running; RTT ",link.rtt_ms," ms")
		quit()
	elif Time.get_ticks_msec()-now>6000:
		printerr("FAIL no verified local clock sample");quit(1)
	return false

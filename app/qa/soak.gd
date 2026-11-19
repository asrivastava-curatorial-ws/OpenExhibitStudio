extends SceneTree
const Session=preload("res://core/session.gd")
const Player=preload("res://player/player.tscn")
const Model=preload("res://core/project.gd")
const Paths=preload("res://core/paths.gd")
var runtime
var started=0
var samples=0
var seconds=600.0
var last_report=0
func _initialize():call_deferred("begin")
func begin():
	seconds=float(Paths.option("--seconds","600"))
	runtime=Player.instantiate()
	runtime.session=Session.new(Model.fresh())
	root.add_child(runtime)
	runtime.load_path(Paths.examples().path_join("11-mixed/project.oes.json"))
	started=Time.get_ticks_msec()
func _process(_dt):
	if not started:return false
	var elapsed=(Time.get_ticks_msec()-started)/1000.0
	runtime.session.sensor("dial",samples%101)
	samples+=1
	if int(elapsed)>=last_report:
		print("SAMPLE ",JSON.stringify({"seconds":int(elapsed),"events":samples,"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC))}))
		last_report=int(elapsed)+10
	if elapsed>=seconds:
		print("SOAK_FINISHED ",samples)
		quit()
	return false

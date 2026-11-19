extends SceneTree
const Model=preload("res://core/project.gd")
const Storage=preload("res://core/storage.gd")
const Session=preload("res://core/session.gd")
var failures=0
var count=0
func check(ok: bool,name_: String):
	count+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+name_)
func _initialize():
	var p=Model.fresh()
	var root=Storage.absolute("user://checks/"+Model.uid("test"))
	var io=Storage.new()
	io.folder=root
	p.variables={"score":0}
	p.rules=[{"id":"score","event":"tap.answer","actions":[{"op":"add","target":"score","value":1}]}]
	check(Model.validate(p)=="","schema accepts a fresh exhibit")
	check(io.save(p,root+"/sample.oes.json"),"save a project")
	var opened=io.open(root+"/sample.oes.json")
	if opened.is_empty(): print(io.error)
	check(opened==JSON.parse_string(JSON.stringify(p)),"save and reopen preserve data")
	check(io.pack(p,root+"/sample.oex"),"write an exhibit package")
	check(io.open(root+"/sample.oex")==JSON.parse_string(JSON.stringify(p)),"verify and reopen package")
	var s=Session.new(p)
	s.dispatch("tap.answer",null,true)
	check(s.vars.score==1,"visitor rule updates session state")
	p.rules.append({"id":"loop","event":"cycle","actions":[{"op":"emit","target":"cycle"}]})
	s.dispatch("cycle")
	check(s.trace[-1].begins_with("Repeated"),"event cycles bounded and reported")
	var clean=extension_roundtrip(p,root)
	check(clean,"independent saves preserve private extensions")
	var plain=root+"/sample.oes.json"
	DirAccess.rename_absolute(plain,plain+".bak")
	check(not io.open(plain).is_empty() and FileAccess.file_exists(plain),"interrupted-save backup restored")
	var invalid=p.duplicate(true)
	invalid.version=2
	check(Model.validate(invalid)!="","newer file version rejected")
	var q=p.duplicate(true)
	q.settings.expressions=true
	var math_session=Session.new(q)
	check(math_session.val({"fn":"mul","args":["$value",4]},3)==12,"opt-in arithmetic expression")
	math_session.project.timelines=[{"id":"reentrant","duration":2,"cues":[{"at":0,"action":{"op":"play","target":"reentrant"}}]}]
	math_session.play("reentrant")
	check("Cyclic timeline start blocked: reentrant" in math_session.trace,"nested timeline cycle bounded")
	print("%d checks, %d failures"%[count,failures])
	quit(1 if failures else 0)

func extension_roundtrip(p:Dictionary,root:String):
	var copy=p.duplicate(true)
	copy.extensions["museum.team"]={"languages":["bn","hi"]}
	var store=Storage.new()
	store.folder=root
	if not store.save(copy,root+"/extra.oes.json"):return false
	var reopened=store.open(root+"/extra.oes.json")
	return reopened.extensions["museum.team"].languages==["bn","hi"]

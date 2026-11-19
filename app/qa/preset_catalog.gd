extends SceneTree
const Mapping=preload("res://core/mapping.gd")
const Model=preload("res://core/project.gd")
const Store=preload("res://core/storage.gd")
func _initialize():
	var root=OS.get_cmdline_user_args()
	if root.is_empty():quit(2);return
	var presets={}
	for k in Mapping.PRESETS:presets[k]=Mapping.make(k)
	var err=Store.write_json(root[0],{"project":Model.fresh(),"layouts":presets})
	quit(0 if err=="" else 1)

extends SceneTree
const Paths=preload("res://core/paths.gd")
const Store=preload("res://core/storage.gd")
const Session=preload("res://core/session.gd")
const Model=preload("res://core/project.gd")
const Player=preload("res://player/player.tscn")
var failures=0
func _initialize():call_deferred("suite")
func suite():
	var names=DirAccess.get_directories_at(Paths.examples())
	names.sort()
	for slug in names:
		var player=Player.instantiate()
		player.session=Session.new(Model.fresh())
		root.add_child(player)
		player.load_path(Paths.examples().path_join(slug+"/project.oes.json"))
		for i in 5:await process_frame
		var healthy=player.feeds.size()==player.session.project.installation.outputs.size()
		for source in player.sources.values():
			var stage=source[1]
			healthy=healthy and stage.nodes.size()==stage.current().objects.size()
			for n in stage.nodes.values():
				if n is TextureRect:healthy=healthy and n.texture!=null
				if n is VideoStreamPlayer:healthy=healthy and n.stream!=null and n.is_playing()
		if not healthy:failures+=1
		print(("PASS" if healthy else "FAIL")," native example playback · ",slug," · ",player.feeds.size()," feed(s)")
		player.queue_free()
		for i in 3:await process_frame
	print("RESULT ",names.size()," example launches, ",failures," failures.")
	quit(1 if failures else 0)

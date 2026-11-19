extends SceneTree
const Model = preload("res://core/project.gd")
const Store = preload("res://core/storage.gd")
const Mapping = preload("res://core/mapping.gd")
const Session = preload("res://core/session.gd")
const Feed = preload("res://core/feed.gd")
const Stage = preload("res://core/stage.gd")


func _initialize():
	call_deferred("run_test")


func run_test():
	if DisplayServer.get_name() == "headless":
		printerr("Run under an OpenGL display.")
		quit(2)
		return
	var p = Model.fresh()
	p.canvas = [128, 128]
	p.scenes[0].background = "#ff2233"
	var m = "v -1 -1 0\nv 1 -1 0\nv 1 1 0\nv -1 1 0\nvt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\nf 1/1 2/2 3/3 4/4\n"
	var io = Store.new()
	io.folder = Store.absolute("user://checks/" + Model.uid("mesh"))
	Store.write_bytes(io.folder.path_join("fixture.obj"), m.to_utf8_buffer())
	var id = io.import_asset(io.folder.path_join("fixture.obj"), p)
	p.installation = Mapping.make("Custom object")
	var o = p.installation.outputs[0]
	o.size = [160, 120]
	o.position = [0, 0, 3]
	o.aim = [0, 0, 0]
	o.throw = 0.8
	var surf = p.installation.surfaces[0]
	surf.asset = id
	var s = Session.new(p)
	var vp = SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var stage = Stage.new()
	vp.add_child(stage)
	stage.configure(s, io.folder, "@live")
	var out = SubViewport.new()
	out.size = Vector2i(160, 120)
	out.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(out)
	var feed = Feed.new()
	out.add_child(feed)
	feed.size = Vector2(160, 120)
	feed.configure(vp, stage, o, surf, s, io.folder)
	for _i in 6:
		await RenderingServer.frame_post_draw
	var pixels = out.get_texture().get_image()
	var center = pixels.get_pixel(80, 60)
	var edge = pixels.get_pixel(2, 2)
	var success = feed.mesh_camera != null and center.r > 0.6 and center.g < 0.4 and edge.r < 0.2
	print(
		"PASS" if success else "FAIL",
		" UV-mapped OBJ with perspective projector, dark background and sampled content; colours ",
		center,
		" ",
		edge
	)
	quit(0 if success else 1)

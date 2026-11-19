extends SceneTree
const Feed = preload("res://core/feed.gd")
const Model = preload("res://core/project.gd")
const Session = preload("res://core/session.gd")
const Store = preload("res://core/storage.gd")
const Paths = preload("res://core/paths.gd")
var errors = 0


func _initialize():
	call_deferred("run")


func run():
	var dir = Paths.option("--fixture")
	var jobs = Store.json_at(dir.path_join("cases.json"))
	if not jobs is Array:
		quit(1)
		return
	for job in jobs:
		var p = Model.fresh()
		p.assets = {"mask": {"path": "assets/mask.png"}}
		var session = Session.new(p)
		session.vars.longitude = job.get("longitude", 0)
		var source = SubViewport.new()
		var im = Image.load_from_file(dir.path_join(job.source))
		source.size = im.get_size()
		source.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(source)
		var tex = TextureRect.new()
		tex.texture = ImageTexture.create_from_image(im)
		source.add_child(tex)
		tex.size = Vector2(source.size)
		var dest = SubViewport.new()
		dest.size = Vector2i(job.output.size[0], job.output.size[1])
		dest.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(dest)
		var feed = Feed.new()
		dest.add_child(feed)
		feed.size = Vector2(dest.size)
		feed.configure(source, tex, job.output, job.surface, session, dir)
		for _j in 4:
			await RenderingServer.frame_post_draw
		var out_img = dest.get_texture().get_image()
		if out_img == null or out_img.save_png(dir.path_join(job.name + ".png")) != OK:
			errors += 1
		dest.queue_free()
		source.queue_free()
		await process_frame
	print("Rendered ", jobs.size(), " independent calibration fixtures, failures ", errors)
	quit(1 if errors else 0)

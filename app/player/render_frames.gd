extends SceneTree
const Paths=preload("res://core/paths.gd")
const Store=preload("res://core/storage.gd")
const Model=preload("res://core/project.gd")
const Session=preload("res://core/session.gd")
const Stage=preload("res://core/stage.gd")
const Feed=preload("res://core/feed.gd")

func _initialize():call_deferred("render")

func render():
	if DisplayServer.get_name()=="headless":
		printerr("Image export requires a graphics display.")
		quit(2)
		return
	var io=Store.new()
	var project=io.open(Paths.option("--project"))
	if project.is_empty():
		printerr(io.error);quit(2);return
	var output=Model.lookup(project.installation.outputs,Paths.option("--output"))
	var total=int(Paths.option("--frames","1"))
	var fps=float(Paths.option("--fps","24"))
	var dest=Paths.option("--prefix")
	if output.is_empty() or not dest or total<1 or fps<1 or fps>120:
		printerr("Invalid output or export range.");quit(2);return
	var s=Session.new(project)
	var source=SubViewport.new()
	source.size=Vector2i(project.canvas[0],project.canvas[1])
	source.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(source)
	var stage=Stage.new()
	source.add_child(stage)
	stage.configure(s,io.folder,output.get("scene","@live"),false,true)
	var rendered=SubViewport.new()
	rendered.size=Vector2i(output.size[0],output.size[1])
	rendered.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(rendered)
	var feed=Feed.new()
	rendered.add_child(feed)
	feed.size=Vector2(rendered.size)
	feed.configure(source,stage,output,Model.lookup(project.installation.surfaces,output.surface),s,io.folder)
	for j in 2:await RenderingServer.frame_post_draw
	for i in total:
		await RenderingServer.frame_post_draw
		var img=rendered.get_texture().get_image()
		if not img or img.save_png(dest+"%06d.png"%i)!=OK:
			printerr("Could not save frame ",i);quit(2);return
		s.tick(1.0/fps)
	print("Rendered %d frames at %d × %d."%[total,rendered.size.x,rendered.size.y])
	quit()

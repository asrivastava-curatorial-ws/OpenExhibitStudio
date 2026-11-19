extends SceneTree
const Model=preload("res://core/project.gd")
const Store=preload("res://core/storage.gd")
const Mapping=preload("res://core/mapping.gd")
const Session=preload("res://core/session.gd")
const Paths=preload("res://core/paths.gd")
const Studio=preload("res://studio/studio.tscn")
const Player=preload("res://player/player.tscn")
var checks=0
var fails=0
var root_path=""
func check(ok:bool,name_:String):
	checks+=1
	if not ok:fails+=1
	print(("PASS " if ok else "FAIL ")+name_)
func _initialize():call_deferred("suite")
func frames(n=2):
	for _i in n:await process_frame
func suite():
	root_path=Store.absolute("user://checks/"+Model.uid("integration"))
	var ex=Paths.examples()
	var count=0
	for slug in DirAccess.get_directories_at(ex):
		var store=Store.new()
		var project=store.open(ex.path_join(slug+"/project.oes.json"))
		check(not project.is_empty(),"checksum and schema · "+slug)
		if project.is_empty():continue
		var target=root_path.path_join(slug+"/project.oes.json")
		check(store.save(project,target),"relocate assets · "+slug)
		check(store.pack(project,target+".oex") and store.open(target+".oex")==project,"portable round trip · "+slug)
		count+=1
	check(count==14,"all fourteen exhibit examples present")
	var editor=Studio.instantiate()
	root.add_child(editor)
	await frames()
	editor.pick("title")
	var o=editor.obj()
	editor.mutate("Set title",func():o.text="A different title")
	check(editor.canvas.stage.nodes.title.text=="A different title","edited canvas text updates shared renderer")
	editor.undo()
	check(editor.canvas.stage.nodes.title.text=="A year around the Sun","undo restores the exact previous object")
	editor.redo()
	check(editor.obj().text=="A different title","redo returns the edited object")
	editor.undo()
	editor.set_space("Test")
	editor.canvas.stage.nodes.mars.pressed.emit()
	check(editor.canvas.stage.nodes.planet.text=="Mars" and editor.session.vars.days>686,"visitor button updates another native control")
	editor.set_space("Canvas")
	for name_ in editor.SPACES:
		editor.set_space(name_)
		await frames(1)
		check(editor.center.get_child_count()>0,"workspace opens · "+name_)
	editor.set_space("Canvas")
	editor.selected=""
	editor.add_object("panel")
	var oid=editor.selected
	editor.canvas.transformed.emit(oid,[96,112,312,144])
	check(editor.obj().rect==[96,112,312,144],"canvas transform commits to project")
	editor.undo()
	check(editor.obj().rect==[80,80,340,96],"undo canvas transform")
	editor.duplicate_object()
	check(editor.selected!=oid,"duplicate obtains independent ID")
	editor.delete_object()
	var spath=root_path+"/edited/project.oes.json"
	editor.save_to(spath)
	check(not editor.dirty and Store.new().open(spath).title==editor.p.title,"authoring save entry point")
	var old=editor.p.title
	var a=editor.p.duplicate(true)
	a.title="Changed externally"
	Store.write_json(spath,a)
	check(not editor.io.save(editor.p,spath) and "changed" in editor.io.error,"concurrent modification detected")
	editor.p.title=old
	# Point correspondences, angular mapping and physical heights.
	for name_ in Mapping.PRESETS:
		var p=Model.fresh()
		p.installation=Mapping.make(name_)
		check(Model.validate(p)=="","valid preset · "+name_)
	var cal=Mapping.make("Single projector")
	var o0=cal.outputs[0]
	o0.warp=[[0.12,0.04],[0.91,0.1],[0.81,0.92],[0.04,0.82]]
	var corners=[Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]
	var valid=true
	for j in 4:valid=valid and Mapping.content_uv(Mapping.v2(o0.warp[j]),o0,cal.surfaces[0]).distance_to(corners[j])<0.0001
	check(valid,"corner pin is a perspective homography")
	var mesh=Mapping.lattice_default()
	mesh[4]=[.42,.62]
	check(Mapping.mesh_uv(Vector2(.42,.62),mesh).distance_to(Vector2(.5,.5))<.0001,"mesh warp recovers displaced central control point")
	var p0=Model.fresh()
	p0.installation=cal
	o0.gamma=1.3;o0.blend=[0.12,0.04,0.0,0.0]
	var io=Store.new();io.folder=root_path
	check(io.save(p0,root_path+"/warp.json") and io.open(root_path+"/warp.json").installation.outputs[0].warp==JSON.parse_string(JSON.stringify(o0.warp)),"warp, blend and geometry persist")
	var cy=Mapping.make("360° ring",4,3,2.5,360)
	var srf=cy.surfaces[0]
	var centers=[]
	for op in cy.outputs:centers.append(Mapping.content_uv(Vector2(.5,.5),op,srf))
	check(absf(centers[0].x-.125)<.001 and absf(centers[3].x-.875)<.001,"360-degree cylinder seam and cardinal sectors")
	var uv=Mapping.content_uv(Vector2(.5,.25),cy.outputs[0],srf)
	var taller=srf.duplicate();taller.height*=2
	var uv2=Mapping.content_uv(Vector2(.5,.25),cy.outputs[0],taller)
	check(absf(absf(uv.y-.5)/2-absf(uv2.y-.5))<.001,"fixed cylinder height controls vertical mapping")
	var sphere=Mapping.make("Earth sphere")
	var pole=false
	for outlet in sphere.outputs:pole=pole or Mapping.sees(Vector3(0,2,0),outlet,sphere.surfaces[0])
	check(not pole,"equatorial projector layout flags uncovered north pole")
	var sr=Mapping.content_uv(Vector2(.5,.5),sphere.outputs[0],sphere.surfaces[0])
	var rot=Mapping.content_uv(Vector2(.5,.5),sphere.outputs[0],sphere.surfaces[0],90)
	check(absf(sr.y-.5)<.001 and absf(fposmod(rot.x-sr.x,1)-.25)<.001,"equirectangular sphere rotation")
	var current_output=editor.p.installation.outputs[0]
	var original_warp=current_output.warp.duplicate(true)
	var measure={"format":"oes-measured-warp","version":1,"status":"capture-validated","method":"test-fixture","size":current_output.size,"warp":[[.1,.1],[.9,.08],[.9,.9],[.08,.9]],"limits":{"p95_px":1.5,"max_px":4.5},"spatial_holdout":{"samples":500,"p95_px":.42,"max_px":.82},"independent_dots":{"samples":20,"p95_px":.29,"max_px":.44}}
	var report_path=root_path+"/measurement.json"
	Store.write_json(report_path,measure)
	editor.work.contest.import_warp(current_output,editor.p.installation.surfaces[0],report_path)
	check(editor.p.installation.outputs[0].has("capture_check") and editor.p.installation.outputs[0].warp!=original_warp,"measured camera report applies to actual Studio output")
	editor.undo()
	check(editor.p.installation.outputs[0].warp==original_warp and not editor.p.installation.outputs[0].has("capture_check"),"undo restores prior calibration")
	measure.size=[101,123]
	Store.write_json(report_path,measure)
	editor.work.contest.import_warp(editor.p.installation.outputs[0],editor.p.installation.surfaces[0],report_path)
	check(editor.p.installation.outputs[0].warp==original_warp,"wrong-resolution camera report cannot overwrite the output")
	# A single input reaches both scene trees and multiple disarmed/armed requests.
	var mixed=ex.path_join("11-mixed/project.oes.json")
	var runtime=Player.instantiate()
	# Explicit loading bypasses the startup picker without an extra set of windows.
	runtime.session=Session.new(Model.fresh())
	root.add_child(runtime)
	runtime.load_path(mixed)
	await frames(3)
	check(runtime.feeds.size()==2 and runtime.get_window().size==Vector2i(1280,720) and runtime.windows[0].size==Vector2i(1024,768),"two native windows with independent requested sizes")
	runtime.session.sensor("dial",70)
	check(runtime.session.virtual_outputs.is_empty(),"fresh runtime starts with outputs disarmed")
	runtime.session.virtual_armed=true
	runtime.session.sensor("dial",72)
	check(runtime.session.virtual_outputs.get("lamp")==1 and runtime.session.virtual_outputs.get("light")==1,"one physical-channel event requests two output devices")
	check(runtime.sources["@live"][1].nodes.layer.text=="Sandstone" and runtime.sources.projection[1].nodes.layer.text=="Sandstone","one input updates kiosk and projector scene")
	var projected=runtime.feeds[0]
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var img=runtime.sources["@live"][0].get_texture().get_image()
		var colors={}
		if img and not img.is_empty():
			for y in range(0,img.get_height(),13):
				for x in range(0,img.get_width(),17):colors[img.get_pixel(x,y).to_html()]=true
		check(colors.size()>8,"OpenGL renders distinct exhibit colours in the scene texture")
		var rendered=runtime.windows[0].get_texture().get_image()
		var pigments={}
		if rendered:
			for y in range(0,rendered.get_height(),17):
				for x in range(0,rendered.get_width(),23):pigments[rendered.get_pixel(x,y).to_html()]=true
		check(pigments.size()>8,"calibrated second window renders live projector feed")
	runtime.session.reset()
	check(not runtime.session.virtual_armed and runtime.session.vars.dial==0,"visitor reset clears outputs and state")
	runtime.queue_free()
	await frames(3)
	var interactive=Player.instantiate()
	interactive.session=Session.new(Model.fresh())
	root.add_child(interactive)
	interactive.load_path(ex.path_join("01-solar/project.oes.json"))
	await frames(3)
	var touch=interactive.feeds[0]
	var pt=Vector2(523,656)/Vector2(1280,720)*touch.size
	var move=InputEventMouseMotion.new()
	move.position=pt
	touch._gui_input(move)
	for pressed in [true,false]:
		var e=InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.position=pt
		e.pressed=pressed
		touch._gui_input(e)
	check(interactive.session.vars.planet=="Mars","standalone feed maps pointer input to native scene button")
	interactive.queue_free()
	await frames(3)
	var timed=Store.new().open(ex.path_join("13-shows/project.oes.json"))
	var show=Session.new(timed)
	show.tick(6.01)
	check(show.scene=="standing","timeline changes film at six seconds")
	show.virtual_armed=true;show.seek(1)
	check(show.scene=="main" and not show.virtual_armed,"seeking restores presentation and disarms outputs")
	var drawn=Session.new(Store.new().open(ex.path_join("12-postcards/project.oes.json")))
	drawn.vars.ink=[[.2,.3]]
	drawn.dispatch("tap.post")
	drawn.vars.ink.append([.3,.4])
	check(drawn.vars.posted.size()==1,"submitted drawing is a snapshot")
	drawn.dispatch("tap.clear")
	check(drawn.vars.ink.is_empty() and drawn.vars.posted.size()==1,"clearing kiosk preserves wall submission")
	var book=Session.new(Store.new().open(ex.path_join("07-physical-book/project.oes.json")))
	book.sensor("page",3)
	check(book.scene=="pressure","page sensor selects a physical book spread")
	book.dispatch("book.prev")
	check(book.scene=="layers","manual fallback turns one book page")
	var broken=Model.fresh()
	broken.assets={"unsafe":{"path":"assets/../../outside","sha256":"0".repeat(64)}}
	check(Model.validate(broken)!="","traversal path rejected")
	var bounded=Model.fresh()
	bounded.rules=[{"id":"guard","event":"tick","actions":[{"op":"add","target":"v","value":1}]}]
	var sim=Session.new(bounded)
	for j in 30000:sim.sensor("tick",j)
	check(sim.trace.size()<=160 and sim.history.tick.size()==160,"30,000 sensor events keep bounded traces and samples")
	editor.queue_free()
	await frames(4)
	print("RESULT %d integration checks, %d failures."%[checks,fails])
	quit(1 if fails else 0)

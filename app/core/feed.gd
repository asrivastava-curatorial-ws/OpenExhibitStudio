extends TextureRect
const Mapping=preload("res://core/mapping.gd")
const StyleKit=preload("res://core/skin.gd")
const ModelView=preload("res://core/model_view.gd")
const SHADER=preload("res://core/feed.gdshader")
var source:SubViewport
var output:Dictionary
var surface:Dictionary
var session
var stage
var folder=""
var pattern=0
var mesh_camera:Camera3D
var mesh_viewport:SubViewport

func configure(vp: SubViewport,sc,o:Dictionary,s:Dictionary,engine,dir=""):
	source=vp
	stage=sc
	session=engine
	output=o
	surface=s
	folder=dir
	texture=vp.get_texture()
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_SCALE
	focus_mode=Control.FOCUS_ALL
	material=ShaderMaterial.new()
	material.shader=SHADER
	if s.kind=="mesh" and s.has("asset"):
		build_mesh_projection()
	calibrate()
	session.updated.connect(sync_vars)
	sync_vars()

func build_mesh_projection():
	var asset_id=surface.asset
	if not session.project.assets.has(asset_id):return
	var loader=ModelView.new()
	add_child(loader)
	loader.hide()
	loader.setup()
	var err=loader.load_model(folder.path_join(session.project.assets[asset_id].path))
	if err:
		session.log_line(err)
		loader.queue_free()
		return
	mesh_viewport=loader.viewport3
	mesh_viewport.reparent(self)
	mesh_viewport.size=Vector2i(output.size[0],output.size[1])
	mesh_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	mesh_camera=loader.camera
	mesh_camera.environment.background_color=Color.BLACK
	var mat=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture=source.get_texture()
	var model=loader.imported
	model.position=Mapping.v3(surface.get("position",[0,0,0]))
	model.rotation_degrees=Mapping.v3(surface.get("rotation",[0,0,0]))
	model.scale=Mapping.v3(surface.get("scale",[1,1,1]))
	var meshes=model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:meshes.append(model)
	for n in meshes:n.material_override=mat
	texture=mesh_viewport.get_texture()
	loader.queue_free()

func calibrate():
	var m=Mapping.inverse_quad(output.warp)
	if m.is_empty(): return
	var b=Mapping.basis_for(output,surface.kind)
	if mesh_camera:
		mesh_camera.position=b[0]
		mesh_camera.look_at(b[0]+b[1],b[3])
		var near_clip=0.05
		var frustum_width=near_clip/maxf(0.02,output.get("throw",1))
		var frustum_height=frustum_width*float(output.size[1])/output.size[0]
		var shift=Mapping.v2(output.get("shift",[0,0]))
		mesh_camera.keep_aspect=Camera3D.KEEP_HEIGHT
		mesh_camera.set_frustum(frustum_height,Vector2(shift.x*frustum_width,-shift.y*frustum_height),near_clip,1000.0)
	var mask=null
	if output.has("mask") and session.project.assets.has(output.mask): mask=StyleKit.texture(folder.path_join(session.project.assets[output.mask].path))
	var local=Mapping.optics_in_surface(output,surface)
	var params={"cubemap_cross":surface.get("source_layout","equirectangular")=="cubemap_cross","row0":m[0],"row1":m[1],"row2":m[2],"geometry":["plane","cylinder","sphere","dome"].find(surface.kind),"view_rect":Mapping.v4(output.view),"edges":Mapping.v4(output.blend),"blend_power":output.get("blend_power",1),"gamma_value":output.get("gamma",1),"black_level":output.get("black",0),"gain":Mapping.v3(output.get("gain",[1,1,1])),"eye":local[0],"forward_dir":local[1],"right_dir":local[2],"up_dir":local[3],"radius":surface.get("radius",2),"height_m":surface.get("height",2),"arc_rad":deg_to_rad(surface.get("arc",360)),"throw_ratio":output.get("throw",1),"lens_shift":Mapping.v2(output.get("shift",[0,0])),"aspect":float(output.size[0])/output.size[1],"pattern":pattern,"masked":mask!=null}
	params.mesh_enabled=output.has("mesh")
	var points=PackedVector2Array()
	for point in output.get("mesh",Mapping.lattice_default()):points.append(Mapping.v2(point))
	params.mesh_nodes=points
	if mask: params.mask_map=mask
	for k in params: material.set_shader_parameter(k,params[k])

func sync_vars(): material.set_shader_parameter("longitude",float(session.vars.get("longitude",0)))

func _gui_input(ev):
	if not source or mesh_camera: return
	var send=ev.duplicate()
	if ev is InputEventMouse or ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		var uv=Mapping.content_uv(ev.position/size,output,surface,float(session.vars.get("longitude",0)))
		if uv.x<0: return
		send.position=uv*Vector2(source.size)
		if ev is InputEventMouse:
			send.global_position=send.position
			if ev is InputEventMouseButton and ev.pressed: grab_focus()
	if ev is InputEventMouse or ev is InputEventScreenTouch or ev is InputEventScreenDrag or ev is InputEventKey:
		source.push_input(send,true)
		session.idle=0
		accept_event()

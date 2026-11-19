extends SubViewportContainer
var viewport3:SubViewport
var world:Node3D
var camera:Camera3D
var target=Vector3.ZERO
var yaw=0.55
var pitch=0.35
var distance=7.0
var dragging=false
var imported:Node3D

func setup():
	stretch=true
	viewport3=SubViewport.new()
	viewport3.own_world_3d=true
	viewport3.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport3)
	world=Node3D.new()
	viewport3.add_child(world)
	camera=Camera3D.new()
	world.add_child(camera)
	var env=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("#111b28")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("#cbdceb")
	env.ambient_light_energy=0.9
	camera.environment=env
	var light=DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees=Vector3(-55,-35,0)
	update_camera()

func update_camera():
	camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target)

func _gui_input(ev):
	if ev is InputEventMouseButton:
		if ev.button_index==MOUSE_BUTTON_LEFT: dragging=ev.pressed
		if ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance=clampf(distance*(0.88 if ev.button_index==MOUSE_BUTTON_WHEEL_UP else 1.13),0.4,100)
			update_camera()
	if ev is InputEventMouseMotion and dragging:
		yaw-=ev.relative.x*0.009
		pitch=clampf(pitch+ev.relative.y*0.009,-1.45,1.45)
		update_camera()

func shape(mesh: Mesh, pos: Vector3, color: Color, wire=false) -> MeshInstance3D:
	var n=MeshInstance3D.new()
	n.mesh=mesh
	n.position=pos
	var mat=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	if wire: mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	n.material_override=mat
	world.add_child(n)
	return n

func line3(a: Vector3,b: Vector3,color: Color):
	var m=ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	m.surface_add_vertex(a)
	m.surface_add_vertex(b)
	m.surface_end()
	shape(m,Vector3.ZERO,color)

func installation(i: Dictionary):
	var grid=Color("#324456")
	for j in range(-5,6):
		line3(Vector3(j,-1.6,-5),Vector3(j,-1.6,5),grid)
		line3(Vector3(-5,-1.6,j),Vector3(5,-1.6,j),grid)
	for s in i.surfaces:
		var at=s.get("position",[0,0,0])
		var pos=Vector3(at[0],at[1],at[2])
		var mat=Color("#50b9c5")
		var r=float(s.get("radius",2))
		var h=float(s.get("height",2))
		match s.kind:
			"sphere","dome":
				var m=SphereMesh.new()
				m.radius=r
				m.height=2*r
				m.is_hemisphere=s.kind=="dome"
				shape(m,pos,Color(mat,0.5),true)
			"cylinder":
				var arc=deg_to_rad(s.get("arc",360))
				var mesh=ImmediateMesh.new()
				mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
				for c in 97:
					var a=-arc/2+arc*c/96.0
					for y in [-h/2,h/2]: mesh.surface_add_vertex(Vector3(sin(a)*r,y,cos(a)*r))
				mesh.surface_end()
				shape(mesh,pos,Color(mat,0.45),true)
			_:
				var m=BoxMesh.new()
				m.size=Vector3(s.get("width",3),h,0.04)
				var plane=shape(m,pos,Color(mat,0.55),true)
				var rot=s.get("rotation",[0,0,0])
				plane.rotation_degrees=Vector3(rot[0],rot[1],rot[2])
	for o in i.outputs:
		var loc=o.get("position",[0,0,3])
		var pos=Vector3(loc[0],loc[1],loc[2])
		var m=BoxMesh.new()
		m.size=Vector3(0.22,0.16,0.27)
		shape(m,pos,Color("#ffc57c"))
		var aim=o.get("aim",[0,0,0])
		line3(pos,Vector3(aim[0],aim[1],aim[2]),Color("#efb16e"))

func load_model(path: String) -> String:
	var ext=path.get_extension().to_lower()
	var node
	if ext in ["glb","gltf"]:
		var bytes=FileAccess.get_file_as_bytes(path)
		if bytes.size()>67108864: return "Model exceeds 64 MiB."
		var raw=bytes
		if ext=="glb":
			if bytes.size()<20 or bytes.decode_u32(0)!=0x46546c67 or bytes.decode_u32(12)>bytes.size()-20: return "Invalid GLB."
			raw=bytes.slice(20,20+bytes.decode_u32(12))
		var doc=JSON.parse_string(raw.get_string_from_utf8())
		if not doc is Dictionary: return "Invalid glTF JSON."
		for key in ["buffers","images"]:
			for desc in doc.get(key,[]):
				if desc.has("uri") and not str(desc.uri).begins_with("data:"): return "Embed all model buffers and textures before importing."
		var loader=GLTFDocument.new()
		var state=GLTFState.new()
		if loader.append_from_buffer(bytes,"",state)!=OK: return "Model import failed."
		node=loader.generate_scene(state)
	elif ext=="obj":
		var f=FileAccess.open(path,FileAccess.READ)
		if not f or f.get_length()>33554432: return "OBJ is missing or oversized."
		var verts=PackedVector3Array()
		var uvs=PackedVector2Array()
		var builder=SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count=0
		while not f.eof_reached():
			var line=f.get_line().strip_edges().replace("\t"," ").split(" ",false)
			if line.size()>=4 and line[0]=="v": verts.append(Vector3(float(line[1]),float(line[2]),float(line[3])))
			elif line.size()>=3 and line[0]=="vt":uvs.append(Vector2(float(line[1]),1.0-float(line[2])))
			elif line.size()>=4 and line[0]=="f":
				var face=[]
				for j in range(1,line.size()):
					var n=int(line[j].get_slice("/",0))
					n=verts.size()+n if n<0 else n-1
					if n<0 or n>=verts.size(): return "Invalid OBJ face index."
					var uv=Vector2.ZERO
					var ref_=line[j].split("/",true)
					if ref_.size()>1 and ref_[1]!="":
						var ti=int(ref_[1])
						ti=uvs.size()+ti if ti<0 else ti-1
						if ti<0 or ti>=uvs.size():return "Invalid OBJ texture index."
						uv=uvs[ti]
					face.append([n,uv])
				for j in range(1,face.size()-1):
					for k in [0,j+1,j]:
						builder.set_uv(face[k][1])
						builder.add_vertex(verts[face[k][0]])
					count+=3
					if count>1500000: return "OBJ triangle limit reached."
		if count==0: return "OBJ contains no faces."
		builder.generate_normals()
		node=MeshInstance3D.new()
		node.mesh=builder.commit()
	else: return "Use GLB, embedded glTF or OBJ."
	if not node: return "Could not instantiate the model."
	world.add_child(node)
	imported=node
	var bounds=AABB()
	var first=true
	var meshes=node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D: meshes.append(node)
	for n in meshes:
		if n.mesh:
			var a=n.global_transform*n.get_aabb()
			bounds=a if first else bounds.merge(a)
			first=false
	if not first:
		target=bounds.get_center()
		distance=maxf(bounds.size.length()*1.2,0.4)
		update_camera()
	return ""

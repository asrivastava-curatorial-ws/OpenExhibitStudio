extends RefCounted

const Model=preload("res://core/project.gd")
const MAX_FILE=268435456
const MAX_TOTAL=536870912
var error=""
var folder=""
var path=""
var revision=""
var packaged=false

static func absolute(p: String) -> String:
	return ProjectSettings.globalize_path(p).replace("\\","/").simplify_path()

static func json_at(p: String):
	var file=FileAccess.open(p,FileAccess.READ)
	if not file or file.get_length()>16777216: return null
	var parser=JSON.new()
	if parser.parse(file.get_as_text())!=OK: return null
	return parser.data

static func write_bytes(p: String, bytes: PackedByteArray) -> String:
	var target=absolute(p)
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir())!=OK: return "Cannot create the destination folder."
	var tmp=target+".writing-"+Model.uid("tmp")
	var f=FileAccess.open(tmp,FileAccess.WRITE)
	if not f: return "Cannot write "+target
	f.store_buffer(bytes)
	f.flush()
	var result=f.get_error()
	f.close()
	if result!=OK:
		DirAccess.remove_absolute(tmp)
		return "Writing failed: "+target
	return commit(tmp,target)

static func commit(tmp: String, target: String) -> String:
	var bak=target+".bak"
	if FileAccess.file_exists(target):
		if FileAccess.file_exists(bak) and DirAccess.remove_absolute(bak)!=OK: return "Cannot rotate backup."
		if DirAccess.rename_absolute(target,bak)!=OK: return "Cannot back up existing file."
	if DirAccess.rename_absolute(tmp,target)!=OK:
		if FileAccess.file_exists(bak): DirAccess.rename_absolute(bak,target)
		return "Cannot finish saving "+target
	return ""

static func write_json(p: String, data) -> String:
	return write_bytes(p,(JSON.stringify(data,"\t",false)+"\n").to_utf8_buffer())

func open(p: String) -> Dictionary:
	error=""
	var target=absolute(p)
	if not FileAccess.file_exists(target) and FileAccess.file_exists(target+".bak"):
		if DirAccess.copy_absolute(target+".bak",target)!=OK:
			error="An interrupted save left a backup at "+target+".bak"
			return {}
	var packed=target.get_extension().to_lower()=="oex"
	if packed:
		target=unpack(target)
		if error: return {}
	var value=json_at(target)
	error=Model.validate(value)
	if error: return {}
	for a in value.assets.values():
		var asset_path=target.get_base_dir().path_join(a.path)
		if not FileAccess.file_exists(asset_path) or FileAccess.get_sha256(asset_path)!=a.sha256:
			error="Missing or changed asset: "+a.path
			return {}
	path=target
	folder=path.get_base_dir()
	revision=FileAccess.get_sha256(path)
	packaged=packed
	return value

func save(p: Dictionary, dest: String) -> bool:
	error=Model.validate(p)
	if error: return false
	var target=absolute(dest)
	if target==path and (packaged or (FileAccess.file_exists(path) and FileAccess.get_sha256(path)!=revision)):
		error="This copy changed on disk or was packaged. Use Save As to create an editable copy."
		return false
	for a in p.assets.values():
		var src=folder.path_join(a.path)
		var dst=target.get_base_dir().path_join(a.path)
		if not FileAccess.file_exists(src) or FileAccess.get_sha256(src)!=a.sha256:
			error="Missing or changed asset: "+a.path
			return false
		if src!=dst:
			if FileAccess.file_exists(dst):
				if FileAccess.get_sha256(dst)!=a.sha256:
					error="Conflicting asset at destination: "+a.path
					return false
			else:
				DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
				if DirAccess.copy_absolute(src,dst)!=OK:
					error="Cannot copy "+a.path
					return false
	error=write_json(target,p)
	if error: return false
	folder=target.get_base_dir()
	path=target
	packaged=false
	revision=FileAccess.get_sha256(path)
	return true

func import_asset(src: String, p: Dictionary) -> String:
	error=""
	if not FileAccess.file_exists(src) or folder=="":
		error="Choose an existing asset and a working project folder."
		return ""
	var digest=FileAccess.get_sha256(src)
	for id in p.assets:
		if p.assets[id].sha256==digest: return id
	var rel="assets/"+digest.left(16)+"-"+src.get_file().validate_filename()
	if not Model.safe_path(rel):
		error="Please shorten or rename the source file."
		return ""
	DirAccess.make_dir_recursive_absolute(folder.path_join("assets"))
	if DirAccess.copy_absolute(src,folder.path_join(rel))!=OK:
		error="Cannot copy the asset."
		return ""
	var id="a_"+digest.left(16)
	p.assets[id]={"path":rel,"sha256":digest}
	return id

func pack(p: Dictionary, dest: String) -> bool:
	error=Model.validate(p)
	if error: return false
	var target=absolute(dest)
	var tmp=target+".writing-"+Model.uid("zip")
	var archive=ZIPPacker.new()
	if archive.open(tmp)!=OK:
		error="Cannot create package."
		return false
	var files={"project.oes.json":(JSON.stringify(p,"\t",false)+"\n").to_utf8_buffer()}
	var manifest={}
	var total=0
	for a in p.assets.values():
		var src=folder.path_join(a.path)
		var f=FileAccess.open(src,FileAccess.READ)
		if not f or f.get_length()>MAX_FILE or FileAccess.get_sha256(src)!=a.sha256:
			error="Missing, oversized or changed asset: "+a.path
			break
		total+=f.get_length()
		if total>MAX_TOTAL:
			error="Package exceeds the 512 MiB unpacked limit."
			break
		files[a.path]=src
	for key in files:
		if error: break
		var bytes=FileAccess.get_file_as_bytes(files[key]) if files[key] is String else files[key]
		var hash=HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		manifest[key]=hash.finish().hex_encode()
		if archive.start_file(key)!=OK or archive.write_file(bytes)!=OK or archive.close_file()!=OK: error="Cannot write package member."
	if not error and (archive.start_file("manifest.json")!=OK or archive.write_file(JSON.stringify(manifest).to_utf8_buffer())!=OK or archive.close_file()!=OK): error="Cannot write checksums."
	if archive.close()!=OK: error="Cannot close package."
	if error:
		DirAccess.remove_absolute(tmp)
		return false
	error=commit(tmp,target)
	return error==""

# Bound allocations using the ZIP central directory before reading a member.
func zip_limits(src: String) -> bool:
	var f=FileAccess.open(src,FileAccess.READ)
	if not f or f.get_length()<22 or f.get_length()>MAX_TOTAL+16777216: return false
	f.seek(f.get_length()-22)
	if f.get_32()!=0x06054b50 or f.get_16()!=0 or f.get_16()!=0: return false
	var count=f.get_16()
	if count!=f.get_16() or count<2 or count>2048: return false
	var extent=f.get_32()
	var offset=f.get_32()
	if offset+extent!=f.get_length()-22: return false
	f.seek(offset)
	var total=0
	for j in count:
		var start=f.get_position()
		if f.get_32()!=0x02014b50: return false
		f.seek(start+24)
		var length=f.get_32()
		total+=length
		if length>MAX_FILE or total>MAX_TOTAL: return false
		var namesize=f.get_16()
		var extras=f.get_16()
		var comment=f.get_16()
		f.seek(start+46+namesize+extras+comment)
		if f.get_position()>offset+extent: return false
	return f.get_position()==offset+extent

func unpack(src: String) -> String:
	error="Invalid or oversized OpenExhibit package."
	if not zip_limits(src): return ""
	var reader=ZIPReader.new()
	if reader.open(src)!=OK: return ""
	var members=reader.get_files()
	if not "manifest.json" in members or not "project.oes.json" in members: return ""
	var manifest=JSON.parse_string(reader.read_file("manifest.json").get_string_from_utf8())
	if not manifest is Dictionary or manifest.size()!=members.size()-1: return ""
	var root=absolute("user://packages/"+FileAccess.get_sha256(src))
	var seen={}
	for member in members:
		if member=="manifest.json": continue
		if seen.has(member.to_lower()) or (member!="project.oes.json" and not Model.safe_path(member)) or not manifest.has(member): return ""
		seen[member.to_lower()]=true
		var bytes=reader.read_file(member)
		var hash=HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if hash.finish().hex_encode()!=manifest[member]: return ""
		var dst=root.path_join(member)
		if FileAccess.file_exists(dst) and FileAccess.get_sha256(dst)==manifest[member]: continue
		if write_bytes(dst,bytes)!="": return ""
	reader.close()
	error=""
	return root.path_join("project.oes.json")

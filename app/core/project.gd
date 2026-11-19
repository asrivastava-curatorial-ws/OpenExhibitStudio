extends RefCounted

const FORMAT = "openexhibit"
const KINDS = ["text","panel","button","image","video","audio","slider","gauge","plot","orbit","grid","drawing","entry","model","particles","fractal","contest"]
const OPS = ["set","add","toggle","goto","emit","output","play","pause","reset","mul","random","append","clear"]
const TESTS = ["always","==","!=",">",">=","<","<=","contains"]

static func uid(prefix: String) -> String:
	return prefix + "_" + Crypto.new().generate_random_bytes(5).hex_encode()

static func fresh() -> Dictionary:
	return {"format":FORMAT,"version":1,"title":"Untitled exhibit","canvas":[1280,720],"start":"main","assets":{},"scenes":[{"id":"main","name":"First scene","background":"#101d30","objects":[]}],"variables":{},"rules":[],"timelines":[],"devices":[],"installation":{"preset":"Kiosk","surfaces":[{"id":"surface_1","kind":"plane","width":3.2,"height":1.8,"radius":2.0,"arc":180.0}],"outputs":[{"id":"out_1","surface":"surface_1","scene":"@live","screen":0,"size":[1280,720],"view":[0,0,1,1],"warp":[[0,0],[1,0],[1,1],[0,1]],"blend":[0,0,0,0],"gamma":1.0,"gain":[1,1,1],"black":0}]},"settings":{"idle_seconds":0,"autoplay":""},"extensions":{}}

static func lookup(items: Array, id: String) -> Dictionary:
	for item in items:
		if item is Dictionary and item.get("id") == id:
			return item
	return {}

static func numeric(v) -> bool:
	return (v is float or v is int) and is_finite(float(v))

static func vector(v, n: int) -> bool:
	if not v is Array or v.size()!=n: return false
	for x in v:
		if not numeric(x): return false
	return true

static func identifier(v) -> bool:
	if not v is String or v.is_empty() or v.length()>96: return false
	for ch in v:
		if not ch.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func safe_path(p) -> bool:
	if not p is String or not p.begins_with("assets/") or p.length()>240 or ":" in p or "\\" in p: return false
	for part in p.split("/"):
		if part in ["",".",".."] or part.ends_with(".") or part.ends_with(" "): return false
		var stem=part.get_slice(".",0).to_upper()
		if stem in ["CON","PRN","AUX","NUL"] or (stem.length()==4 and (stem.begins_with("COM") or stem.begins_with("LPT")) and stem[3] in "123456789"): return false
		for c in part:
			if c.unicode_at(0)<32 or c in '<>"|?*': return false
	return true

static func entries(items, what: String) -> String:
	if not items is Array or items.size()>10000: return "Invalid "+what+" list."
	var seen={}
	for item in items:
		if not item is Dictionary or not identifier(item.get("id")): return "Invalid "+what+" identifier."
		if seen.has(item.id): return "Duplicate "+what+" ID: "+item.id
		seen[item.id]=true
	return ""

static func action_error(action, p: Dictionary) -> String:
	if not action is Dictionary or not action.get("op") in OPS: return "Unknown rule or cue action."
	var op=action.op
	if op=="goto" and lookup(p.scenes,str(action.get("target",""))).is_empty(): return "Unknown scene target."
	if op=="play" and lookup(p.timelines,str(action.get("target",""))).is_empty(): return "Unknown timeline target."
	if op in ["set","add","toggle","mul","random","append","clear","emit","output"] and str(action.get("target","")).strip_edges().is_empty(): return "An action needs a target."
	return ""

static func validate(p) -> String:
	if not p is Dictionary or p.get("format")!=FORMAT or p.get("version")!=1: return "Unsupported project format or version."
	if not p.get("title") is String or p.title.strip_edges().is_empty(): return "A project needs a title."
	if not vector(p.get("canvas"),2) or p.canvas.min()<32 or p.canvas.max()>8192: return "Canvas dimensions must be 32–8192 pixels."
	for key in ["assets","variables","installation","settings"]:
		if not p.get(key) is Dictionary: return "Missing "+key+" dictionary."
	for key in ["scenes","rules","timelines","devices"]:
		var issue=entries(p.get(key),key)
		if issue: return issue
	if lookup(p.scenes,str(p.get("start",""))).is_empty(): return "Start scene is missing."
	for id in p.assets:
		var a=p.assets[id]
		if not identifier(id) or not a is Dictionary or not safe_path(a.get("path")): return "Invalid asset path."
		var hash=str(a.get("sha256",""))
		if hash.length()!=64 or not hash.is_valid_hex_number(false): return "Invalid asset digest."
	if not numeric(p.settings.get("idle_seconds",0)) or p.settings.get("idle_seconds",0)<0:return "Invalid idle timeout."
	if p.scenes.size()>512 or (p.installation.get("outputs") is Array and p.installation.outputs.size()>32):return "Exhibit exceeds scene or output limits."
	for d in p.devices:
		var channels=d.get("channels",[])
		var issue_=entries(channels,"channel")
		if issue_:return issue_
		for c in channels:
			if not c.get("direction","input") in ["input","output"]:return "Invalid channel direction."
	for s in p.scenes:
		if not s.get("name") is String:return "A scene needs a name."
		var issue=entries(s.get("objects"),"object")
		if issue: return issue
		for o in s.objects:
			if not o.get("kind") in KINDS or not vector(o.get("rect"),4) or o.rect[2]<=0 or o.rect[3]<=0: return "Bad component: "+o.id
			for field in ["text","color","background","border","fill","bind","event","channel","name"]:
				if o.has(field) and not o[field] is String:return "Invalid component field "+field+"."
			for field in ["min","max","step","font","volume_db","radius"]:
				if o.has(field) and not numeric(o[field]):return "Invalid numeric component field."
			if o.has("asset") and not p.assets.has(o.asset): return "Missing asset for "+o.id
			if o.has("points") and not o.points is Array: return "Invalid shape points."
	for rule in p.rules:
		if not rule.get("event") is String or not rule.get("actions") is Array: return "Rule needs an event and actions."
		var cond=rule.get("if",{})
		if not cond is Dictionary or not cond.get("op","always") in TESTS: return "Invalid condition."
		for a in rule.actions:
			var issue=action_error(a,p)
			if issue: return issue
	for t in p.timelines:
		if not numeric(t.get("duration")) or t.duration<=0 or not t.get("cues",[]) is Array or not t.get("keys",[]) is Array: return "Invalid timeline."
		for cue in t.get("cues",[]):
			if not cue is Dictionary or not numeric(cue.get("at")) or cue.at<0 or cue.at>t.duration: return "Invalid cue time."
			var issue=action_error(cue.get("action"),p)
			if issue: return issue
		for k in t.get("keys",[]):
			if not k is Dictionary or not numeric(k.get("at")) or not numeric(k.get("value")) or not k.get("property") in ["x","y","opacity","rotation"]: return "Invalid animation key."
			var owner=lookup(p.scenes,str(k.get("scene","")))
			if owner.is_empty() or lookup(owner.objects,str(k.get("object",""))).is_empty(): return "Animation key targets a missing object."
	var i=p.installation
	for key in ["surfaces","outputs"]:
		var err=entries(i.get(key),key)
		if err or i[key].is_empty(): return "Invalid installation "+key+"."
	for s in i.surfaces:
		if not s.get("kind") in ["plane","cylinder","sphere","dome","mesh"]: return "Unknown surface geometry."
		if s.has("asset") and not p.assets.has(s.asset):return "Missing surface mesh asset."
		if not s.get("source_layout","equirectangular") in ["equirectangular","cubemap_cross"]:return "Unknown surface texture layout."
		if s.get("source_layout","")=="cubemap_cross" and not s.kind in ["sphere","dome"]:return "Cube-cross textures require a sphere or dome."
		for geom in ["position","rotation","scale"]:
			if s.has(geom) and not vector(s[geom],3):return "Invalid surface transform."
		for field in ["width","height","radius","arc"]:
			if not numeric(s.get(field,1)) or s.get(field,1)<=0: return "Invalid surface "+field+"."
	for out in i.outputs:
		if lookup(i.surfaces,str(out.get("surface",""))).is_empty(): return "Output surface is missing."
		if out.get("scene","@live")!="@live" and lookup(p.scenes,str(out.scene)).is_empty(): return "Output scene is missing."
		if not numeric(out.get("screen",0)) or out.get("screen",0)<0:return "Invalid screen index."
		if not vector(out.get("size"),2) or out.size.min()<32 or out.size.max()>8192: return "Invalid display dimensions."
		for key in ["position","aim","up"]:
			if out.has(key) and not vector(out[key],3):return "Invalid projector pose."
		if out.has("position") and out.has("aim") and Vector3(out.position[0],out.position[1],out.position[2]).distance_to(Vector3(out.aim[0],out.aim[1],out.aim[2]))<0.00001:return "The projector must aim away from its own position."
		if not vector(out.get("shift",[0,0]),2):return "Invalid lens shift."
		for name_ in ["throw","gamma","blend_power","black"]:
			if out.has(name_) and not numeric(out[name_]):return "Invalid projector correction."
		if not vector(out.get("view"),4) or not vector(out.get("blend"),4) or not vector(out.get("gain",[1,1,1]),3): return "Invalid output calibration."
		if out.get("throw",1)<=0 or out.get("gamma",1)<=0 or out.get("blend_power",1)<=0 or out.get("black",0)<0 or out.get("black",0)>1 or out.blend.min()<0 or out.blend.max()>1 or out.get("gain",[1,1,1]).min()<0 or out.view[2]<=0 or out.view[3]<=0:return "Calibration has an invalid gain, blend, optical or viewport range."
		if out.has("capture_check"):
			var capture=out.capture_check
			if not capture is Dictionary or not capture.get("independent_dots") is Dictionary or not numeric(capture.independent_dots.get("p95_px")):return "Invalid capture quality summary."
		if not out.get("warp") is Array or out.warp.size()!=4: return "Expected four warp corners."
		var orient=0
		for k in range(4):
			if not vector(out.warp[k],2): return "Invalid warp coordinate."
		for k in range(4):
			var a=Vector2(out.warp[k][0],out.warp[k][1])
			var b=Vector2(out.warp[(k+1)%4][0],out.warp[(k+1)%4][1])
			var c=Vector2(out.warp[(k+2)%4][0],out.warp[(k+2)%4][1])
			var cross=(b-a).cross(c-b)
			if absf(cross)<0.00001 or (orient!=0 and signf(cross)!=orient): return "Warp corners must form a convex quadrilateral."
			orient=int(signf(cross))
		if out.has("mesh"):
			if not out.mesh is Array or out.mesh.size()!=9:return "Expected a 3 × 3 warp mesh."
			for point in out.mesh:
				if not vector(point,2):return "Invalid mesh vertex."
			for j in [0,1,3,4]:
				for tri in [[j,j+1,j+4],[j,j+4,j+3]]:
					var a=Vector2(out.mesh[tri[0]][0],out.mesh[tri[0]][1])
					var b=Vector2(out.mesh[tri[1]][0],out.mesh[tri[1]][1])
					var c=Vector2(out.mesh[tri[2]][0],out.mesh[tri[2]][1])
					if (b-a).cross(c-a)<0.00001:return "Warp mesh triangles must keep their orientation."
		if out.has("mask") and not p.assets.has(out.mask): return "Unknown mask asset."
	return ""

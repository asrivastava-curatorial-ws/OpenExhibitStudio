extends RefCounted
const Model = preload("res://core/project.gd")
const PRESETS = [
	"Kiosk",
	"Multiple kiosks",
	"Interactive table",
	"Mixed displays",
	"Video wall",
	"Single projector",
	"Linear panorama",
	"Vertical panorama",
	"Cyclorama",
	"360° ring",
	"Earth sphere",
	"Fulldome",
	"Immersive room",
	"L-shaped room",
	"U-shaped room",
	"CAVE",
	"Custom object",
	"Relief map",
	"Digital book",
	"Projected book",
	"Physical book",
	"Touchscreen + projection",
	"Pepper’s Ghost",
	"Mixed installation"
]


static func make(preset: String, count = 0, radius = 2.0, height = 2.4, arc = 180.0) -> Dictionary:
	var n = 1
	match preset:
		"Multiple kiosks", "Mixed displays", "Vertical panorama", "Physical book", "Touchscreen + projection", "Mixed installation", "L-shaped room":
			n = 2
		"Linear panorama", "Cyclorama", "U-shaped room":
			n = 3
		"Earth sphere", "360° ring", "Pepper’s Ghost", "Video wall":
			n = 4
		"Immersive room", "CAVE":
			n = 6
	if count > 0:
		n = clampi(count, 1, 32)
	var result = {"preset": preset, "surfaces": [], "outputs": []}
	var shared = (
		preset
		in ["Linear panorama", "Vertical panorama", "Cyclorama", "360° ring", "Earth sphere", "Fulldome", "Video wall"]
	)
	var kind = "plane"
	if preset in ["Cyclorama", "360° ring"]:
		kind = "cylinder"
	if preset == "Earth sphere":
		kind = "sphere"
	if preset == "Fulldome":
		kind = "dome"
	if preset in ["Custom object", "Relief map"]:
		kind = "mesh"
	if preset == "360° ring":
		arc = 360.0
	var room = preset in ["Immersive room", "CAVE", "L-shaped room", "U-shaped room"]
	var names = ["Front", "Right", "Back", "Left", "Floor", "Ceiling"]
	var room_pos = [[0, 0, -2], [2, 0, 0], [0, 0, 2], [-2, 0, 0], [0, -2, 0], [0, 2, 0]]
	var room_rot = [[0, 0, 0], [0, 90, 0], [0, 180, 0], [0, -90, 0], [90, 0, 0], [-90, 0, 0]]
	for j in n:
		var s_id = "s1" if shared else "s" + str(j + 1)
		if j == 0 or not shared:
			var surf = {
				"id": s_id,
				"name": names[j % 6] if room else "Surface " + str(j + 1),
				"kind": kind,
				"width": float(n) * 3.2 if preset == "Linear panorama" else 3.2,
				"height": height,
				"radius": radius,
				"arc": arc,
				"position": room_pos[j % 6] if room else [0, 0, 0],
				"rotation": room_rot[j % 6] if room else [0, 0, 0]
			}
			if room:
				surf.merge({"width": 4.0, "height": 4.0}, true)
			result.surfaces.append(surf)
		var span = 360.0 if kind == "sphere" else arc
		var a = deg_to_rad(-span / 2.0 + span * (j + 0.5) / n)
		var pos = [(j - (n - 1) * 0.5) * 2.8, 0, 4]
		var aim = [pos[0], 0, 0]
		var throw_ratio = 1.1
		if kind == "sphere":
			pos = [sin(a) * radius * 2.4, 0, cos(a) * radius * 2.4]
			aim = [0, 0, 0]
			throw_ratio = 0.76
		if kind == "cylinder":
			pos = [0, 0, 0]
			aim = [sin(a) * radius, 0, cos(a) * radius]
			throw_ratio = minf(0.5 / tan(deg_to_rad(minf(150, span / n + 8)) / 2), radius / (height * 16.0 / 9.0))
		var view = [0.0, 0.0, 1.0, 1.0]
		var blend = [0.0, 0.0, 0.0, 0.0]
		if preset in ["Linear panorama", "Vertical panorama"]:
			var margin = 0.04 / n
			var lo = maxf(0, float(j) / n - margin)
			var hi = minf(1, float(j + 1) / n + margin)
			var b = 2 * margin / (hi - lo)
			if preset == "Linear panorama":
				view = [lo, 0, hi - lo, 1]
				blend = [b if j else 0.0, b if j < n - 1 else 0.0, 0.0, 0.0]
			else:
				view = [0, lo, 1, hi - lo]
				blend = [0.0, 0.0, b if j else 0.0, b if j < n - 1 else 0.0]
		if preset == "Physical book":
			view = [float(j) / n, 0, 1.0 / n, 1]
		if preset == "Video wall":
			var cols = ceili(sqrt(n))
			var rows = ceili(float(n) / cols)
			view = [float(j % cols) / cols, float(floori(float(j) / cols)) / rows, 1.0 / cols, 1.0 / rows]
		if room:
			# Cube cross atlas. Front, right, back and left occupy the middle row.
			var tiles = [[1, 1], [2, 1], [3, 1], [0, 1], [1, 2], [1, 0]]
			view = [tiles[j % 6][0] / 4.0, tiles[j % 6][1] / 3.0, 0.25, 1.0 / 3.0]
		result.outputs.append(
			{
				"id": "out_" + str(j + 1),
				"surface": s_id,
				"scene": "@live",
				"screen": j,
				"size": [1280, 720],
				"view": view,
				"warp": [[0, 0], [1, 0], [1, 1], [0, 1]],
				"blend": blend,
				"blend_power": 1.0,
				"gamma": 1.0,
				"black": 0.0,
				"gain": [1, 1, 1],
				"position": pos,
				"aim": aim,
				"throw": throw_ratio,
				"shift": [0, 0]
			}
		)
	return result


static func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func v2(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


static func v4(a: Array) -> Vector4:
	return Vector4(a[0], a[1], a[2], a[3])


# Solve the inverse projective transform from four destination corners to unit UV.
static func inverse_quad(warp: Array) -> Array:
	var mat = []
	for j in 4:
		var a = warp[j]
		var u = [0, 1, 1, 0][j]
		var v = [0, 0, 1, 1][j]
		mat.append([a[0], a[1], 1.0, 0.0, 0.0, 0.0, -u * a[0], -u * a[1], float(u)])
		mat.append([0.0, 0.0, 0.0, a[0], a[1], 1.0, -v * a[0], -v * a[1], float(v)])
	for k in 8:
		var best = k
		for j in range(k + 1, 8):
			if absf(mat[j][k]) > absf(mat[best][k]):
				best = j
		if absf(mat[best][k]) < 0.0000001:
			return []
		var row = mat[k]
		mat[k] = mat[best]
		mat[best] = row
		var divisor = mat[k][k]
		for j in range(k, 9):
			mat[k][j] /= divisor
		for i in 8:
			if i == k:
				continue
			var f = mat[i][k]
			for j in range(k, 9):
				mat[i][j] -= f * mat[k][j]
	return [
		Vector3(mat[0][8], mat[1][8], mat[2][8]),
		Vector3(mat[3][8], mat[4][8], mat[5][8]),
		Vector3(mat[6][8], mat[7][8], 1)
	]


static func basis_for(o: Dictionary, kind: String) -> Array:
	var eye = v3(o.get("position", [0, 0, 4]))
	var f = (v3(o.get("aim", [0, 0, 0])) - eye).normalized()
	if f.length() < 0.1:
		f = Vector3.FORWARD
	var preferred_up = v3(o.get("up", [0, 1, 0])).normalized()
	var r = f.cross(preferred_up).normalized()
	if r.length() < 0.1:
		r = f.cross(Vector3.RIGHT if absf(f.x) < 0.9 else Vector3.BACK).normalized()
	var up = r.cross(f).normalized()
	if kind == "cylinder":
		r = -r
	return [eye, f, r, up]


static func lattice_default() -> Array:
	var result = []
	for j in 9:
		result.append([(j % 3) * 0.5, floori(j / 3.0) * 0.5])
	return result


static func mesh_uv(pos: Vector2, grid: Array) -> Vector2:
	var uv = lattice_default()
	for y in 2:
		for x in 2:
			var i = y * 3 + x
			for tri in [[i, i + 1, i + 4], [i, i + 4, i + 3]]:
				var a = v2(grid[tri[0]])
				var ab = v2(grid[tri[1]]) - a
				var ac = v2(grid[tri[2]]) - a
				var den = ab.cross(ac)
				if absf(den) < 0.000001:
					continue
				var w = (pos - a).cross(ac) / den
				var z = ab.cross(pos - a) / den
				if w >= -0.000001 and z >= -0.000001 and w + z <= 1.000001:
					return v2(uv[tri[0]]) * (1 - w - z) + v2(uv[tri[1]]) * w + v2(uv[tri[2]]) * z
	return Vector2(-1, -1)


static func sees(point: Vector3, o: Dictionary, s: Dictionary) -> bool:
	var basis = basis_for(o, s.kind)
	var eye = basis[0]
	var local = point - v3(s.get("position", [0, 0, 0]))
	if s.kind == "sphere" and local.dot(eye - point) <= 0:
		return false
	var vec = point - eye
	var forward = vec.dot(basis[1])
	if forward <= 0:
		return false
	var shift = v2(o.get("shift", [0, 0]))
	var ratio = float(o.get("throw", 1)) / forward
	var uv = (
		Vector2(.5, .5)
		- shift
		+ Vector2(vec.dot(basis[2]) * ratio, -vec.dot(basis[3]) * ratio * float(o.size[0]) / o.size[1])
	)
	return uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1


static func local_frame(s: Dictionary) -> Basis:
	return Basis.from_euler(v3(s.get("rotation", [0, 0, 0])) * PI / 180.0)


static func optics_in_surface(o: Dictionary, s: Dictionary) -> Array:
	var basis = basis_for(o, s.kind)
	var inverse = local_frame(s).transposed()
	return [
		inverse * (basis[0] - v3(s.get("position", [0, 0, 0]))),
		inverse * basis[1],
		inverse * basis[2],
		inverse * basis[3]
	]


# Horizontal cube cross (left/front/right/back, zenith above front).
static func source_uv(c: Vector2, s: Dictionary) -> Vector2:
	if s.get("source_layout", "equirectangular") != "cubemap_cross":
		return c
	var lng = (c.x - .5) * TAU
	var lat = (.5 - c.y) * PI
	var d = Vector3(sin(lng) * cos(lat), sin(lat), cos(lng) * cos(lat))
	var a = d.abs()
	var tile = Vector2.ZERO
	var face = Vector2.ZERO
	if a.x >= a.y and a.x >= a.z:
		tile = Vector2(2 if d.x > 0 else 0, 1)
		face = Vector2(-d.z if d.x > 0 else d.z, -d.y) / a.x
	elif a.y >= a.z:
		tile = Vector2(1, 0 if d.y > 0 else 2)
		face = Vector2(d.x, d.z if d.y > 0 else -d.z) / a.y
	else:
		tile = Vector2(1 if d.z > 0 else 3, 1)
		face = Vector2(d.x if d.z > 0 else -d.x, -d.y) / a.z
	return (tile + face * .5 + Vector2(.5, .5)) / Vector2(4, 3)


static func content_uv(pos: Vector2, o: Dictionary, s: Dictionary, longitude = 0.0) -> Vector2:
	var m = inverse_quad(o.warp)
	if m.is_empty():
		return Vector2(-1, -1)
	var p = Vector3(pos.x, pos.y, 1)
	var den = m[2].dot(p)
	if absf(den) < 0.000001:
		return Vector2(-1, -1)
	var uv = Vector2(m[0].dot(p), m[1].dot(p)) / den
	if not Rect2(-0.00001, -0.00001, 1.00002, 1.00002).has_point(uv):
		return Vector2(-1, -1)
	if o.has("mesh"):
		uv = mesh_uv(uv, o.mesh)
		if uv.x < 0:
			return uv
	var view = v4(o.view)
	if s.kind in ["plane", "mesh"]:
		return Vector2(view.x + uv.x * view.z, view.y + uv.y * view.w)
	if s.kind == "dome":
		var xy = (uv - Vector2(0.5, 0.5)) * 2
		if xy.length() > 1:
			return Vector2(-1, -1)
		return source_uv(Vector2(fposmod(0.5 + atan2(xy.x, -xy.y) / TAU + longitude / 360.0, 1), xy.length() * 0.5), s)
	var basis = optics_in_surface(o, s)
	var eye = basis[0]
	var shift = v2(o.get("shift", [0, 0]))
	var aspect = float(o.size[0]) / o.size[1]
	var offset = (uv - Vector2(0.5, 0.5) + shift) / maxf(0.01, o.get("throw", 1))
	var ray = (basis[1] + basis[2] * offset.x - basis[3] * offset.y / aspect).normalized()
	var q = eye
	var d = ray
	if s.kind == "cylinder":
		q = Vector3(eye.x, 0, eye.z)
		d = Vector3(ray.x, 0, ray.z)
	var a = d.dot(d)
	var b = q.dot(d)
	var disc = b * b - a * (q.dot(q) - s.radius * s.radius)
	if disc < 0 or a < 0.000001:
		return Vector2(-1, -1)
	var t = (-b - sqrt(disc)) / a
	if t <= 0:
		t = (-b + sqrt(disc)) / a
	if t <= 0:
		return Vector2(-1, -1)
	var hit = eye + t * ray
	var lng = atan2(hit.x, hit.z)
	if s.kind == "sphere":
		return source_uv(
			Vector2(fposmod(0.5 + lng / TAU + longitude / 360.0, 1), 0.5 - asin(clampf(hit.y / s.radius, -1, 1)) / PI),
			s
		)
	var result = Vector2(0.5 + lng / deg_to_rad(s.arc), 0.5 - hit.y / s.height)
	if s.arc >= 359.999:
		result.x = fposmod(result.x, 1)
	if result.x < 0 or result.x > 1 or result.y < 0 or result.y > 1:
		return Vector2(-1, -1)
	return result

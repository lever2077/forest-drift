# Procedural deciduous trees (slender trunk, forked branches, airy crown of
# fine compound leaves) scattered through chunks with two levels of detail.
extends Node3D

const MB = preload("res://scripts/mb.gd")

const CHUNK := 48.0
const HI_RANGE := 140.0
const LO_RANGE := 800.0
const VARIANTS := 4

var track
var leaf_mat: StandardMaterial3D
var bark_mat: StandardMaterial3D
var hi_meshes: Array[ArrayMesh] = []
var lo_meshes: Array[ArrayMesh] = []
var bush_mesh: ArrayMesh
var trunk_radius: Array[float] = []

# collision: Vector2i cell -> Array of Vector3(x, z, radius)
const HCELL := 8.0
var hash := {}
var quality := 1.0   # 1 = desktop, lower for VR

# biome look (set by main before build): density, tree shape, leaf colour
var tree_k := 1.0
var bush_k := 1.0
var tree_scale := Vector3.ONE
var leaf_tint := Color.WHITE

func set_biome(b: Dictionary) -> void:
	tree_k = b.get("tree_k", 1.0)
	bush_k = b.get("bush_k", 1.0)
	tree_scale = b.get("tree_scale", Vector3.ONE)
	leaf_tint = b.get("leaf_tint", Color.WHITE)

func build(p_track, p_quality := 1.0, scatter := true) -> void:
	track = p_track
	quality = p_quality
	# solid scenery the map placed (stadium stands, boards, light towers):
	# hit like tree trunks, as (x, z, radius)
	var obs = track.get("obstacles") if track != null else null
	if obs is Array:
		for o in obs:
			var ov: Vector3 = o
			var hk := Vector2i(int(floor(ov.x / HCELL)), int(floor(ov.y / HCELL)))
			if not hash.has(hk):
				hash[hk] = []
			hash[hk].append(ov)
	_make_materials()
	leaf_mat.albedo_color = leaf_mat.albedo_color * leaf_tint
	for v in VARIANTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + v * 77
		var data := _gen_skeleton(rng)
		hi_meshes.append(_mesh_from_skeleton(data, rng, true))
		rng.seed = 5000 + v
		lo_meshes.append(_mesh_from_skeleton(data, rng, false))
		trunk_radius.append(data["trunk_r"])
	bush_mesh = _make_bush()
	if scatter:
		_scatter()

# ---------------------------------------------------------------- textures
func _make_leaf_texture() -> ImageTexture:
	var S := 512
	var data := PackedByteArray()
	data.resize(S * S * 4)
	# transparent background carrying leaf colour (avoids dark mip fringes)
	for i in S * S:
		data[i * 4] = 70
		data[i * 4 + 1] = 98
		data[i * 4 + 2] = 32
		data[i * 4 + 3] = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var leaves := 9
	for l in leaves:
		var ang := TAU * l / leaves + rng.randf_range(-0.3, 0.3)
		var start := Vector2(S * 0.5, S * 0.5) + Vector2(cos(ang), sin(ang)) * rng.randf_range(10, 60)
		var dir := Vector2(cos(ang), sin(ang))
		var length := rng.randf_range(150, 205)
		var pairs := rng.randi_range(5, 6)
		var base_col := Color(rng.randf_range(0.26, 0.36), rng.randf_range(0.46, 0.58), rng.randf_range(0.10, 0.18))
		# rachis
		for s in int(length):
			var p := start + dir * s
			_plot(data, S, int(p.x), int(p.y), Color(0.30, 0.34, 0.14), 1.0)
			_plot(data, S, int(p.x) + 1, int(p.y), Color(0.30, 0.34, 0.14), 1.0)
		for k in pairs:
			var t := 0.22 + 0.78 * float(k) / pairs
			var p := start + dir * length * t
			for side in [-1.0, 1.0]:
				var la: float = ang + side * rng.randf_range(0.85, 1.15)
				var ll := rng.randf_range(22, 30) * (1.0 - 0.25 * t)
				var c := Vector2(p.x + cos(la) * ll * 0.9, p.y + sin(la) * ll * 0.9)
				var col := base_col.lightened(rng.randf_range(-0.12, 0.15))
				_leaflet(data, S, c, ll, ll * 0.42, la, col)
		# terminal leaflet
		var tip := start + dir * (length + 22)
		_leaflet(data, S, tip, 26, 11, ang, base_col.lightened(0.08))
	var img := Image.create_from_data(S, S, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _plot(data: PackedByteArray, S: int, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= S or y >= S:
		return
	var i := (y * S + x) * 4
	data[i] = int(c.r * 255)
	data[i + 1] = int(c.g * 255)
	data[i + 2] = int(c.b * 255)
	data[i + 3] = max(data[i + 3], int(a * 255))

func _leaflet(data: PackedByteArray, S: int, c: Vector2, a: float, b: float, ang: float, col: Color) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var r := int(a) + 1
	for y in range(int(c.y) - r, int(c.y) + r + 1):
		for x in range(int(c.x) - r, int(c.x) + r + 1):
			var dx := x - c.x
			var dy := y - c.y
			var u := dx * ca + dy * sa
			var v := -dx * sa + dy * ca
			var un := u / a
			# pointed oval: narrower towards the tip
			var bw: float = b * (1.0 - 0.35 * max(un, 0.0))
			var e := un * un + (v / bw) * (v / bw)
			if e <= 1.0:
				var shade := 0.85 + 0.25 * (1.0 - e)
				if abs(v) < 0.9:
					shade *= 0.8  # midrib
				_plot(data, S, x, y, Color(col.r * shade, col.g * shade, col.b * shade), 1.0)

func _make_materials() -> void:
	leaf_mat = StandardMaterial3D.new()
	leaf_mat.albedo_texture = _make_leaf_texture()
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf_mat.alpha_scissor_threshold = 0.4
	leaf_mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.roughness = 0.75
	leaf_mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	leaf_mat.backlight_enabled = true
	leaf_mat.backlight = Color(0.55, 0.65, 0.18)
	leaf_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	bark_mat = StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.05
	fn.fractal_octaves = 4
	nt.noise = fn
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	var g := Gradient.new()
	g.set_color(0, Color(0.16, 0.14, 0.12))
	g.set_color(1, Color(0.42, 0.39, 0.35))
	nt.color_ramp = g
	bark_mat.albedo_texture = nt
	var nn := NoiseTexture2D.new()
	nn.noise = fn
	nn.seamless = true
	nn.as_normal_map = true
	nn.bump_strength = 6.0
	bark_mat.normal_enabled = true
	bark_mat.normal_texture = nn
	bark_mat.uv1_scale = Vector3(1.0, 3.0, 1.0)
	bark_mat.roughness = 0.95

# ---------------------------------------------------------------- skeleton
func _gen_skeleton(rng: RandomNumberGenerator) -> Dictionary:
	var segs := []   # [p0, p1, r0, r1]
	var spots := []  # [pos, dir, depth]
	var trunk_h := rng.randf_range(2.3, 3.2)
	var trunk_r := rng.randf_range(0.16, 0.22)
	var lean := Vector3(rng.randf_range(-0.08, 0.08), 1.0, rng.randf_range(-0.08, 0.08)).normalized()
	# trunk in 3 slightly wobbly pieces
	var p := Vector3.ZERO
	var r := trunk_r
	for i in 3:
		var d := (lean + Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))).normalized()
		var q := p + d * trunk_h / 3.0
		var r1 := r * 0.9
		segs.append([p, q, r, r1])
		p = q
		r = r1
	# main scaffold branches from the top of the trunk
	var mains := rng.randi_range(4, 6)
	var phase := rng.randf() * TAU
	for m in mains:
		var az := phase + TAU * m / mains + rng.randf_range(-0.3, 0.3)
		var tilt := rng.randf_range(0.35, 0.75)
		var dir := Vector3(cos(az) * sin(tilt), cos(tilt), sin(az) * sin(tilt)).normalized()
		var start: Vector3 = p - lean * rng.randf_range(0.0, 0.8)
		_grow(rng, segs, spots, start, dir, rng.randf_range(3.6, 4.8), r * 0.75, 0)
	# central leader
	_grow(rng, segs, spots, p, (lean + Vector3(0, 0.4, 0)).normalized(), rng.randf_range(4.0, 5.0), r * 0.7, 0)
	return {"segs": segs, "spots": spots, "trunk_r": trunk_r}

func _grow(rng: RandomNumberGenerator, segs: Array, spots: Array, start: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var nseg := 3
	var p := start
	var d := dir
	var r := radius
	var r_end := radius * 0.35
	var path := [p]
	for s in nseg:
		var wob := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.1, 0.2), rng.randf_range(-0.3, 0.3))
		var trop := Vector3(0, 0.15 if depth < 2 else -0.05, 0)  # upward early, drooping tips
		d = (d + wob * 0.5 + trop).normalized()
		var q := p + d * length / nseg
		var r1 := lerpf(radius, r_end, float(s + 1) / nseg)
		segs.append([p, q, r, r1])
		p = q
		r = r1
		path.append(p)
	if depth >= 2:
		# leaf clusters along the twig
		for k in range(1, path.size()):
			spots.append([path[k], d, depth])
		return
	var kids := 5 if depth == 0 else 3
	for k in kids:
		var t := rng.randf_range(0.35, 1.0)
		var fi := t * nseg
		var si: int = int(min(floor(fi), nseg - 1))
		var a: Vector3 = path[si]
		var b: Vector3 = path[si + 1]
		var at := a.lerp(b, fi - si)
		var axis := d.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		if axis.length() < 0.1:
			axis = Vector3.RIGHT
		var cd := d.rotated(axis, rng.randf_range(0.5, 0.95))
		# push children outward and a little upward
		var outward := Vector3(at.x, 0, at.z).normalized() * 0.3
		cd = (cd + outward + Vector3(0, 0.1, 0)).normalized()
		_grow(rng, segs, spots, at, cd, length * rng.randf_range(0.5, 0.7), lerpf(radius, r_end, t) * 0.75, depth + 1)
	# end of a branch always gets foliage too
	spots.append([p, d, depth])

# ---------------------------------------------------------------- meshes
func _mesh_from_skeleton(data: Dictionary, rng: RandomNumberGenerator, hi: bool) -> ArrayMesh:
	var mb := MB.new()
	var segs: Array = data["segs"]
	var spots: Array = data["spots"]
	# bark
	for s in segs:
		var p0: Vector3 = s[0]
		var p1: Vector3 = s[1]
		var r0: float = s[2]
		var r1: float = s[3]
		if not hi and r0 < 0.07:
			continue
		var sides := 8 if r0 > 0.08 else 5
		if not hi:
			sides = 5
		var h := p0.distance_to(p1)
		var up := (p1 - p0).normalized()
		var basis := Basis()
		var side: Vector3 = up.cross(Vector3.FORWARD if abs(up.z) < 0.9 else Vector3.RIGHT).normalized()
		basis = Basis(side, up, side.cross(up)).orthonormalized()
		var tr := Transform3D(basis, (p0 + p1) * 0.5)
		mb.cylinder("bark", tr, r0, r1, h, sides, false)
	# crown centre / size for shading
	var cen := Vector3.ZERO
	for sp in spots:
		cen += sp[0]
	cen /= max(spots.size(), 1)
	var rad := 0.1
	var ymin := 1e9
	var ymax := -1e9
	for sp in spots:
		var q: Vector3 = sp[0]
		rad = max(rad, Vector2(q.x - cen.x, q.z - cen.z).length())
		ymin = min(ymin, q.y)
		ymax = max(ymax, q.y)
	cen.y = (ymin + ymax) * 0.5
	var stretch: Vector3 = Vector3(1.0 / rad, 2.0 / max(ymax - ymin, 0.1), 1.0 / rad)
	# leaf cards
	var per_spot := 4 if hi else 1
	var stride := 1 if hi else 3
	var idx := 0
	for sp in spots:
		idx += 1
		if idx % stride != 0:
			continue
		var pos: Vector3 = sp[0]
		var dir: Vector3 = sp[1]
		for c in per_spot:
			var size := rng.randf_range(1.0, 1.5) if hi else rng.randf_range(2.8, 3.5)
			var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)) * (0.35 if hi else 0.8)
			var cpos := pos + off + dir * 0.2
			var rel := (cpos - cen) * stretch
			var out_n := rel.normalized()
			if out_n.length() < 0.1:
				out_n = Vector3.UP
			# card plane: mostly facing outward/up with randomness
			var fn := (out_n + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.3, 0.9), rng.randf_range(-0.8, 0.8))).normalized()
			var u: Vector3 = fn.cross(Vector3.UP if abs(fn.y) < 0.95 else Vector3.RIGHT).normalized()
			u = u.rotated(fn, rng.randf() * TAU)
			var v := fn.cross(u).normalized()
			var hs := size * 0.5
			var a := cpos - u * hs - v * hs
			var b := cpos + u * hs - v * hs
			var cc := cpos + u * hs + v * hs
			var d := cpos - u * hs + v * hs
			# fake ambient occlusion + hue variation
			var depth_k := clampf(rel.length(), 0.0, 1.2)
			var up_k: float = clampf((cpos.y - ymin) / max(ymax - ymin, 0.1), 0.0, 1.0)
			var bright := 0.55 + 0.4 * depth_k + 0.3 * up_k
			var hue := rng.randf_range(-0.06, 0.06)
			var col := Color(clampf((0.95 + hue * 1.5) * bright, 0, 1.4), clampf(1.0 * bright, 0, 1.4), clampf((0.85 - hue) * bright, 0, 1.4))
			# spherical normals make the crown shade like one soft volume
			var n := (out_n * 0.8 + fn * 0.2).normalized()
			mb.tri("leaf", a, b, cc, n, n, n, col, col, col, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
			mb.tri("leaf", a, cc, d, n, n, n, col, col, col, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0))
	return mb.build({"bark": bark_mat, "leaf": leaf_mat})

func _make_bush() -> ArrayMesh:
	var mb := MB.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 321
	for i in 22:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
		var cpos := Vector3(dir.x * 0.7, 0.35 + dir.y * 0.6, dir.z * 0.7)
		var fn := (dir + Vector3(rng.randf_range(-0.5, 0.5), 0.4, rng.randf_range(-0.5, 0.5))).normalized()
		var u: Vector3 = fn.cross(Vector3.UP if abs(fn.y) < 0.95 else Vector3.RIGHT).normalized().rotated(fn, rng.randf() * TAU)
		var v := fn.cross(u)
		var hs := rng.randf_range(0.45, 0.65)
		var bright := 0.5 + 0.5 * dir.y
		var col := Color(bright * 0.9, bright, bright * 0.8)
		var n := dir
		mb.tri("leaf", cpos - u * hs - v * hs, cpos + u * hs - v * hs, cpos + u * hs + v * hs, n, n, n, col, col, col, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
		mb.tri("leaf", cpos - u * hs - v * hs, cpos + u * hs + v * hs, cpos - u * hs + v * hs, n, n, n, col, col, col, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0))
	return mb.build({"leaf": leaf_mat})

# ---------------------------------------------------------------- placement
func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var chunks := {}   # Vector2i -> {"t": [Array per variant], "b": Array}
	var tmin: Vector2 = track.T_MIN + Vector2(40, 40)
	var tmax: Vector2 = track.T_MAX - Vector2(40, 40)
	var spacing := 6.5 / sqrt(quality)
	var x := tmin.x
	while x < tmax.x:
		var z := tmin.y
		while z < tmax.y:
			var px := x + rng.randf_range(-0.45, 0.45) * spacing
			var pz := z + rng.randf_range(-0.45, 0.45) * spacing
			var d: float = track.road_dist(px, pz)
			var keep := true
			if d < track.HALF_W + 3.5:
				keep = false
			elif d > 70.0:
				keep = rng.randf() < 0.55   # thinner deep forest
			# maps can thin the trees out (open hillsides with clumps)
			if keep and track.has_method("tree_density"):
				keep = rng.randf() < track.tree_density(px, pz, d)
			if keep and tree_k < 1.0:
				keep = rng.randf() < tree_k
			if keep:
				var key := Vector2i(int(floor(px / CHUNK)), int(floor(pz / CHUNK)))
				if not chunks.has(key):
					var tl := []
					for v in VARIANTS:
						tl.append([])
					chunks[key] = {"t": tl, "b": []}
				var v := rng.randi() % VARIANTS
				var s := rng.randf_range(0.8, 1.25)
				var h: float = track.surface_h(px, pz) if track.has_method("surface_h") else track.terrain_h(px, pz)   # sit on the drawn ground
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.92, 1.1), s))
				chunks[key]["t"][v].append(Transform3D(basis, Vector3(px, h - 0.1, pz)))
				var hk := Vector2i(int(floor(px / HCELL)), int(floor(pz / HCELL)))
				if not hash.has(hk):
					hash[hk] = []
				hash[hk].append(Vector3(px, pz, trunk_radius[v] * s + 0.05))
			# bushes near the road edge
			var bk: float = (track.bush_density(px, pz, d) if track.has_method("bush_density") else 1.0) * bush_k
			if d > track.HALF_W + 2.0 and d < 40.0 and rng.randf() < 0.35 * bk:
				var bx := px + rng.randf_range(-2, 2)
				var bz := pz + rng.randf_range(-2, 2)
				if track.road_dist(bx, bz) > track.HALF_W + 2.0:
					var key2 := Vector2i(int(floor(bx / CHUNK)), int(floor(bz / CHUNK)))
					if not chunks.has(key2):
						var tl2 := []
						for v in VARIANTS:
							tl2.append([])
						chunks[key2] = {"t": tl2, "b": []}
					var bs := rng.randf_range(0.7, 1.5)
					chunks[key2]["b"].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(bs, bs * 0.8, bs)), Vector3(bx, (track.surface_h(bx, bz) if track.has_method("surface_h") else track.terrain_h(bx, bz)) - 0.1, bz)))
			z += spacing
		x += spacing
	for key in chunks.keys():
		var k: Vector2i = key
		var centre := Vector3((k.x + 0.5) * CHUNK, 0, (k.y + 0.5) * CHUNK)
		centre.y = track.terrain_h(centre.x, centre.z)
		var ch: Dictionary = chunks[key]
		for v in VARIANTS:
			var list: Array = ch["t"][v]
			if list.is_empty():
				continue
			_add_tree_lods(v, list, centre, null)
		var bl: Array = ch["b"]
		if not bl.is_empty():
			_add_mm(bush_mesh, bl, centre, 0.0, 120.0, false)

# Full-detail trees up close and light ones further out. The sun's shadows come
# from an invisible copy of the light tree (~350 triangles instead of ~6,500),
# because the shadow map draws every tree up to four times: that was what made
# daytime so much slower than night.
func _add_tree_lods(v: int, list: Array, centre: Vector3, parent: Node3D) -> void:
	# biome tree shape: wide flat-topped (savannah), tall and narrow (tundra)
	if tree_scale != Vector3.ONE:
		var scaled := []
		for t in list:
			var tr: Transform3D = t
			tr.basis = tr.basis * Basis.from_scale(tree_scale)
			scaled.append(tr)
		list = scaled
	_add_mm(hi_meshes[v], list, centre, 0.0, HI_RANGE, false, parent)
	_add_mm(lo_meshes[v], list, centre, HI_RANGE - 10.0, LO_RANGE, false, parent)
	_add_mm(lo_meshes[v], list, centre, 0.0, HI_RANGE, true, parent, true)

func _add_mm(mesh: Mesh, list: Array, centre: Vector3, r0: float, r1: float, shadows: bool, parent: Node3D = null, shadow_only := false) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var t: Transform3D = list[i]
		t.origin -= centre
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = centre
	mmi.visibility_range_begin = r0
	mmi.visibility_range_end = r1
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shadow_only:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if parent:
		parent.add_child(mmi)
	else:
		add_child(mmi)

func trees_near(x: float, z: float) -> Array:
	var out := []
	var cx := int(floor(x / HCELL))
	var cz := int(floor(z / HCELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(cx + dx, cz + dz)
			if hash.has(k):
				out.append_array(hash[k])
	return out

# ---- streaming (endless road): plant one block of trees under 'parent'.
# trees: Array of [Transform3D, variant]; bushes: Array of Transform3D (world space)
func add_tree_block(trees: Array, bushes: Array, centre: Vector3, parent: Node3D) -> void:
	var per := []
	for v in VARIANTS:
		per.append([])
	for t in trees:
		var tr: Transform3D = t[0]
		var v: int = t[1]
		per[v].append(tr)
		var hk := Vector2i(int(floor(tr.origin.x / HCELL)), int(floor(tr.origin.z / HCELL)))
		if not hash.has(hk):
			hash[hk] = []
		var s: float = tr.basis.get_scale().x
		hash[hk].append(Vector3(tr.origin.x, tr.origin.z, trunk_radius[v] * s + 0.05))
	for v in VARIANTS:
		var list: Array = per[v]
		if list.is_empty():
			continue
		_add_tree_lods(v, list, centre, parent)
	if not bushes.is_empty():
		_add_mm(bush_mesh, bushes, centre, 0.0, 120.0, false, parent)

func forget_trees(xmin: float, xmax: float, zmin: float, zmax: float) -> void:
	# drop collision entries for a region that has been unloaded
	for k in hash.keys():
		var kv: Vector2i = k
		var x := (kv.x + 0.5) * HCELL
		var z := (kv.y + 0.5) * HCELL
		if x > xmin and x < xmax and z > zmin and z < zmax:
			hash.erase(k)
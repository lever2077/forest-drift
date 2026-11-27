# Procedural deciduous trees (slender trunk, forked branches, airy crown of
# fine compound leaves) scattered through chunks with two levels of detail.
extends Node3D

const MB = preload("res://scripts/mb.gd")
const Gfx = preload("res://scripts/gfx.gd")

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
var leaf_color := Color(0, 0, 0, 0)   # a > 0: leaves repainted in this colour
var leaf_glow := 0.0                  # leaves glow in glow_col (neon biome)
var glow_col := Color.BLACK
var glow_col2 := Color.BLACK
var buildings := false                # neon night: buildings with neon edges instead of trees
var no_leaves := false                # volcanic: bare charred trees
var bark_col := Color(0, 0, 0, 0)     # a > 0: bark in this colour (charred black)
var tree_clear := 0.0                 # extra space kept free beside the road (buildings)
var bld_mat: StandardMaterial3D
var neon_mats: Array = []

func set_biome(b: Dictionary) -> void:
	tree_k = b.get("tree_k", 1.0)
	bush_k = b.get("bush_k", 1.0)
	tree_scale = b.get("tree_scale", Vector3.ONE)
	leaf_tint = b.get("leaf_tint", Color.WHITE)
	leaf_color = b.get("leaf_color", Color(0, 0, 0, 0))
	leaf_glow = float(b.get("leaf_glow", 0.0))
	glow_col = b.get("glow_col", Color.BLACK)
	glow_col2 = b.get("glow_col2", glow_col)
	buildings = bool(b.get("buildings", false))
	no_leaves = bool(b.get("no_leaves", false))
	bark_col = b.get("bark_col", Color(0, 0, 0, 0))
	tree_clear = float(b.get("tree_clear", 0.0))

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
	if leaf_glow > 0.0:   # neon leaves
		leaf_mat.emission_enabled = true
		leaf_mat.emission = glow_col
		leaf_mat.emission_energy_multiplier = leaf_glow
	Gfx.surface(leaf_mat)
	Gfx.surface(bark_mat)
	if buildings:
		_make_building_mats()
	for v in VARIANTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + v * 77
		if buildings:   # neon night: a building instead of each tree variant
			var bres: Array = _building(rng, true)
			hi_meshes.append(bres[0])
			lo_meshes.append(_building(rng, false, bres[2])[0])
			trunk_radius.append(bres[1])
			continue
		var data := _gen_skeleton(rng)
		if Gfx.low and not no_leaves:   # low detail: round ball crowns (bare charred trees keep their branches)
			hi_meshes.append(_ball_tree(data, rng, true))
			lo_meshes.append(_ball_tree(data, rng, false))
		else:
			hi_meshes.append(_mesh_from_skeleton(data, rng, true))
			rng.seed = 5000 + v
			lo_meshes.append(_mesh_from_skeleton(data, rng, false))
		trunk_radius.append(data["trunk_r"])
	bush_mesh = _make_ball_bush() if Gfx.low else _make_bush()
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
	# biome leaf colour (autumn orange, blossom pink, ...): repaint the green
	# leaves in it, keeping each pixel's light and shade
	if leaf_color.a > 0.0:
		var ref := 0.3 * 0.31 + 0.59 * 0.52 + 0.11 * 0.14
		for i in S * S:
			var o := i * 4
			var k := (0.3 * data[o] + 0.59 * data[o + 1] + 0.11 * data[o + 2]) / 255.0 / ref
			data[o] = int(clampf(leaf_color.r * k, 0.0, 1.0) * 255.0)
			data[o + 1] = int(clampf(leaf_color.g * k, 0.0, 1.0) * 255.0)
			data[o + 2] = int(clampf(leaf_color.b * k, 0.0, 1.0) * 255.0)
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
	if Gfx.low:
		# low detail: smooth solid colours, no leaf cut-outs (opaque is much cheaper)
		leaf_mat = StandardMaterial3D.new()
		leaf_mat.albedo_color = Color(leaf_color.r * 0.8, leaf_color.g * 0.8, leaf_color.b * 0.8) if leaf_color.a > 0.0 else Color(0.25, 0.42, 0.12)
		leaf_mat.vertex_color_use_as_albedo = true
		leaf_mat.roughness = 1.0
		leaf_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		bark_mat = StandardMaterial3D.new()
		bark_mat.albedo_color = Color(0.3, 0.27, 0.24) if bark_col.a <= 0.0 else bark_col
		bark_mat.vertex_color_use_as_albedo = true
		bark_mat.roughness = 1.0
		bark_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		return
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
	g.set_color(0, Color(0.16, 0.14, 0.12) if bark_col.a <= 0.0 else bark_col.darkened(0.5))
	g.set_color(1, Color(0.42, 0.39, 0.35) if bark_col.a <= 0.0 else bark_col.lightened(0.25))
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
	bark_mat.vertex_color_use_as_albedo = Gfx.baked   # baked: trunks darker near the ground

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
		mb.cylinder("bark", tr, r0, r1, h, sides, false, _bark_col((p0.y + p1.y) * 0.5))
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
	var per_spot := 0 if no_leaves else (4 if hi else 1)   # charred trees: bare branches
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
			if Gfx.baked:   # bake the sun side of the crown into the leaf colour
				col = col * (Gfx.light_at(n, 0.9) * 1.1)
				col.a = 1.0
			mb.tri("leaf", a, b, cc, n, n, n, col, col, col, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
			mb.tri("leaf", a, cc, d, n, n, n, col, col, col, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0))
	return mb.build({"bark": bark_mat, "leaf": leaf_mat})

# trunk shade: with baked lighting, darker near the ground (light blocked by the
# crown and the undergrowth), otherwise plain white (no effect)
func _bark_col(y: float) -> Color:
	if not Gfx.baked:
		return Color.WHITE
	var k := lerpf(0.35, 0.8, clampf(y / 4.0, 0.0, 1.0))
	return Color(k, k, k)

# ---------------------------------------------------------------- low detail (ball trees)
# A smooth ball of leaves. Vertex colours carry a soft shade: with baked lighting
# the full sun + sky light, otherwise just a little darkening underneath.
func _ball(mb, centre: Vector3, r: Vector3, seg_u: int, seg_v: int, base: Color, ao: float) -> void:
	var pts := []
	for j in seg_v + 1:
		var b := lerpf(-PI / 2, PI / 2, float(j) / seg_v)
		var row := []
		for i in seg_u + 1:
			var a := TAU * i / seg_u
			row.append(Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b)))
		pts.append(row)
	for j in seg_v:
		for i in seg_u:
			var q := [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
			var vs := []
			var ns := []
			var cs := []
			for u in q:
				var uv: Vector3 = u
				vs.append(centre + uv * r)
				var n := Vector3(uv.x / r.x, uv.y / r.y, uv.z / r.z).normalized()
				ns.append(n)
				var shade: float
				if Gfx.baked:
					shade = Gfx.light_at(n, ao) * 1.15
				else:
					shade = lerpf(0.72, 1.0, 0.5 + 0.5 * n.y) * lerpf(1.0, ao, 0.6)
				var c := base * shade
				c.a = 1.0
				cs.append(c)
			mb.tri("leaf", vs[0], vs[1], vs[2], ns[0], ns[1], ns[2], cs[0], cs[1], cs[2])
			mb.tri("leaf", vs[0], vs[2], vs[3], ns[0], ns[2], ns[3], cs[0], cs[2], cs[3])

# Low detail tree: the trunk and a short leader into the crown, then one big
# leaf ball with a few smaller ones around it, sized to the full tree's crown.
func _ball_tree(data: Dictionary, rng: RandomNumberGenerator, hi: bool) -> ArrayMesh:
	var mb := MB.new()
	var segs: Array = data["segs"]
	var spots: Array = data["spots"]
	var sides := 7 if hi else 5
	var top := Vector3.ZERO
	var top_r := 0.1
	for i in 3:   # the first three segments are the trunk
		var s: Array = segs[i]
		_bark_seg(mb, s[0], s[1], s[2], s[3], sides)
		top = s[1]
		top_r = s[3]
	# crown extent from the leaf spots of the full tree
	var cen := Vector3.ZERO
	for sp in spots:
		cen += sp[0]
	cen /= max(spots.size(), 1)
	var rad := 0.5
	var ymin := 1e9
	var ymax := -1e9
	for sp in spots:
		var q: Vector3 = sp[0]
		rad = max(rad, Vector2(q.x - cen.x, q.z - cen.z).length())
		ymin = min(ymin, q.y)
		ymax = max(ymax, q.y)
	cen.y = (ymin + ymax) * 0.5 + 0.3
	var half_h: float = max(ymax - ymin, 1.0) * 0.5
	_bark_seg(mb, top, cen, top_r, top_r * 0.5, sides)
	var su := 14 if hi else 8
	var sv := 9 if hi else 5
	var green := Color(1.0 + rng.randf_range(-0.08, 0.08), 1.0, 1.0 + rng.randf_range(-0.1, 0.1))
	# main ball
	_ball(mb, cen, Vector3(rad * 0.78, half_h * 0.95, rad * 0.78), su, sv, green, 0.95)
	# smaller balls bulging out of it: lumpy, more tree-like silhouette
	var n := rng.randi_range(4, 6)
	var phase := rng.randf() * TAU
	for k in n:
		var az := phase + TAU * k / n + rng.randf_range(-0.3, 0.3)
		var up := rng.randf_range(-0.45, 0.55)
		var d := Vector3(cos(az) * (1.0 - abs(up) * 0.5), up, sin(az) * (1.0 - abs(up) * 0.5))
		var p := cen + Vector3(d.x * rad * 0.62, d.y * half_h * 0.7, d.z * rad * 0.62)
		var br := rad * rng.randf_range(0.42, 0.55)
		var tint := green.lightened(rng.randf_range(-0.08, 0.12))
		_ball(mb, p, Vector3(br, br * 0.85, br), max(su - 4, 6), max(sv - 2, 4), tint, lerpf(0.75, 1.0, 0.5 + 0.5 * up))
	return mb.build({"bark": bark_mat, "leaf": leaf_mat})

# ---------------------------------------------------------------- neon night buildings
func _make_building_mats() -> void:
	bld_mat = StandardMaterial3D.new()
	bld_mat.albedo_color = Color(0.035, 0.035, 0.05)
	bld_mat.roughness = 0.55
	bld_mat.metallic = 0.3
	Gfx.surface(bld_mat)
	neon_mats = []
	for c in [glow_col, glow_col2, Color(1.0, 0.82, 0.55)]:
		var m := StandardMaterial3D.new()
		var cc: Color = c
		m.albedo_color = Color(cc.r, cc.g, cc.b).clamp() * 0.3
		m.emission_enabled = true
		m.emission = cc
		m.emission_energy_multiplier = 2.2
		neon_mats.append(m)
	neon_mats[2].emission_energy_multiplier = 0.9   # windows: a softer warm light

# A tower block: dark walls, neon tubes along every vertical and top edge, a
# band of the second neon colour round one floor and some lit windows.
# Returns [mesh, collision radius, [w, d, h]] (pass the size back in for the
# far-away version, which skips the windows).
func _building(rng: RandomNumberGenerator, hi: bool, dims := []) -> Array:
	var w: float = dims[0] if dims.size() > 0 else rng.randf_range(6.0, 10.0)
	var d: float = dims[1] if dims.size() > 1 else rng.randf_range(6.0, 10.0)
	var h: float = dims[2] if dims.size() > 2 else rng.randf_range(9.0, 26.0)
	var mb := MB.new()
	# walls (reaching 3 m below the base so slopes don't show a gap)
	mb.box("bld", Transform3D(Basis(), Vector3(0, h * 0.5 - 1.5, 0)), Vector3(w, h + 3.0, d))
	var e := 0.16
	var hw := w * 0.5 + 0.03
	var hd := d * 0.5 + 0.03
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.box("neon", Transform3D(Basis(), Vector3(hw * sx, h * 0.5 - 0.25, hd * sz)), Vector3(e, h + 0.5, e))
	for sz in [-1.0, 1.0]:
		mb.box("neon", Transform3D(Basis(), Vector3(0, h, hd * sz)), Vector3(w + e, e, e))
	for sx in [-1.0, 1.0]:
		mb.box("neon", Transform3D(Basis(), Vector3(hw * sx, h, 0)), Vector3(e, e, d + e))
	# a band of the second colour round one floor
	var by: float = 3.2 * rng.randi_range(1, max(int(h / 3.2) - 1, 1))
	for sz in [-1.0, 1.0]:
		mb.box("neon2", Transform3D(Basis(), Vector3(0, by, hd * sz)), Vector3(w, e * 0.8, e * 0.8))
	for sx in [-1.0, 1.0]:
		mb.box("neon2", Transform3D(Basis(), Vector3(hw * sx, by, 0)), Vector3(e * 0.8, e * 0.8, d))
	# lit windows
	if hi:
		var floors := int(h / 3.2)
		for f in floors:
			var y := 1.6 + f * 3.2
			for face in 4:
				var along := w if face < 2 else d
				var n := int(along / 2.4)
				for k in n:
					if rng.randf() > 0.32:
						continue
					var u := -along * 0.5 + (k + 0.5) * along / n
					var sgn := 1.0 if face % 2 == 0 else -1.0
					var c: Vector3
					var sz2: Vector3
					if face < 2:
						c = Vector3(u, y, (d * 0.5 + 0.02) * sgn)
						sz2 = Vector3(1.2, 1.1, 0.02)
					else:
						c = Vector3((w * 0.5 + 0.02) * sgn, y, u)
						sz2 = Vector3(0.02, 1.1, 1.2)
					mb.box("win", Transform3D(Basis(), c), sz2)
	var mesh: ArrayMesh = mb.build({"bld": bld_mat, "neon": neon_mats[0], "neon2": neon_mats[1], "win": neon_mats[2]})
	return [mesh, max(w, d) * 0.62, [w, d, h]]

func _bark_seg(mb, p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int) -> void:
	var h := p0.distance_to(p1)
	if h < 0.01:
		return
	var up := (p1 - p0).normalized()
	var side: Vector3 = up.cross(Vector3.FORWARD if abs(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).orthonormalized()
	mb.cylinder("bark", Transform3D(basis, (p0 + p1) * 0.5), r0, r1, h, sides, false, _bark_col((p0.y + p1.y) * 0.5))

func _make_ball_bush() -> ArrayMesh:
	var mb := MB.new()
	_ball(mb, Vector3(0, 0.45, 0), Vector3(0.85, 0.6, 0.85), 10, 6, Color(0.95, 1.0, 0.9), 0.85)
	_ball(mb, Vector3(0.45, 0.35, 0.2), Vector3(0.5, 0.42, 0.5), 8, 5, Color(1.0, 1.05, 0.9), 0.8)
	return mb.build({"leaf": leaf_mat})

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
		if Gfx.baked:
			col = col * (Gfx.light_at(n) * 1.2)
			col.a = 1.0
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
			if d < track.HALF_W + 3.5 + tree_clear:
				keep = false
			elif d > 70.0 and not buildings:
				keep = rng.randf() < 0.55   # thinner deep forest
			# maps can thin the trees out (open hillsides with clumps)
			if keep and track.has_method("tree_density"):
				keep = rng.randf() < track.tree_density(px, pz, d)
			if keep and track.get("sea") == true and track.surface_h(px, pz) < track.sea_y + 0.6:
				keep = false   # beach: no trees in the sea
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
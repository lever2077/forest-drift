# Hillside Touge: a closed mountain-pass circuit cut into a big grassy slope.
# Switchback hairpins climb the hill in stacked tiers, a ridge run along the top,
# then a long fast descent down the far side. Armco guardrails line the drops and
# the outside of corners, street lamps stand along the road, and trees grow in
# loose clumps on the open grass.
extends "res://scripts/track.gd"

const RAIL_OFF := HALF_W + 1.0     # guardrail line, measured from the road centre
var rail_l := PackedByteArray()    # per road sample: rail on the left / right side
var rail_r := PackedByteArray()
var g_off := PackedFloat32Array()  # road height minus raw hill height at the nearest road point
var clump := FastNoiseLite.new()
var lamps: Array[SpotLight3D] = []
var lamp_mat: StandardMaterial3D

func _init() -> void:
	ctrl = [
		# bottom straight heading east, first hairpin climbs left
		Vector2(-250, -224), Vector2(-60, -230), Vector2(150, -232),
		Vector2(228, -204), Vector2(244, -152), Vector2(186, -120),
		# tier 2 back west, hairpin right
		Vector2(40, -108), Vector2(-80, -92),
		Vector2(-168, -62), Vector2(-182, -12), Vector2(-122, 12),
		# tier 3 east, hairpin left
		Vector2(0, 18), Vector2(112, 32),
		Vector2(200, 62), Vector2(212, 112), Vector2(150, 138),
		# tier 4 west, hairpin right onto the ridge
		Vector2(30, 144), Vector2(-90, 152),
		Vector2(-190, 178), Vector2(-202, 226), Vector2(-140, 248),
		# ridge run along the top
		Vector2(0, 254), Vector2(140, 244), Vector2(262, 228),
		# long descent down the east side
		Vector2(334, 180), Vector2(352, 80), Vector2(344, -30), Vector2(332, -140),
		# bottom sweepers back west to the start
		Vector2(306, -238), Vector2(236, -290), Vector2(100, -302), Vector2(-100, -300),
		Vector2(-262, -292), Vector2(-326, -256),
	]
	G_MIN = Vector2(-440, -400)
	crest_count = 0
	smooth_win = 8
	blend_far = 10.0
	gantry_text = "SWITCHBACK RIDGE"
	grass_density = 1.7
	grass_height = 1.15
	clump.seed = 31
	clump.frequency = 0.012

# one big slope rising to the north, with rolling bumps and hills at the sides
func base_hill(x: float, z: float) -> float:
	var h := 66.0 * sstep(-330.0, 280.0, z)
	if z > 280.0:
		h += (z - 280.0) * 0.06
	h += 22.0 * sstep(400.0, 650.0, abs(x)) + 18.0 * sstep(-420.0, -650.0, z)
	h += hills.get_noise_2d(x, z) * 6.0 + hills2.get_noise_2d(x, z) * 0.8
	return h

func build() -> void:
	super()
	if biome["name"] == "Forest":
		terrain_mat.set_shader_parameter("litter_k", 0.12)   # open meadow, not forest floor
		terrain_mat.set_shader_parameter("tint", Vector3(0.62, 0.7, 0.55))   # deep grass green under the blades
	_build_rails()
	_build_lamps()

# remember how far the road sits above/below the raw hill, so the land can
# return to the hill shape without a step between stacked road tiers
func _build_grid() -> void:
	super()
	g_off.resize(gw * gh)
	g_off.fill(0.0)
	for i in gw * gh:
		if g_dist[i] < G_RADIUS + 5.0:
			g_off[i] = g_rh[i] - base_hill(g_px[i], g_pz[i])

func terrain_h(x: float, z: float) -> float:
	var d := road_dist(x, z)
	var base := base_hill(x, z) + Biome.extra_height(biome, x, z, d)
	if d > G_RADIUS - 1.0:
		return base
	var rh := road_h(x, z)
	var off := _grid_sample(g_off, x, z) * (1.0 - sstep(HALF_W + 6.0, G_RADIUS - 2.0, d))
	var t := sstep(HALF_W + 1.0, HALF_W + blend_far, d)
	return lerpf(rh - 0.15, base + off, t)

# open grass between the road tiers with the odd clump of trees; forest
# grows around the outside of the course
func tree_density(x: float, z: float, d: float) -> float:
	if d < 18.0:
		return 0.0
	var c := clump.get_noise_2d(x, z)
	var inside := sstep(420.0, 380.0, abs(x - 10.0)) * sstep(-370.0, -330.0, z) * sstep(320.0, 280.0, z)
	var open_k := 0.35 + 0.65 * sstep(-0.1, 0.35, c)    # woodland with clearings between the tiers
	var forest_k := 0.85 + 0.15 * sstep(-0.2, 0.2, c)   # nearly solid forest around the edge
	return lerpf(forest_k, open_k, inside)

func bush_density(_x: float, _z: float, _d: float) -> float:
	return 0.25

# ---------------------------------------------------------------- guardrails
func _build_rails() -> void:
	var cnt := pts.size()
	rail_l.resize(cnt)
	rail_r.resize(cnt)
	for i in cnt:
		var p: Vector3 = pts[i]
		var t: Vector3 = tans[i]
		var left := Vector3(-t.z, 0, t.x)
		for sv in [1.0, -1.0]:
			var s: float = sv
			var q: Vector3 = p + left * s * (HALF_W + 9.0)
			var drop: bool = base_hill(q.x, q.z) < p.y - 1.4         # the land falls away on this side
			var outside: bool = curv[i] * s < -0.01                  # outside of a corner
			var rp: Vector3 = p + left * s * RAIL_OFF
			var clear: bool = _other_road_dist(rp, i) > HALF_W + 2.0 # don't fence across another tier
			var on: bool = (drop or outside) and clear
			if s > 0.0:
				rail_l[i] = 1 if on else 0
			else:
				rail_r[i] = 1 if on else 0
	# no rails right at the start line, and close tiny gaps / drop tiny pieces
	for k in range(-6, 7):
		rail_l[(k + cnt) % cnt] = 0
		rail_r[(k + cnt) % cnt] = 0
	rail_l = _clean(rail_l)
	rail_r = _clean(rail_r)
	var mb := MB.new()
	for sdv in [1.0, -1.0]:
		var side: float = sdv
		var flags: PackedByteArray = rail_l if side > 0.0 else rail_r
		for i in cnt:
			var j := (i + 1) % cnt
			if flags[i] == 0 or flags[j] == 0:
				continue
			var a := _rail_point(i, side)
			var b := _rail_point(j, side)
			var out_n := Vector3(-tans[i].z, 0, tans[i].x) * side
			# W-beam: two angled strips, seen from both sides
			for strip in [[0.42, 0.58, 0.05], [0.58, 0.74, -0.05]]:
				var y0: float = strip[0]
				var y1: float = strip[1]
				var lean: float = strip[2]
				var a0 := a + Vector3(0, y0, 0)
				var a1 := a + Vector3(0, y1, 0) + out_n * lean
				var b0 := b + Vector3(0, y0, 0)
				var b1 := b + Vector3(0, y1, 0) + out_n * lean
				var n_in := (-out_n + Vector3(0, 0.25 * signf(lean), 0)).normalized()
				mb.quad("rail", a0, b0, b1, a1, n_in, n_in, n_in, n_in)
				mb.quad("rail", a0, b0, b1, a1, -n_in, -n_in, -n_in, -n_in)
			# a post every 4 m
			if i % 2 == 0:
				var pb := Basis.looking_at(tans[i], Vector3.UP)
				mb.box("post", Transform3D(pb, a + out_n * 0.12 + Vector3(0, 0.25, 0)), Vector3(0.1, 1.1, 0.14))
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.74, 0.76, 0.78)
	rail_mat.metallic = 0.75
	rail_mat.roughness = 0.38
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.45, 0.46, 0.48)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.5
	var mi := MeshInstance3D.new()
	mi.name = "Guardrails"
	mi.mesh = mb.build({"rail": rail_mat, "post": post_mat})
	add_child(mi)

func _rail_point(i: int, side: float) -> Vector3:
	var p: Vector3 = pts[i]
	var t: Vector3 = tans[i]
	return Vector3(p.x, p.y + 0.04, p.z) + Vector3(-t.z, 0, t.x) * side * RAIL_OFF

# distance from a point to the road, ignoring the stretch around sample i
func _other_road_dist(p: Vector3, i: int) -> float:
	var cnt := pts.size()
	var best := 1e9
	for k in range(0, cnt, 3):
		var dk: int = abs(k - i)
		if min(dk, cnt - dk) < 30:
			continue
		var q: Vector3 = pts[k]
		best = min(best, Vector2(q.x - p.x, q.z - p.z).length())
	return best

static func _clean(f: PackedByteArray) -> PackedByteArray:
	var cnt := f.size()
	var o := f.duplicate()
	# fill gaps shorter than 6 samples
	for i in cnt:
		if f[i] == 0:
			var a := false
			var b := false
			for k in range(1, 7):
				a = a or f[(i - k + cnt) % cnt] == 1
				b = b or f[(i + k) % cnt] == 1
			if a and b:
				o[i] = 1
	# drop runs shorter than 8 samples
	var o2 := o.duplicate()
	var i := 0
	while i < cnt:
		if o[i] == 1:
			var j := i
			while j < i + cnt and o[j % cnt] == 1:
				j += 1
			if j - i < 8:
				for k in range(i, j):
					o2[k % cnt] = 0
			i = j
		else:
			i += 1
	return o2

# car collision: returns how far to push a point back inside the rails
# (and the outward normal), or ZERO when it isn't touching one
func rail_push(p: Vector3, hint: int) -> Vector3:
	if rail_l.is_empty():
		return Vector3.ZERO
	var i := nearest_index(p, hint, 8)
	var t: Vector3 = tans[i]
	var left := Vector3(-t.z, 0, t.x)
	var s: float = (p - pts[i]).dot(left)
	if s > RAIL_OFF - 0.1 and s < RAIL_OFF + 1.6 and rail_l[i] == 1:
		return -left * (s - RAIL_OFF + 0.1)
	if s < -(RAIL_OFF - 0.1) and s > -(RAIL_OFF + 1.6) and rail_r[i] == 1:
		return left * (-s - RAIL_OFF + 0.1)
	return Vector3.ZERO

# ---------------------------------------------------------------- street lamps
func _build_lamps() -> void:
	var cnt := pts.size()
	var mb := MB.new()
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.95, 0.92, 0.8)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.85, 0.6)
	lamp_mat.emission_energy_multiplier = 0.0
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.36, 0.38, 0.4)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.45
	var i := 10
	while i < cnt - 10:
		# stand on the outside of the bend (or the drop side), behind any rail
		var side := -signf(curv[i]) if abs(curv[i]) > 0.004 else (1.0 if rail_l[i] == 1 else -1.0)
		var p: Vector3 = pts[i]
		var t: Vector3 = tans[i]
		var left := Vector3(-t.z, 0, t.x) * side
		var base := Vector3(p.x, 0, p.z) + left * (HALF_W + 2.3)
		if _other_road_dist(base, i) > HALF_W + 3.0:
			base.y = terrain_h(base.x, base.z) - 0.2
			mb.cylinder("pole", Transform3D(Basis(), base + Vector3(0, 4.2, 0)), 0.11, 0.07, 8.4, 8)
			# arm reaching out over the road
			var top := base + Vector3(0, 8.3, 0)
			var tip := top - left * 2.2 + Vector3(0, 0.2, 0)
			mb.beam("pole", top, tip, Vector3.UP, 0.08, 0.06, 0.08, 0.06)
			var hb := Basis.looking_at(-left, Vector3.UP)
			mb.box("head", Transform3D(hb, tip + Vector3(0, -0.08, 0)), Vector3(0.32, 0.12, 0.7))
			var sl := SpotLight3D.new()
			sl.position = tip + Vector3(0, -0.2, 0)
			sl.rotation = Vector3(-PI / 2, 0, 0)
			sl.spot_angle = 62.0
			sl.spot_range = 22.0
			sl.light_energy = 3.0
			sl.light_color = Color(1.0, 0.82, 0.58)
			sl.distance_fade_enabled = true
			sl.distance_fade_begin = 90.0
			sl.distance_fade_length = 30.0
			sl.visible = false
			add_child(sl)
			lamps.append(sl)
		i += 28
	var mi := MeshInstance3D.new()
	mi.name = "Lamps"
	mi.mesh = mb.build({"pole": pole_mat, "head": lamp_mat})
	add_child(mi)

# street lamps switch on with the headlights
func set_night(on: bool) -> void:
	if lamp_mat:
		lamp_mat.emission_energy_multiplier = 4.0 if on else 0.0
	for l in lamps:
		l.visible = on

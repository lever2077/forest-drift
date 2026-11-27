# Winding closed-loop forest road + terrain.
# Also answers queries: road distance, road/ground height, nearest sample.
extends Node3D

const MB = preload("res://scripts/mb.gd")
const Biome = preload("res://scripts/biome.gd")
const Gfx = preload("res://scripts/gfx.gd")

# cosmetic biome (set by main before build); see biome.gd
var biome: Dictionary = Biome.get_biome("Forest")

const HALF_W := 5.25         # road half width: one 10.5 m lane
const STEP := 2.0            # spacing of road samples (m)
var ctrl := [
	Vector2(0, -250), Vector2(150, -262), Vector2(262, -222), Vector2(302, -132), Vector2(252, -58),
	Vector2(172, -38), Vector2(128, 22), Vector2(172, 92), Vector2(282, 118), Vector2(322, 202),
	Vector2(272, 282), Vector2(150, 302), Vector2(40, 252), Vector2(-20, 172), Vector2(-92, 140),
	Vector2(-172, 200), Vector2(-262, 232), Vector2(-322, 160), Vector2(-302, 60), Vector2(-222, 18),
	Vector2(-252, -80), Vector2(-322, -150), Vector2(-282, -242), Vector2(-150, -272),
]

# ---- per-map settings (a map script can change these in _init)
var crest_count := 3           # jump crests on the straightest stretches
var smooth_win := 25           # elevation smoothing (samples each side)
var blend_far := 26.0          # how far the land takes to blend from road level to the hills
var gantry_text := "GREENWOOD CIRCUIT"
var grass_density := 0.8       # tufts per square metre multiplier for the grass system
var grass_height := 1.0

var pts := PackedVector3Array()      # road centre samples (x, height, z)
var tans := PackedVector3Array()     # unit tangents (xz)
var curv := PackedFloat32Array()     # signed curvature
var total_len := 0.0
var endless := false
var bump_centres: Array[int] = []
var obstacles: Array = []            # solid scenery (x, z, radius), hit like trees
var road_mat: StandardMaterial3D

var terrain_mat: ShaderMaterial
var surf_wet := 0.0
var grass_mat: ShaderMaterial    # set by the grass system so snow can frost it

# rain: darker, shinier asphalt (0..1)
func set_wet(w: float) -> void:
	if abs(w - surf_wet) < 0.01:
		return
	surf_wet = w
	_apply_surface()

# snow weather: snow on the ground (the road itself stays clear tarmac)
func set_snow(s: float) -> void:
	s = max(s, biome.get("snow_base", 0.0))   # tundra ground is always frosted
	if terrain_mat:
		terrain_mat.set_shader_parameter("snow", s)
	if grass_mat:
		grass_mat.set_shader_parameter("snow", s)

func _apply_surface() -> void:
	if road_mat == null:
		return
	# wet: darker and shiny, but not mirror-smooth (that glitters with the bump map)
	road_mat.roughness = lerpf(0.82, 0.34, surf_wet)
	road_mat.metallic_specular = lerpf(0.5, 0.7, surf_wet)
	Gfx.set_albedo(road_mat, Color.WHITE.lerp(Color(0.6, 0.61, 0.64), surf_wet))
	road_mat.normal_scale = lerpf(0.6, 0.15, surf_wet)
	road_mat.clearcoat_enabled = surf_wet > 0.3
	road_mat.clearcoat = 0.6
	road_mat.clearcoat_roughness = 0.25

var hills := FastNoiseLite.new()
var hills2 := FastNoiseLite.new()

# distance grid around the road
var G_MIN := Vector2(-520, -480)
const G_CELL := 2.5
const G_RADIUS := 40.0
var gw := 0
var gh := 0
var g_dist := PackedFloat32Array()
var g_rh := PackedFloat32Array()
var g_px := PackedFloat32Array()     # nearest road point (for maps that need it)
var g_pz := PackedFloat32Array()

# terrain extents
const T_MIN := Vector2(-700, -680)
const T_MAX := Vector2(700, 720)

func build() -> void:
	hills.seed = 7
	hills.frequency = 0.0035
	hills.fractal_octaves = 3
	hills2.seed = 99
	hills2.frequency = 0.02
	_sample_curve()
	_build_grid()
	if biome.get("sea", false):
		_setup_sea()
	_build_road_mesh()
	_build_terrain()
	_build_start_gantry()

# ---------------------------------------------------------------- beach: sea outside the loop
# The Beach biome puts the ocean all round the outside of the circuit: the
# ground outside the loop slopes from the road down to a beach and under the
# water (a longer slope where the road is high up), while the land inside the
# loop is kept above the water. "Outside" = reachable from the edge of the map
# without crossing the road (a flood fill on the road-distance grid).
const Sea = preload("res://scripts/sea.gd")
var sea := false
var sea_y := -1e9            # water level (grass and trees stay above it)
var g_out := PackedByteArray()   # 1 = grid cell outside the loop
var g_od := PackedFloat32Array()    # outside the loop: distance to the road
var g_orh := PackedFloat32Array()   # ... and that road's height

func _setup_sea() -> void:
	sea = true
	var lo := 1e9
	for p in pts:
		lo = min(lo, (p as Vector3).y)
	sea_y = lo - 2.4
	g_out.resize(gw * gh)
	g_out.fill(0)
	# a thick wall (38 m round the road) so the fill can't run into the gaps
	# between stacked switchback tiers - those count as land, not sea (it used
	# to lower the ground between them into a steep wall under the upper tier)
	var wall := 38.0
	var queue := PackedInt32Array()
	for gx in gw:
		for gz in [0, gh - 1]:
			queue.append(gz * gw + gx)
	for gz in gh:
		for gx in [0, gw - 1]:
			queue.append(gz * gw + gx)
	var qi := 0
	while qi < queue.size():
		var id := queue[qi]
		qi += 1
		if g_out[id] == 1 or g_dist[id] < wall:
			continue
		g_out[id] = 1
		var gx2 := id % gw
		var gz2 := id / gw
		if gx2 > 0: queue.append(id - 1)
		if gx2 < gw - 1: queue.append(id + 1)
		if gz2 > 0: queue.append(id - gw)
		if gz2 < gh - 1: queue.append(id + gw)
	# then grow the sea side back into that band towards the road, but only as far
	# as the band reaches from the real outside: right up to the outer edge of the
	# road, while a narrow gap between two tiers stays land
	var grow := PackedInt32Array()
	var gd := PackedFloat32Array()
	gd.resize(gw * gh)
	gd.fill(1e9)
	for id in gw * gh:
		if g_out[id] == 1:
			gd[id] = 0.0
			grow.append(id)
	var gi := 0
	while gi < grow.size():
		var id := grow[gi]
		gi += 1
		var gx4 := id % gw
		var gz4 := id / gw
		for nb in [id - 1 if gx4 > 0 else -1, id + 1 if gx4 < gw - 1 else -1, id - gw if gz4 > 0 else -1, id + gw if gz4 < gh - 1 else -1]:
			var j: int = nb
			if j < 0 or g_out[j] == 1 or g_dist[j] < HALF_W + 1.5:
				continue
			var nd := gd[id] + G_CELL
			# only cells you reach by heading straight in towards the road
			if nd < gd[j] and nd <= wall - g_dist[j] + G_CELL * 2.0:
				gd[j] = nd
				g_out[j] = 1
				grow.append(j)
	# distance from the road (and that road's height) for every cell outside the
	# loop: the road grid only knows them within ~50 m, and past that the
	# ground used to drop straight to the seabed in a sheer cliff
	g_od.resize(gw * gh)
	g_orh.resize(gw * gh)
	g_od.fill(1e9)
	var front := PackedInt32Array()
	for id in gw * gh:
		if g_out[id] == 1 and g_dist[id] < 1e8:
			g_od[id] = g_dist[id]
			g_orh[id] = g_rh[id]
			front.append(id)
	var fi := 0
	while fi < front.size():
		var id := front[fi]
		fi += 1
		var gx3 := id % gw
		var gz3 := id / gw
		for nb in [id - 1 if gx3 > 0 else -1, id + 1 if gx3 < gw - 1 else -1, id - gw if gz3 > 0 else -1, id + gw if gz3 < gh - 1 else -1]:
			var j: int = nb
			if j < 0 or g_out[j] != 1:
				continue
			var nd := g_od[id] + G_CELL
			if nd < g_od[j] - 0.01:
				g_od[j] = nd
				g_orh[j] = g_orh[id]
				front.append(j)
	var s := Sea.new()
	s.name = "Sea"
	add_child(s)
	s.setup(sea_y)

func _outside(x: float, z: float) -> bool:
	var ix := int(round((x - G_MIN.x) / G_CELL))
	var iz := int(round((z - G_MIN.y) / G_CELL))
	if ix < 0 or iz < 0 or ix >= gw or iz >= gh:
		return true   # beyond the road grid: well outside the loop
	return g_out[iz * gw + ix] == 1

# the ground height h at (x, z) reshaped for the sea
func _sea_shape(x: float, z: float, h: float) -> float:
	if not _outside(x, z):
		return max(h, sea_y + 0.6)
	var d := 1e9
	var rh := h
	var ix := int(round((x - G_MIN.x) / G_CELL))
	var iz := int(round((z - G_MIN.y) / G_CELL))
	if ix >= 0 and iz >= 0 and ix < gw and iz < gh:
		d = g_od[iz * gw + ix]
		rh = g_orh[iz * gw + ix] if d < 1e8 else h
	var s0 := HALF_W + 2.0
	if d <= s0:
		return h
	# beach width, longer where the road is high up (a sloping bank, not a cliff)
	var s1: float = s0 + clampf((rh - sea_y) * 3.0, float(biome.get("sea_start", 28.0)) - s0, 180.0)
	if d <= s1:   # beach (a sloping bank where the road is high)
		return lerpf(min(h, rh - 0.15), sea_y + 0.25, sstep(s0, s1, d))
	return lerpf(sea_y + 0.25, sea_y - 6.0, sstep(s1, s1 + 50.0, d)) + base_hill(x, z) * 0.04

# ---------------------------------------------------------------- curve
static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func base_hill(x: float, z: float) -> float:
	return hills.get_noise_2d(x, z) * 16.0 + hills2.get_noise_2d(x, z) * 1.5

func _sample_curve() -> void:
	var dense: Array[Vector2] = []
	var n := ctrl.size()
	for i in n:
		var p0: Vector2 = ctrl[(i - 1 + n) % n]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n]
		for k in 80:
			dense.append(_cr(p0, p1, p2, p3, k / 80.0))
	# resample at equal arc length
	var res: Array[Vector2] = [dense[0]]
	var acc := 0.0
	for i in range(1, dense.size() + 1):
		var a: Vector2 = dense[i - 1]
		var b: Vector2 = dense[i % dense.size()]
		var seg := a.distance_to(b)
		while acc + seg >= STEP:
			var t := (STEP - acc) / seg
			a = a.lerp(b, t)
			res.append(a)
			seg = a.distance_to(b)
			acc = 0.0
		acc += seg
	if res[res.size() - 1].distance_to(res[0]) < STEP * 0.5:
		res.pop_back()
	var cnt := res.size()
	total_len = cnt * STEP
	# smoothed elevation
	var h := PackedFloat32Array()
	h.resize(cnt)
	for i in cnt:
		h[i] = base_hill(res[i].x, res[i].y)
	for pass_i in 3:
		var h2 := PackedFloat32Array()
		h2.resize(cnt)
		var win := smooth_win
		for i in cnt:
			var s := 0.0
			for k in range(-win, win + 1):
				s += h[(i + k + cnt) % cnt]
			h2[i] = s / (2 * win + 1)
		h = h2
	# jump crests on the three straightest stretches (away from the start line)
	var turn := PackedFloat32Array()
	turn.resize(cnt)
	for i in cnt:
		var a: Vector2 = res[(i - 12 + cnt) % cnt]
		var b: Vector2 = res[i]
		var c: Vector2 = res[(i + 12) % cnt]
		turn[i] = abs((b - a).angle_to(c - b))
	var centres: Array[int] = []
	for k in crest_count:
		var best := -1
		var bv := 1e9
		for i in range(60, cnt - 60):
			var ok := true
			for cc in centres:
				if abs(i - cc) < 220:
					ok = false
					break
			if ok and turn[i] < bv:
				bv = turn[i]
				best = i
		if best >= 0:
			centres.append(best)
	bump_centres = centres
	for cc in centres:
		var half := 18
		for k in range(-half, half + 1):
			var u := float(k + half) / float(2 * half)
			var idx := (cc + k + cnt) % cnt
			h[idx] += 3.6 * 0.5 * (1.0 - cos(u * TAU))
	pts.resize(cnt)
	tans.resize(cnt)
	curv.resize(cnt)
	for i in cnt:
		pts[i] = Vector3(res[i].x, h[i], res[i].y)
	for i in cnt:
		var a: Vector3 = pts[(i - 1 + cnt) % cnt]
		var b: Vector3 = pts[(i + 1) % cnt]
		var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		tans[i] = t
	for i in cnt:
		var ta: Vector3 = tans[(i - 2 + cnt) % cnt]
		var tb: Vector3 = tans[(i + 2) % cnt]
		var cr := ta.x * tb.z - ta.z * tb.x
		curv[i] = cr / (4.0 * STEP)

# ---------------------------------------------------------------- distance grid
func _build_grid() -> void:
	gw = int((-G_MIN.x * 2.0) / G_CELL) + 1
	gh = int((-G_MIN.y * 2.0) / G_CELL) + 1
	g_dist.resize(gw * gh)
	g_rh.resize(gw * gh)
	g_px.resize(gw * gh)
	g_pz.resize(gw * gh)
	g_dist.fill(1e9)
	g_rh.fill(0.0)
	var cnt := pts.size()
	var rc := int(ceil(G_RADIUS / G_CELL))
	for i in cnt:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % cnt]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var len2 := abx * abx + abz * abz
		var cx := int((a.x - G_MIN.x) / G_CELL)
		var cz := int((a.z - G_MIN.y) / G_CELL)
		for gz in range(max(cz - rc, 0), min(cz + rc + 2, gh)):
			var wz := G_MIN.y + gz * G_CELL
			for gx in range(max(cx - rc, 0), min(cx + rc + 2, gw)):
				var wx := G_MIN.x + gx * G_CELL
				var t := clampf(((wx - a.x) * abx + (wz - a.z) * abz) / len2, 0.0, 1.0)
				var px := a.x + abx * t - wx
				var pz := a.z + abz * t - wz
				var d := sqrt(px * px + pz * pz)
				var idx := gz * gw + gx
				if d < g_dist[idx]:
					g_dist[idx] = d
					g_rh[idx] = lerpf(a.y, b.y, t)
					g_px[idx] = a.x + abx * t
					g_pz[idx] = a.z + abz * t

func _grid_sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := (x - G_MIN.x) / G_CELL
	var fz := (z - G_MIN.y) / G_CELL
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	if ix < 0 or iz < 0 or ix >= gw - 1 or iz >= gh - 1:
		return 1e9
	var tx := fx - ix
	var tz := fz - iz
	var i0 := iz * gw + ix
	var a := lerpf(arr[i0], arr[i0 + 1], tx)
	var b := lerpf(arr[i0 + gw], arr[i0 + gw + 1], tx)
	return lerpf(a, b, tz)

func road_dist(x: float, z: float) -> float:
	return _grid_sample(g_dist, x, z)

func road_h(x: float, z: float) -> float:
	var fx := (x - G_MIN.x) / G_CELL
	var fz := (z - G_MIN.y) / G_CELL
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	if ix < 0 or iz < 0 or ix >= gw - 1 or iz >= gh - 1:
		return 0.0
	# weight only cells that actually have road data
	var tx := fx - ix
	var tz := fz - iz
	var s := 0.0
	var ws := 0.0
	var ids := [iz * gw + ix, iz * gw + ix + 1, (iz + 1) * gw + ix, (iz + 1) * gw + ix + 1]
	var wts := [(1 - tx) * (1 - tz), tx * (1 - tz), (1 - tx) * tz, tx * tz]
	for k in 4:
		var id: int = ids[k]
		if g_dist[id] < 1e8:
			s += g_rh[id] * wts[k]
			ws += wts[k]
	return s / ws if ws > 0.0 else 0.0

static func sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func terrain_h(x: float, z: float) -> float:
	var d := road_dist(x, z)
	# biome ground shape (dunes, rocks) away from the road
	var base := base_hill(x, z) + Biome.extra_height(biome, x, z, d)
	if d > G_RADIUS - 1.0:
		return base
	var rh := road_h(x, z)
	var t := sstep(HALF_W + 1.0, HALF_W + blend_far, d)
	return lerpf(rh - 0.15, base, t)

# height the car drives on: the road, or the ground exactly as it's drawn (the
# terrain mesh is 5 m triangles, so the smooth formula could be a metre off on
# dunes and lumps - you'd float above it or sink into it)
func ground_h(x: float, z: float) -> float:
	var d := road_dist(x, z)
	if d < HALF_W:
		return road_h(x, z) + 0.04
	if d < HALF_W + 1.4:
		# gravel shoulder sloping gently down into the terrain (matches the mesh)
		var sh := road_h(x, z) + 0.04 - 0.26 * (d - HALF_W) / 1.4
		return max(sh, surface_h(x, z))
	return surface_h(x, z)

func nearest_index(p: Vector3, hint: int, search := 40) -> int:
	var cnt := pts.size()
	var best := hint
	var bd := 1e18
	if hint < 0:
		for i in cnt:
			var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
			if d < bd:
				bd = d
				best = i
		return best
	for k in range(-search, search + 1):
		var i := (hint + k + cnt) % cnt
		var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best

# ---------------------------------------------------------------- road mesh
func _noise_tex(freq: float, as_normal := false, size := 512, ramp: Gradient = null) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = freq
	fn.fractal_octaves = 5
	nt.noise = fn
	nt.width = size
	nt.height = size
	nt.seamless = true
	nt.as_normal_map = as_normal
	if as_normal:
		nt.bump_strength = 4.0
	if ramp:
		nt.color_ramp = ramp
	return nt

func _build_road_mesh() -> void:
	var mb := MB.new()
	var cnt := pts.size()
	var dist_acc := 0.0
	for i in cnt:
		var j := (i + 1) % cnt
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[j]
		var ta: Vector3 = tans[i]
		var tb: Vector3 = tans[j]
		var la := Vector3(-ta.z, 0, ta.x)  # left
		var lb := Vector3(-tb.z, 0, tb.x)
		var v0 := dist_acc / 12.0
		var v1 := (dist_acc + STEP) / 12.0
		var up := Vector3.UP
		var ya := a.y + 0.04
		var yb := b.y + 0.04
		var A := Vector3(a.x, ya, a.z)
		var B := Vector3(b.x, yb, b.z)
		# asphalt
		mb.quad("road", A + la * HALF_W, A - la * HALF_W, B - lb * HALF_W, B + lb * HALF_W, up, up, up, up, Color.WHITE,
			Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1))
		# gravel shoulders sloping into the terrain
		for sd in [1.0, -1.0]:
			var oa: Vector3 = la * sd
			var ob: Vector3 = lb * sd
			var na := (Vector3.UP + oa * 0.3).normalized()
			mb.quad("shoulder", A + oa * HALF_W, A + oa * (HALF_W + 1.4) - Vector3(0, 0.22, 0),
				B + ob * (HALF_W + 1.4) - Vector3(0, 0.22, 0), B + ob * HALF_W, na, na, na, na, Color.WHITE,
				Vector2(0, v0 * 3), Vector2(0.3, v0 * 3), Vector2(0.3, v1 * 3), Vector2(0, v1 * 3))
			# solid white edge lines
			var lw := 0.18
			var e0 := HALF_W - 0.45
			mb.quad("line", A + oa * e0 + up * 0.01, A + oa * (e0 + lw) + up * 0.01, B + ob * (e0 + lw) + up * 0.01, B + ob * e0 + up * 0.01, up, up, up, up)
		dist_acc += STEP
	# start / finish checker strip
	var p0: Vector3 = pts[0]
	var t0: Vector3 = tans[0]
	var l0 := Vector3(-t0.z, 0, t0.x)
	var y := p0.y + 0.055
	var rows := 2
	var cols := 10
	for r in rows:
		for c in cols:
			var col := Color.WHITE if (r + c) % 2 == 0 else Color(0.05, 0.05, 0.05)
			var a0 := Vector3(p0.x, y, p0.z) + l0 * lerpf(HALF_W, -HALF_W, float(c) / cols) + t0 * (r * 1.0)
			var a1 := Vector3(p0.x, y, p0.z) + l0 * lerpf(HALF_W, -HALF_W, float(c + 1) / cols) + t0 * (r * 1.0)
			mb.quad("kerb", a0, a1, a1 + t0, a0 + t0, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, col)

	var g := Gradient.new()
	g.set_color(0, Color(0.11, 0.11, 0.115))
	g.set_color(1, Color(0.26, 0.26, 0.27))
	road_mat = StandardMaterial3D.new()
	road_mat.albedo_texture = _noise_tex(0.08, false, 512, g)
	road_mat.normal_enabled = true
	road_mat.normal_texture = _noise_tex(0.15, true)
	road_mat.normal_scale = 0.6
	road_mat.roughness = 0.82
	road_mat.uv1_scale = Vector3(2.5, 1.0, 1.0)
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.20, 0.18, 0.15))
	g2.set_color(1, Color(0.42, 0.38, 0.32))
	var sh_mat := StandardMaterial3D.new()
	sh_mat.albedo_texture = _noise_tex(0.25, false, 256, g2)
	sh_mat.roughness = 1.0
	sh_mat.albedo_color = biome.get("shoulder", Color.WHITE)   # sandy / red-earth shoulders
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.86, 0.86, 0.82)
	line_mat.roughness = 0.6
	if float(biome.get("line_glow", 0.0)) > 0.0:   # neon road lines (biome)
		line_mat.emission_enabled = true
		line_mat.emission = biome.get("glow_col", Color.WHITE)
		line_mat.emission_energy_multiplier = float(biome["line_glow"])
	var kerb_mat := StandardMaterial3D.new()
	kerb_mat.vertex_color_use_as_albedo = true
	kerb_mat.roughness = 0.55
	# Low detail: smooth flat asphalt / gravel; baked lighting: drawn unshaded
	Gfx.surface(road_mat, Color(0.185, 0.185, 0.19))
	Gfx.surface(sh_mat, Color(0.31, 0.28, 0.235))
	Gfx.surface(line_mat)
	Gfx.surface(kerb_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build({"road": road_mat, "shoulder": sh_mat, "line": line_mat, "kerb": kerb_mat})
	mi.name = "Road"
	add_child(mi)

# ---------------------------------------------------------------- terrain
var t_h := PackedFloat32Array()   # rendered terrain vertex heights
var t_step := 5.0
var t_nx := 0
var t_nz := 0

# height of the terrain mesh exactly as drawn (same triangles as _build_terrain),
# so things placed on the ground sit on it instead of floating or sinking
func surface_h(x: float, z: float) -> float:
	var fx := (x - T_MIN.x) / t_step
	var fz := (z - T_MIN.y) / t_step
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	if t_h.is_empty() or ix < 0 or iz < 0 or ix >= t_nx - 1 or iz >= t_nz - 1:
		return terrain_h(x, z)
	fx -= ix
	fz -= iz
	var a := iz * t_nx + ix
	var ha := t_h[a]
	var hb := t_h[a + 1]
	var hc := t_h[a + t_nx]
	var hd := t_h[a + t_nx + 1]
	if fx + fz <= 1.0:
		return ha + (hb - ha) * fx + (hc - ha) * fz
	return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)

func _build_terrain() -> void:
	var step := 2.5   # was 5 m: dunes and lumps looked blocky
	var nx := int((T_MAX.x - T_MIN.x) / step) + 1
	var nz := int((T_MAX.y - T_MIN.y) / step) + 1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	cols.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var x := T_MIN.x + ix * step
			var z := T_MIN.y + iz * step
			var h := terrain_h(x, z)
			var d := road_dist(x, z)
			if sea:
				h = _sea_shape(x, z, h)
			verts[iz * nx + ix] = Vector3(x, h, z)
			cols[iz * nx + ix] = Color(clampf((d - HALF_W) / 10.0, 0.0, 1.0), 1, 1)
	var norms := PackedVector3Array()
	norms.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var hl: float = verts[iz * nx + max(ix - 1, 0)].y
			var hr: float = verts[iz * nx + min(ix + 1, nx - 1)].y
			var hd: float = verts[max(iz - 1, 0) * nx + ix].y
			var hu: float = verts[min(iz + 1, nz - 1) * nx + ix].y
			norms[iz * nx + ix] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			if Gfx.baked:   # baked light in the green channel (tree shadows added by bake_shadows)
				var bc: Color = cols[iz * nx + ix]
				bc.g = Gfx.light_at(norms[iz * nx + ix]) / Gfx.TERRAIN_SCALE
				cols[iz * nx + ix] = bc
	# keep the vertex heights so surface_h() can return the exact rendered ground
	t_step = step
	t_nx = nx
	t_nz = nz
	t_h.resize(nx * nz)
	for i in nx * nz:
		t_h[i] = verts[i].y
	var idx := PackedInt32Array()
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			# clockwise when seen from above
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sh := Shader.new()
	sh.code = Gfx.shader_code(Biome.TERRAIN_SHADER)   # shared ground shader (biome colours)
	var mat := ShaderMaterial.new()
	terrain_mat = mat
	mat.shader = sh
	mat.set_shader_parameter("noise_a", _noise_tex(0.01, false, 256))
	mat.set_shader_parameter("noise_b", _noise_tex(0.04, false, 512))
	mat.set_shader_parameter("detail_n", _noise_tex(0.08, true, 512))
	Biome.apply_terrain(mat, biome)
	mesh.surface_set_material(0, mat)
	t_mesh = mesh
	t_arrays = arrays
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Terrain"
	add_child(mi)

var t_mesh: ArrayMesh
var t_arrays := []

# Baked lighting: soft tree shadows on the ground. Each tree (x, z, r) darkens
# the ground where its crown blocks the baked sun, plus a little contact shade
# right around the trunk. Done once after the forest is planted.
func bake_shadows(trees: Array) -> void:
	if t_mesh == null or t_arrays.is_empty():
		return
	var sun := Gfx.BAKE_SUN.normalized()
	var crown_h := 6.0
	var off := -Vector2(sun.x, sun.z) / sun.y * crown_h   # where the crown's shadow lands
	var sh := PackedFloat32Array()
	var ao := PackedFloat32Array()
	sh.resize(t_nx * t_nz)
	ao.resize(t_nx * t_nz)
	sh.fill(1.0)
	ao.fill(1.0)
	var R := 4.5
	for t in trees:
		var tv: Vector3 = t
		for pass_i in 2:
			var c := Vector2(tv.x, tv.y) + (off if pass_i == 0 else Vector2.ZERO)
			var rad := R if pass_i == 0 else 3.0
			var ix0 := int(floor((c.x - rad - T_MIN.x) / t_step))
			var iz0 := int(floor((c.y - rad - T_MIN.y) / t_step))
			var ix1 := int(ceil((c.x + rad - T_MIN.x) / t_step))
			var iz1 := int(ceil((c.y + rad - T_MIN.y) / t_step))
			for iz in range(max(iz0, 0), min(iz1 + 1, t_nz)):
				for ix in range(max(ix0, 0), min(ix1 + 1, t_nx)):
					var p := Vector2(T_MIN.x + ix * t_step, T_MIN.y + iz * t_step)
					var f := 1.0 - smoothstep(rad * 0.35, rad, p.distance_to(c))
					if f <= 0.0:
						continue
					var i := iz * t_nx + ix
					if pass_i == 0:
						sh[i] *= 1.0 - 0.55 * f
					else:
						ao[i] *= 1.0 - 0.3 * f
	var cols: PackedColorArray = t_arrays[Mesh.ARRAY_COLOR]
	var norms: PackedVector3Array = t_arrays[Mesh.ARRAY_NORMAL]
	for i in cols.size():
		var bc: Color = cols[i]
		bc.g = Gfx.light_at(norms[i], maxf(ao[i], 0.5), maxf(sh[i], 0.2)) / Gfx.TERRAIN_SCALE
		cols[i] = bc
	t_arrays[Mesh.ARRAY_COLOR] = cols
	var mat := t_mesh.surface_get_material(0)
	t_mesh.clear_surfaces()
	t_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, t_arrays)
	t_mesh.surface_set_material(0, mat)

# ---------------------------------------------------------------- start gantry
func _build_start_gantry() -> void:
	var p0: Vector3 = pts[0]
	var t0: Vector3 = tans[0]
	var l0 := Vector3(-t0.z, 0, t0.x)
	var mb := MB.new()
	var base := Vector3(p0.x, p0.y, p0.z)
	for sd in [1.0, -1.0]:
		var c: Vector3 = base + l0 * (HALF_W + 1.6) * sd
		mb.box("metal", Transform3D(Basis(), c + Vector3(0, 3.2, 0)), Vector3(0.35, 6.4, 0.35))
	var basis := Basis.looking_at(t0, Vector3.UP)
	mb.box("metal", Transform3D(basis, base + Vector3(0, 6.2, 0)), Vector3((HALF_W + 1.8) * 2.0, 0.5, 0.4))
	mb.box("banner", Transform3D(basis, base + Vector3(0, 5.3, 0)), Vector3(HALF_W * 1.6, 1.3, 0.12))
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.56, 0.58)
	metal.metallic = 0.8
	metal.roughness = 0.35
	var banner := StandardMaterial3D.new()
	banner.albedo_color = Color(0.08, 0.08, 0.1)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build({"metal": metal, "banner": banner})
	add_child(mi)
	for sd in [1.0, -1.0]:
		var lbl := Label3D.new()
		lbl.text = gantry_text
		lbl.font_size = 160
		lbl.outline_size = 0
		lbl.pixel_size = 0.0065
		lbl.modulate = Color(1.0, 0.55, 0.15)
		lbl.shaded = false
		var bb := Basis.looking_at(t0 * sd, Vector3.UP)
		lbl.transform = Transform3D(bb, base + Vector3(0, 5.3, 0) - t0 * 0.08 * sd)
		lbl.double_sided = false
		add_child(lbl)

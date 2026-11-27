# Endless forest road: a never-ending single-lane road that drives like a real
# country road - long, slight bends, long gradual hills, now and then a straight,
# and only very rarely a sharp bend. Road, terrain and trees are generated in
# 200 m chunks ahead of the car and unloaded behind it. Exposes the same queries
# as track.gd.
extends Node3D

const MB = preload("res://scripts/mb.gd")
const Biome = preload("res://scripts/biome.gd")
const Gfx = preload("res://scripts/gfx.gd")
const Sea = preload("res://scripts/sea.gd")

# cosmetic biome (set by main before build); see biome.gd
var biome: Dictionary = Biome.get_biome("Forest")

const HALF_W := 5.25
const STEP := 2.0
const CHUNK_N := 100          # samples per chunk (200 m)
const AHEAD := 6              # chunks kept ahead of the car (~1.2 km)
const BEHIND := 2
const G_RADIUS := 40.0
const HC := 16.0              # spatial hash cell for road samples

var endless := true
var T_MIN := Vector2(-1e7, -1e7)
var T_MAX := Vector2(1e7, 1e7)

var pts := PackedVector3Array()
var tans := PackedVector3Array()
var curv := PackedFloat32Array()
var total_len := 0.0
var hint_idx := 0

var hills := FastNoiseLite.new()
var hills2 := FastNoiseLite.new()
var elev := FastNoiseLite.new()
var elev2 := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()

# generator state
var gen_pos := Vector2.ZERO
var gen_heading := 0.0
var gen_k := 0.0
var gen_k_target := 0.0
var gen_k_rate := 0.00008     # how fast the curvature eases in and out
var gen_next_change := 0.0

var hash := {}
var chunks := {}               # chunk index -> Node3D
var forest

var road_mat: StandardMaterial3D
var sh_mat: StandardMaterial3D
var line_mat: StandardMaterial3D
var terrain_mat: ShaderMaterial

# ---- beach biome: the sea along the left side of the road. One flat water
# surface that follows the camera, so the ocean runs on without a break to the
# horizon; the ground on that side slopes from the beach down under it.
var sea := false
var sea_y := -1e9            # water level (grass and trees stay above it)
var sea_mi             # sea.gd

func _make_sea() -> void:
	sea_mi = Sea.new()
	sea_mi.name = "Sea"
	add_child(sea_mi)
	sea_mi.setup(sea_y)
var surf_wet := 0.0
var grass_mat: ShaderMaterial    # set by the grass system so snow can frost it

func build() -> void:
	hills.seed = 7
	hills.frequency = 0.0035
	hills.fractal_octaves = 3
	hills2.seed = 99
	hills2.frequency = 0.02
	# road elevation: long rolling hills (~1 km apart) with a gentle ripple on top
	elev.seed = 3
	elev.frequency = 0.0011
	elev.fractal_octaves = 1
	elev2.seed = 11
	elev2.frequency = 0.0035
	elev2.fractal_octaves = 1
	rng.seed = 12345
	sea = bool(biome.get("sea", false))
	if sea:
		sea_y = float(biome.get("sea_y", -2.4))
		_make_sea()
	_make_materials()
	_generate_until(CHUNK_N * (AHEAD + 6) + 2)

func set_forest(f) -> void:
	forest = f
	for c in AHEAD + 1:
		_build_chunk(c)

# ---------------------------------------------------------------- generation
func _generate_until(n: int) -> void:
	while pts.size() < n:
		var dist := pts.size() * STEP
		if dist >= gen_next_change:
			var r := rng.randf()
			# steer back towards the overall direction so the road keeps heading on
			var sgn := 1.0 if rng.randf() < 0.5 - clampf(gen_heading, -1.0, 1.0) * 0.45 else -1.0
			var seg := rng.randf_range(220.0, 480.0)
			if r < 0.28:
				# a straight
				gen_k_target = 0.0
				gen_k_rate = 0.00008
			elif r < 0.31:
				# rare sharp bend: 60-110 m radius, at most ~80 degrees, eased in quickly
				var k := rng.randf_range(1.0 / 110.0, 1.0 / 60.0)
				gen_k_target = k * sgn
				gen_k_rate = 0.0006
				seg = min(rng.randf_range(60.0, 120.0), 1.4 / k)
			else:
				# long, slight bend: 500-1400 m radius
				gen_k_target = rng.randf_range(1.0 / 1400.0, 1.0 / 500.0) * sgn
				gen_k_rate = 0.00006
			gen_next_change = dist + seg
		gen_k = move_toward(gen_k, gen_k_target, gen_k_rate * STEP)
		var d := Vector2(-sin(gen_heading), -cos(gen_heading))
		# long gradual hills: about +-18 m over ~1 km, grades of a few percent
		var hk := float(biome.get("road_hills", 1.0))   # beach: the road stays near sea level
		var h := (elev.get_noise_1d(dist) * 18.0 + elev2.get_noise_1d(dist) * 3.0) * hk
		var i := pts.size()
		pts.append(Vector3(gen_pos.x, h, gen_pos.y))
		tans.append(Vector3(d.x, 0, d.y))
		curv.append(gen_k)
		var key := Vector2i(int(floor(gen_pos.x / HC)), int(floor(gen_pos.y / HC)))
		if not hash.has(key):
			hash[key] = []
		hash[key].append(i)
		gen_heading += gen_k * STEP
		gen_pos += d * STEP
	total_len = pts.size() * STEP

# ---------------------------------------------------------------- streaming
func update_stream(car_idx: int) -> void:
	var cc := car_idx / CHUNK_N
	# the road is laid out ~1 km past the last built chunk, so a chunk's terrain
	# already knows about road that will loop back near it later
	_generate_until(CHUNK_N * (cc + AHEAD + 6) + 2)
	# build at most one new chunk per frame to avoid hitches
	for c in range(max(cc - BEHIND, 0), cc + AHEAD + 1):
		if not chunks.has(c):
			_build_chunk(c)
			break
	for c in chunks.keys():
		var ci: int = c
		if ci < cc - BEHIND:
			_free_chunk(ci)

func _free_chunk(c: int) -> void:
	var node: Node3D = chunks[c]
	var aabb_min := Vector2(1e9, 1e9)
	var aabb_max := Vector2(-1e9, -1e9)
	for i in range(c * CHUNK_N, min((c + 1) * CHUNK_N + 1, pts.size())):
		aabb_min.x = min(aabb_min.x, pts[i].x)
		aabb_min.y = min(aabb_min.y, pts[i].z)
		aabb_max.x = max(aabb_max.x, pts[i].x)
		aabb_max.y = max(aabb_max.y, pts[i].z)
	node.queue_free()
	chunks.erase(c)

# ---------------------------------------------------------------- queries
static func sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func base_hill(x: float, z: float) -> float:
	return hills.get_noise_2d(x, z) * 16.0 + hills2.get_noise_2d(x, z) * 1.5

func _seg(i: int, x: float, z: float) -> Vector2:
	# distance to segment i..i+1 and the road height there
	var a: Vector3 = pts[i]
	var b: Vector3 = pts[min(i + 1, pts.size() - 1)]
	var abx := b.x - a.x
	var abz := b.z - a.z
	var len2 := abx * abx + abz * abz
	var t := 0.0
	if len2 > 1e-6:
		t = clampf(((x - a.x) * abx + (z - a.z) * abz) / len2, 0.0, 1.0)
	var px := a.x + abx * t - x
	var pz := a.z + abz * t - z
	return Vector2(sqrt(px * px + pz * pz), lerpf(a.y, b.y, t))

func _d2(i: int, x: float, z: float) -> float:
	var p: Vector3 = pts[i]
	return (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)

# cap: callers that only compare the distance with a small threshold pass it,
# so the search stops at that distance (the result is then only exact below cap)
func _nearest(x: float, z: float, cap := INF) -> Vector2:
	var best := Vector2(1e9, 0.0)
	# fast path: walk from the car's road position to the closest sample (a few
	# steps for points around the car), then check the two segments either side
	var w := _walk(x, z)
	for j in [w - 1, w]:
		var r := _seg(j, x, z)
		if r.x < best.x:
			best = r
	# only trust the shortcut on or right beside that stretch of road: further out,
	# another part of a winding road can be closer (that put grass on the road)
	if best.x < HALF_W + 2.25:
		return best
	# Search the spatial hash, but only the cells that could hold a closer piece
	# of road: within the distance already found (plus a segment length), never
	# more than 3 cells out. Searching all 7x7 cells every time made each
	# off-road ground query ~30x slower, and the car makes ~100 a tick: the
	# frame rate fell from 120 to under 10 as soon as you left the road.
	var reach := minf(best.x, cap) + STEP * 1.5
	var reach2 := reach * reach
	var cx := int(floor(x / HC))
	var cz := int(floor(z / HC))
	for kz in range(maxi(int(floor((z - reach) / HC)), cz - 3), mini(int(floor((z + reach) / HC)), cz + 3) + 1):
		for kx in range(maxi(int(floor((x - reach) / HC)), cx - 3), mini(int(floor((x + reach) / HC)), cx + 3) + 1):
			var cell = hash.get(Vector2i(kx, kz))
			if cell == null:
				continue
			for i in cell:
				if _d2(i, x, z) > reach2:
					continue
				var r := _seg(i, x, z)
				if r.x < best.x:
					best = r
					reach = minf(best.x, cap) + STEP * 1.5
					reach2 = reach * reach
	return best

# closest road sample reached by walking from the car's position along the road
func _walk(x: float, z: float) -> int:
	var n := pts.size()
	var w := clampi(hint_idx, 1, n - 2)
	var dw := _d2(w, x, z)
	var steps := 0
	while steps < 60 and w < n - 2 and _d2(w + 1, x, z) < dw:
		w += 1
		dw = _d2(w, x, z)
		steps += 1
	while steps < 60 and w > 1 and _d2(w - 1, x, z) < dw:
		w -= 1
		dw = _d2(w, x, z)
		steps += 1
	return w

func road_dist(x: float, z: float) -> float:
	return _nearest(x, z).x

# nearest road sample: the one reached by walking along the road from the car,
# or a closer one in the spatial hash (only the cells that could hold one are
# searched, same reason as in _nearest)
func _nearest_index_hash(x: float, z: float) -> int:
	var cx := int(floor(x / HC))
	var cz := int(floor(z / HC))
	var best := -1
	var bd := 1e18
	# start from the sample reached by walking along the road from the car. The
	# hash only covers ~50 m around the point, but the ground strip reaches up
	# to 310 m from the road: further out the lookup used to find nothing and
	# fall back to plain hills without the dunes, 2-3 m below the sand that's
	# drawn, so the car sank into the desert.
	var w := _walk(x, z)
	best = w
	bd = _d2(w, x, z)
	var reach := minf(sqrt(bd), HC * 4.0)
	for kz in range(maxi(int(floor((z - reach) / HC)), cz - 3), mini(int(floor((z + reach) / HC)), cz + 3) + 1):
		for kx in range(maxi(int(floor((x - reach) / HC)), cx - 3), mini(int(floor((x + reach) / HC)), cx + 3) + 1):
			var cell = hash.get(Vector2i(kx, kz))
			if cell == null:
				continue
			for i in cell:
				var d := _d2(i, x, z)
				if d < bd:
					bd = d
					best = i
	return best

# height of the terrain ribbon exactly as drawn: rows every 2 samples, columns at
# the OFFS distances either side of the road, straight lines in between
#
# Works on the real mesh: finds the quad of the strip the point is in (rows r0,
# r1 and columns k, k+1, built exactly like _build_chunk builds them, clipping
# included) and returns the height of the triangle it's on. Each quad is drawn
# as two triangles split along its B-C diagonal.
func surface_h(x: float, z: float) -> float:
	var i := _nearest_index_hash(x, z)
	if i < 0:
		return base_hill(x, z)
	var n := pts.size()
	var r0 := clampi((i / 2) * 2, 0, n - 3)
	# the point may be just behind row r0: then it's in the previous quad row
	var u := _row_u(r0, x, z)
	if u < 0.0 and r0 >= 2:
		r0 -= 2
		u = _row_u(r0, x, z)
	var r1 := mini(r0 + 2, n - 1)
	u = clampf(u, 0.0, 1.0)
	var l0 := Vector3(-tans[r0].z, 0, tans[r0].x)
	var l1 := Vector3(-tans[r1].z, 0, tans[r1].x)
	var pu: Vector3 = (pts[r0] as Vector3).lerp(pts[r1], u)
	var o := Vector3(x - pu.x, 0, z - pu.z).dot(l0.lerp(l1, u).normalized())
	var cols := OFFS.size() * 2 - 1
	var c0 := _row_cols(r0)
	var c1 := _row_cols(r1)
	if o <= lerpf(c0[0], c1[0], u) or o >= lerpf(c0[cols - 1], c1[cols - 1], u):
		return base_hill(x, z)        # past the strip: the far terrain
	# the column the point is in: binary search (the offsets only increase).
	# A linear scan over ~57 columns made every off-road ground query slow.
	var k := 0
	var hi := cols - 2
	while k < hi:
		var mid := (k + hi) >> 1
		if lerpf(c0[mid + 1], c1[mid + 1], u) < o:
			k = mid + 1
		else:
			hi = mid
	var P := Vector3(x, 0, z)
	# That guess measures straight out from the road, but on a bend the rows of
	# the strip fan out, so far from the road (60+ m) the point is often really
	# in a neighbouring quad - and the dunes there gave the car a ground up to
	# 1.8 m below the sand that's drawn (it sank in). So check the quad's real
	# corners and step to the neighbour the point lies towards until it's inside.
	var A: Vector3
	var B: Vector3
	var C: Vector3
	var D: Vector3
	for step in 24:
		r1 = mini(r0 + 2, n - 1)
		A = _rib_vert(r0, k)
		B = _rib_vert(r0, k + 1)
		C = _rib_vert(r1, k)
		D = _rib_vert(r1, k + 1)
		var moved := false
		# before this row (wrong side of edge A-B) / past the next one (C-D)
		if r0 >= 2 and _opposite(A, B, P, C):
			r0 -= 2
			moved = true
		elif r0 + 2 <= n - 3 and _opposite(C, D, P, A):
			r0 += 2
			moved = true
		# left of column k (edge A-C) / right of column k+1 (edge B-D); clipped
		# columns can collapse to a line, then just keep going the same way
		if not moved:
			if _opposite(A, C, P, B) or (A.distance_squared_to(B) < 1e-6 and o < 0.0):
				if k == 0:
					return base_hill(x, z)   # past the strip's edge
				k -= 1
				moved = true
			elif _opposite(B, D, P, A) or (A.distance_squared_to(B) < 1e-6 and o >= 0.0):
				if k >= cols - 2:
					return base_hill(x, z)
				k += 1
				moved = true
		if not moved:
			break
	# which side of the B-C diagonal: A's triangle or D's
	var side_p := _side(B, C, P)
	var side_a := _side(B, C, A)
	if (side_p >= 0.0) == (side_a >= 0.0):
		return _tri_h(A, B, C, x, z)
	return _tri_h(B, C, D, x, z)

# true when p and ref are on opposite sides of the line a-b (in plan view)
static func _opposite(a: Vector3, b: Vector3, p: Vector3, ref: Vector3) -> bool:
	if a.distance_squared_to(b) < 1e-6:
		return false
	var sp := _side(a, b, p)
	var sr := _side(a, b, ref)
	return (sp > 1e-6 and sr < -1e-6) or (sp < -1e-6 and sr > 1e-6)

# all column offsets of row ri (cached: the ground under the car is asked for
# ~30 times a tick)
var _cols_cache := {}
func _row_cols(ri: int) -> PackedFloat32Array:
	var hit = _cols_cache.get(ri)
	if hit != null:
		return hit
	var cols := OFFS.size() * 2 - 1
	var a := PackedFloat32Array()
	a.resize(cols)
	for k in cols:
		a[k] = _col_o(ri, k)
	if _cols_cache.size() > 20000:
		_cols_cache.clear()
	_cols_cache[ri] = a
	return a

# how far along from row r0 to row r0+2 the point is (0..1 inside)
func _row_u(r0: int, x: float, z: float) -> float:
	var p0: Vector3 = pts[r0]
	var p1: Vector3 = pts[mini(r0 + 2, pts.size() - 1)]
	var along := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
	return Vector3(x - p0.x, 0, z - p0.z).dot(along) / max(along.length_squared(), 1e-4)

# signed sideways offset of column k on row ri, clipped like _build_chunk
func _col_o(ri: int, k: int) -> float:
	var o: float = OFFS[abs(k - (OFFS.size() - 1))] * (1.0 if k >= OFFS.size() - 1 else -1.0)
	var lim := _row_limits(ri)
	return min(o, lim.x) if o >= 0.0 else max(o, -lim.y)

# the strip vertex (row ri, column k) exactly as _build_chunk makes it.
# Cached: a crash checks the ground under ~30 points of the car every tick, and
# each vertex costs a noise lookup.
var _rv_cache := {}
func _rib_vert(ri: int, k: int) -> Vector3:
	var key := ri * 128 + k
	var hit = _rv_cache.get(key)
	if hit != null:
		return hit
	var p: Vector3 = pts[ri]
	var l := Vector3(-tans[ri].z, 0, tans[ri].x)
	var o := _col_o(ri, k)
	var wp := Vector3(p.x, 0, p.z) + l * o
	var v := Vector3(wp.x, _ground_from(wp.x, wp.z, o, p.y), wp.z)
	if _rv_cache.size() > 40000:
		_rv_cache.clear()
	_rv_cache[key] = v
	return v

static func _side(a: Vector3, b: Vector3, p: Vector3) -> float:
	return (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x)

# height at (x, z) on the plane through triangle a, b, c
static func _tri_h(a: Vector3, b: Vector3, c: Vector3, x: float, z: float) -> float:
	var nrm := (b - a).cross(c - a)
	if absf(nrm.y) < 1e-6:
		return (a.y + b.y + c.y) / 3.0
	return a.y - (nrm.x * (x - a.x) + nrm.z * (z - a.z)) / nrm.y

# How far the terrain strip at road sample ri may reach on its left (x) and
# right (y) side. A strip must not fold over itself on the inside of a bend
# (it would cross the road on the far side), and must stop halfway to any
# other part of the road so it never lies over that road. Cached per sample.
var row_lim := {}
func _row_limits(ri: int) -> Vector2:
	if row_lim.has(ri):
		return row_lim[ri]
	var n := pts.size()
	var far: float = OFFS[OFFS.size() - 1]
	if "--nolimits" in OS.get_cmdline_user_args():   # dev: compare with the old unclipped strips
		return Vector2(far, far)
	var lp := far
	var ln := far
	var p: Vector3 = pts[ri]
	var t: Vector3 = tans[ri]
	var l := Vector3(-t.z, 0, t.x)
	# 1) bends: stay short of the centre of the turn on the inside
	var kmax := 0.0
	for j in range(max(ri - 10, 0), min(ri + 11, n)):
		kmax = max(kmax, abs(curv[j]))
	if kmax > 1e-5:
		var ahead: Vector3 = pts[min(ri + 8, n - 1)] - p
		var behind: Vector3 = pts[max(ri - 8, 0)] - p
		var s := (ahead + behind).dot(l)       # the road bends towards this side
		var r_lim := 0.8 / kmax
		if s > 0.0:
			lp = min(lp, r_lim)
		else:
			ln = min(ln, r_lim)
	# 2) other parts of the road: stop halfway to them
	for j in range(max(ri - 500, 0), min(ri + 500, n), 3):
		if abs(j - ri) < 45:
			continue
		var v: Vector3 = pts[j] - p
		if abs(v.x * t.x + v.z * t.z) > 30.0:
			continue
		var along := v.x * l.x + v.z * l.z
		if along > 0.0:
			lp = min(lp, along * 0.5)
		else:
			ln = min(ln, -along * 0.5)
	var lim := Vector2(max(lp, HALF_W + 1.6), max(ln, HALF_W + 1.6))
	row_lim[ri] = lim
	return lim

func _rib_h(p: Vector3, l: Vector3, o: float) -> float:
	var wp := Vector3(p.x, 0, p.z) + l * o
	return _ground_from(wp.x, wp.z, o, p.y)

func road_h(x: float, z: float) -> float:
	return _nearest(x, z).y

# Ground height at signed offset o from the road (o < 0 = the driver's left). On
# the beach the left side is sand sloping down to the sea and then the seabed;
# everywhere else it's _terrain_from.
func _ground_from(x: float, z: float, o: float, rh: float) -> float:
	if sea and o < 0.0:
		o = -o
		var s0 := HALF_W + 1.4
		var s1: float = float(biome.get("sea_start", 28.0))
		if o <= s0:
			return rh - 0.15
		if o <= s1:   # the beach: sand down to just above the water
			return lerpf(rh - 0.2, sea_y + 0.25, sstep(s0, s1, o))
		# under the water: shelving down to the seabed, with gentle ripples
		return lerpf(sea_y + 0.25, sea_y - 6.0, sstep(s1, s1 + 50.0, o)) + base_hill(x, z) * 0.04
	return _terrain_from(x, z, abs(o), rh)

func _terrain_from(x: float, z: float, d: float, rh: float) -> float:
	# beach: the land side is low rolling ground that never dips into the sea
	var base := base_hill(x, z) * float(biome.get("land_k", 1.0)) + float(biome.get("land_add", 0.0))
	base += Biome.extra_height(biome, x, z, d)   # dunes / rocks away from the road
	if d > G_RADIUS - 1.0:
		return base
	# a wide, gentle bank between the road and the hillside
	return lerpf(rh - 0.15, base, sstep(HALF_W + 1.0, G_RADIUS - 3.0, d))

func terrain_h(x: float, z: float) -> float:
	var r := _nearest(x, z)
	return _terrain_from(x, z, r.x, r.y)

func ground_h(x: float, z: float) -> float:
	var r := _nearest(x, z, HALF_W + 1.4)   # only compared with the shoulder width
	if r.x < HALF_W:
		return r.y + 0.04
	if r.x < HALF_W + 1.4:
		# gravel shoulder sloping gently down into the terrain (matches the mesh)
		return max(r.y + 0.04 - 0.26 * (r.x - HALF_W) / 1.4, surface_h(x, z))
	return surface_h(x, z)   # the ground exactly as drawn, not the smooth formula

func nearest_index(p: Vector3, hint: int, search := 40) -> int:
	var n := pts.size()
	var best := 0
	var bd := 1e18
	var lo: int = 0 if hint < 0 else maxi(hint - search, 0)
	var hi: int = n if hint < 0 else mini(hint + search + 1, n)
	for i in range(lo, hi):
		var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	hint_idx = best
	return best

# ---------------------------------------------------------------- surface looks
func set_wet(w: float) -> void:
	if abs(w - surf_wet) < 0.01:
		return
	surf_wet = w
	_apply_surface()

# snow weather: snow on the ground (the road itself stays clear tarmac)
func set_snow(s: float) -> void:
	s = max(s, biome.get("snow_base", 0.0))   # tundra ground is always frosted
	terrain_mat.set_shader_parameter("snow", s)
	if grass_mat:
		grass_mat.set_shader_parameter("snow", s)

func _apply_surface() -> void:
	# wet: darker and shiny, but not mirror-smooth (that glitters with the bump map)
	road_mat.roughness = lerpf(0.82, 0.34, surf_wet)
	road_mat.metallic_specular = lerpf(0.5, 0.7, surf_wet)
	Gfx.set_albedo(road_mat, Color.WHITE.lerp(Color(0.6, 0.61, 0.64), surf_wet))
	road_mat.normal_scale = lerpf(0.6, 0.15, surf_wet)
	road_mat.clearcoat_enabled = surf_wet > 0.3
	road_mat.clearcoat = 0.6
	road_mat.clearcoat_roughness = 0.25

# ---------------------------------------------------------------- materials
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

func _make_materials() -> void:
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
	sh_mat = StandardMaterial3D.new()
	sh_mat.albedo_texture = _noise_tex(0.25, false, 256, g2)
	sh_mat.roughness = 1.0
	line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.86, 0.86, 0.82)
	line_mat.roughness = 0.6
	if float(biome.get("line_glow", 0.0)) > 0.0:   # neon road lines (biome)
		line_mat.emission_enabled = true
		line_mat.emission = biome.get("glow_col", Color.WHITE)
		line_mat.emission_energy_multiplier = float(biome["line_glow"])
	sh_mat.albedo_color = biome.get("shoulder", Color.WHITE)
	# Low detail: smooth flat asphalt / gravel; baked lighting: drawn unshaded
	Gfx.surface(road_mat, Color(0.185, 0.185, 0.19))
	Gfx.surface(sh_mat, Color(0.31, 0.28, 0.235))
	Gfx.surface(line_mat)
	var sh := Shader.new()
	sh.code = Gfx.shader_code(Biome.TERRAIN_SHADER)   # shared ground shader (biome colours)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = sh
	terrain_mat.set_shader_parameter("noise_a", _noise_tex(0.01, false, 256))
	terrain_mat.set_shader_parameter("noise_b", _noise_tex(0.04, false, 512))
	terrain_mat.set_shader_parameter("detail_n", _noise_tex(0.08, true, 512))
	Biome.apply_terrain(terrain_mat, biome)

# ---------------------------------------------------------------- chunk building
# columns of the terrain strip, metres from the road centre: close together
# where dunes / lumps can be seen up close so the ground isn't blocky
const OFFS := [0.0, 5.25, 6.65, 9.0, 13.0, 17.0, 21.0, 25.0, 29.0, 33.0, 37.5, 42.0, 47.0, 52.0, 58.0, 64.0,
	71.0, 79.0, 88.0, 98.0, 110.0, 124.0, 140.0, 158.0, 180.0, 205.0, 235.0, 270.0, 310.0]

func _build_chunk(c: int) -> void:
	var node := Node3D.new()
	node.name = "Chunk%d" % c
	add_child(node)
	chunks[c] = node
	var i0 := c * CHUNK_N
	var i1 := mini((c + 1) * CHUNK_N, pts.size() - 2)
	# ---- road ribbon
	var mb := MB.new()
	for i in range(i0, i1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var la := Vector3(-tans[i].z, 0, tans[i].x)
		var lb := Vector3(-tans[i + 1].z, 0, tans[i + 1].x)
		var v0 := i * STEP / 12.0
		var v1 := (i + 1) * STEP / 12.0
		var up := Vector3.UP
		var A := Vector3(a.x, a.y + 0.04, a.z)
		var B := Vector3(b.x, b.y + 0.04, b.z)
		mb.quad("road", A + la * HALF_W, A - la * HALF_W, B - lb * HALF_W, B + lb * HALF_W, up, up, up, up, Color.WHITE,
			Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1))
		for sd in [1.0, -1.0]:
			var oa: Vector3 = la * sd
			var ob: Vector3 = lb * sd
			var na := (Vector3.UP + oa * 0.3).normalized()
			mb.quad("shoulder", A + oa * HALF_W, A + oa * (HALF_W + 1.4) - Vector3(0, 0.22, 0),
				B + ob * (HALF_W + 1.4) - Vector3(0, 0.22, 0), B + ob * HALF_W, na, na, na, na, Color.WHITE,
				Vector2(0, v0 * 3), Vector2(0.3, v0 * 3), Vector2(0.3, v1 * 3), Vector2(0, v1 * 3))
			var e0 := HALF_W - 0.45
			mb.quad("line", A + oa * e0 + up * 0.01, A + oa * (e0 + 0.18) + up * 0.01, B + ob * (e0 + 0.18) + up * 0.01, B + ob * e0 + up * 0.01, up, up, up, up)
	var rmi := MeshInstance3D.new()
	rmi.mesh = mb.build({"road": road_mat, "shoulder": sh_mat, "line": line_mat})
	node.add_child(rmi)
	# ---- terrain ribbon (both sides of the road)
	var cols := OFFS.size() * 2 - 1
	var rows := 0
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var stride := 2
	var ii := i0
	while ii <= i1 + 1:
		var ri := mini(ii, pts.size() - 1)
		var p: Vector3 = pts[ri]
		var l := Vector3(-tans[ri].z, 0, tans[ri].x)
		var lim := _row_limits(ri)
		for k in range(cols):
			var o: float = OFFS[abs(k - (OFFS.size() - 1))] * (1.0 if k >= OFFS.size() - 1 else -1.0)
			# stop the strip before it folds over a bend or reaches other road
			o = min(o, lim.x) if o >= 0.0 else max(o, -lim.y)
			var wp := Vector3(p.x, 0, p.z) + l * o
			var d: float = abs(o)
			var h := _ground_from(wp.x, wp.z, o, p.y)
			verts.append(Vector3(wp.x, h, wp.z))
			colors.append(Color(clampf((d - HALF_W) / 10.0, 0.0, 1.0), 1, 1))
		rows += 1
		ii += stride
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for r in rows:
		for k in cols:
			var pl: Vector3 = verts[r * cols + max(k - 1, 0)]
			var pr: Vector3 = verts[r * cols + min(k + 1, cols - 1)]
			var pd: Vector3 = verts[max(r - 1, 0) * cols + k]
			var pu: Vector3 = verts[min(r + 1, rows - 1) * cols + k]
			var n := (pr - pl).cross(pu - pd).normalized()
			if n.y < 0.0:
				n = -n
			norms[r * cols + k] = n
			if Gfx.baked:   # baked light in the green channel
				var bc: Color = colors[r * cols + k]
				bc.g = Gfx.light_at(n) / Gfx.TERRAIN_SCALE
				colors[r * cols + k] = bc
	var idx := PackedInt32Array()
	for r in rows - 1:
		for k in cols - 1:
			var a := r * cols + k
			var b := a + 1
			var cc := a + cols
			var dd := cc + 1
			var fn: Vector3 = (verts[b] - verts[a]).cross(verts[cc] - verts[a])
			if fn.y > 0.0:
				idx.append_array([a, cc, b, b, cc, dd])
			else:
				idx.append_array([a, b, cc, b, dd, cc])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var tm := ArrayMesh.new()
	tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	tm.surface_set_material(0, terrain_mat)
	var tmi := MeshInstance3D.new()
	tmi.mesh = tm
	node.add_child(tmi)
	# ---- trees and bushes
	if forest == null:
		return
	var trng := RandomNumberGenerator.new()
	trng.seed = 777 + c * 31
	var trees := []
	var bushes := []
	var ti := i0
	while ti < i1:
		var p: Vector3 = pts[ti]
		var t: Vector3 = tans[ti]
		var l := Vector3(-t.z, 0, t.x)
		var tlim := _row_limits(ti)
		for sd in [1.0, -1.0]:
			var side_lim: float = tlim.x if sd > 0.0 else tlim.y
			# dense near the road, thinner deeper in
			# the biome can spread them further out (neon night: buildings far from the road)
			for n in int(biome.get("tree_tries", 6)):
				var o := HALF_W + 3.5 + float(biome.get("tree_clear", 0.0)) + pow(trng.randf(), float(biome.get("tree_spread", 1.7))) * float(biome.get("tree_reach", 150.0))
				var wp: Vector3 = Vector3(p.x, 0, p.z) + l * o * sd + t * trng.randf_range(-2.0, 2.0)
				var h := _terrain_from(wp.x, wp.z, o, p.y)
				var s := trng.randf_range(0.8, 1.25)
				var bas := Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3(s, s * trng.randf_range(0.92, 1.1), s))
				var variant: int = trng.randi() % forest.VARIANTS
				# not on ground that belongs to another stretch of road; the biome thins the trees
				if o < side_lim - 3.0 and trng.randf() < float(biome.get("tree_k", 1.0)) and not (sea and sd < 0.0):   # nothing on the sea side
					trees.append([Transform3D(bas, Vector3(wp.x, h - 0.1, wp.z)), variant])
			if trng.randf() < 0.5:
				var ob := HALF_W + 2.0 + trng.randf() * 30.0
				var bp: Vector3 = Vector3(p.x, 0, p.z) + l * ob * sd
				var bs := trng.randf_range(0.7, 1.5)
				var bb := Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3(bs, bs * 0.8, bs))
				if ob < side_lim - 2.0 and trng.randf() < float(biome.get("bush_k", 1.0)) and not (sea and sd < 0.0):
					bushes.append(Transform3D(bb, Vector3(bp.x, _terrain_from(bp.x, bp.z, ob, p.y) - 0.1, bp.z)))
		ti += 2
	# group into 48 m cells: the detail level is picked per cell, so only the trees
	# that are actually close get the full-detail mesh (one block per 200 m stretch
	# drew the whole stretch in full detail)
	var cells := {}
	for tr in trees:
		var o: Vector3 = (tr[0] as Transform3D).origin
		var key := Vector2i(int(floor(o.x / 48.0)), int(floor(o.z / 48.0)))
		if not cells.has(key):
			cells[key] = [[], []]
		cells[key][0].append(tr)
	for b in bushes:
		var o: Vector3 = (b as Transform3D).origin
		var key := Vector2i(int(floor(o.x / 48.0)), int(floor(o.z / 48.0)))
		if not cells.has(key):
			cells[key] = [[], []]
		cells[key][1].append(b)
	for key in cells.keys():
		var kv: Vector2i = key
		var cx := (kv.x + 0.5) * 48.0
		var cz := (kv.y + 0.5) * 48.0
		var any: Transform3D = cells[key][0][0][0] if not cells[key][0].is_empty() else cells[key][1][0]
		forest.add_tree_block(cells[key][0], cells[key][1], Vector3(cx, any.origin.y, cz), node)

# Airtime Park: a loop of big jumps. Each jump is a curved kicker, a short lip,
# then a long sloped landing straight ahead of it: it rounds over (a slow car
# drops onto the gentle top), runs steep for as far as a car at the jump's top
# speed flies, then curves out smoothly onto the road again. Most kickers come
# a short run after a corner, and every flight and landing is on the same
# straight as its kicker, with no turn until well after the run-out.
#
# The course is laid out like turtle steps (straight, turn, jump...), so the
# map knows exactly where every straight and jump is. Two long straights are
# stretched or shortened to close the loop. The landings take the course
# downhill; the rest of the lap climbs gently to get the height back.
extends "res://scripts/hill_track.gd"

# jump sizes: the fastest a car should hit it (km/h); the landing is made long
# enough for that. Hitting it faster lands on the run-out.
const JUMP_KMH := [58.0, 72.0, 88.0]
const KICK_LEN := [18.0, 21.0, 24.0]   # kicker length (m)
const KICK_SLOPE := 0.14               # kicker angle at the lip (~8 degrees)
const LIP_LEN := 3.0                   # short flat top
const KNOLL := 6.0                     # landing rounds over from flat to steep
const LAND_SLOPE := 0.27               # steep part of the landing (~15 degrees)
const OUTRUN := 16.0                   # landing curves back to level

# the course: ["S", metres] straight, ["F", metres] straight that's stretched to
# close the loop, ["T", degrees (+ = left), radius] turn, ["J", size] jump
const COURSE := [
	# start straight: a first jump to warm up
	["S", 140.0], ["J", 0], ["S", 40.0],
	["T", 90.0, 45.0],
	["S", 30.0], ["J", 1], ["S", 45.0],
	# a right flick, then straight onto a kicker
	["T", -60.0, 40.0],
	["S", 25.0], ["J", 0], ["S", 40.0],
	["T", 100.0, 35.0],
	["S", 30.0], ["J", 2], ["S", 55.0],
	["T", 50.0, 60.0],
	["F", 200.0],
	["T", 60.0, 45.0],
	["S", 30.0], ["J", 1], ["S", 40.0],
	["T", -50.0, 40.0],
	["S", 25.0], ["J", 0], ["S", 40.0],
	["T", 80.0, 40.0],
	["S", 35.0], ["J", 2], ["S", 55.0],
	["T", 45.0, 50.0],
	["S", 30.0], ["J", 1], ["S", 40.0],
	["T", 90.0, 50.0],
	["F", 40.0],
	["T", -45.0, 60.0],   # (the turns add up to 360)
]

var jumps: Array = []        # {pos: Vector2 kicker start, size, len}
var land_len := [0.0, 0.0, 0.0]   # steep landing length per size
var hfield := PackedFloat32Array()   # coarse land height following the road (base_hill)
var hf_cell := 20.0                   # land height grid spacing
var hf_n := 0

func _init() -> void:
	_prepare()
	var free_add := Vector2.ZERO
	var path := _turtle(free_add)
	# close the loop: solve for how much longer the two "F" straights must be
	var err: Vector2 = path["end"] - path["start"]
	var d: Array = path["free_dirs"]
	var a: Vector2 = d[0]
	var b: Vector2 = d[1]
	var det := a.x * b.y - a.y * b.x
	free_add = Vector2((-err.x * b.y + err.y * b.x) / det, (-a.x * err.y + a.y * err.x) / det)
	path = _turtle(free_add)
	var raw: Array = path["pts"]
	# centre the course on the map
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in raw:
		lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
		hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
	var cen := (lo + hi) * 0.5
	var c: Array = []
	for p in raw:
		c.append((p as Vector2) - cen)
	for j in jumps:
		j["pos"] -= cen
	ctrl = c
	var ext: float = max(hi.x - lo.x, hi.y - lo.y) * 0.5 + 60.0
	G_MIN = Vector2(-ext, -ext)
	_settings(path, free_add, hi - lo)

# --- things another map built on this one changes (speed_track.gd)
func _course() -> Array:
	return COURSE

func _prepare() -> void:
	for s in 3:
		land_len[s] = _steep_len(s)

# road samples left out of the land-height blend (a ravine floor)
func _is_gap(_i: int) -> bool:
	return false

func _settings(path: Dictionary, free_add: Vector2, size: Vector2) -> void:
	crest_count = 0
	smooth_win = 1
	blend_far = 14.0
	gantry_text = "AIRTIME PARK"
	grass_density = 1.3
	grass_height = 1.0
	clump.seed = 12
	clump.frequency = 0.015
	print("Airtime Park: %.0f m lap, %d jumps, free straights %+.0f / %+.0f m, %.0f x %.0f m" % [
		path["len"], jumps.size(), free_add.x, free_add.y, size.x, size.y])

# Walk the course. Points every ~6 m (CR spline goes through them); jumps
# remember where their kicker starts.
func _turtle(free_add: Vector2) -> Dictionary:
	var pos := Vector2.ZERO
	var hd := 0.0
	var out: Array = [pos]
	var free_dirs: Array = []
	var nf := 0
	var total := 0.0
	jumps.clear()
	for step in _course():
		var kind: String = step[0]
		var dist := 0.0
		if kind == "S":
			dist = step[1]
		elif kind == "F":
			free_dirs.append(Vector2(cos(hd), sin(hd)))
			dist = float(step[1]) + (free_add.x if nf == 0 else free_add.y)
			nf += 1
		elif kind == "J":
			var sz: int = step[1]
			jumps.append({"pos": pos, "size": sz, "dir": Vector2(cos(hd), sin(hd))})
			dist = jump_len(sz)
		if kind != "T":
			var n: int = max(1, int(ceil(dist / 6.0)))
			var dv := Vector2(cos(hd), sin(hd))
			for k in n:
				pos += dv * (dist / n)
				out.append(pos)
			total += dist
		else:
			var ang := deg_to_rad(float(step[1]))
			var r: float = step[2]
			var arc: float = abs(ang) * r
			var n: int = max(2, int(ceil(arc / 5.0)))
			var sgn := signf(ang)
			# centre of the turn sits to the left (+) or right (-) of the heading
			var cc := pos + Vector2(-sin(hd), cos(hd)) * r * sgn
			for k in n:
				hd += ang / n
				pos = cc - Vector2(-sin(hd), cos(hd)) * r * sgn
				out.append(pos)
			total += arc
	var end: Vector2 = out.pop_back()   # the loop's last point is the start again
	return {"pts": out, "start": Vector2.ZERO, "end": end, "free_dirs": free_dirs, "len": total}

func jump_len(sz: int) -> float:
	return KICK_LEN[sz] + LIP_LEN + KNOLL + land_len[sz] + OUTRUN

# Height of a jump above where it starts, x metres from the kicker's foot.
func jump_shape(sz: int, x: float) -> float:
	var lk: float = KICK_LEN[sz]
	var hk := KICK_SLOPE * lk * 0.5             # kicker: y = hk (x/lk)^2, slope KICK_SLOPE at the lip
	if x <= 0.0:
		return 0.0
	if x < lk:
		var u := x / lk
		return hk * u * u
	x -= lk
	if x < LIP_LEN:
		return hk
	x -= LIP_LEN
	var ls: float = land_len[sz]
	# landing: slope grows 0 -> LAND_SLOPE over KNOLL, stays for ls, eases back to 0 over OUTRUN
	var y := hk
	var t := minf(x, KNOLL)
	y -= LAND_SLOPE * t * t / (2.0 * KNOLL)
	x -= KNOLL
	if x <= 0.0:
		return y
	t = minf(x, ls)
	y -= LAND_SLOPE * t
	x -= ls
	if x <= 0.0:
		return y
	t = minf(x, OUTRUN)
	y -= LAND_SLOPE * (t - t * t / (2.0 * OUTRUN))
	return y

# How long the steep part must be: fly a car off the lip at the jump's top
# speed and see where it comes down, plus a few metres to spare.
func _steep_len(sz: int) -> float:
	var v: float = JUMP_KMH[sz] / 3.6
	var ang := atan(KICK_SLOPE)
	var vx := v * cos(ang)
	var vy := v * sin(ang)
	var x := 0.0
	while x < 300.0:
		x += 0.5
		var t := x / vx
		var car_y := vy * t - 4.905 * t * t
		var tt := minf(x, KNOLL)
		var ground: float = -LAND_SLOPE * tt * tt / (2.0 * KNOLL) - LAND_SLOPE * max(x - KNOLL, 0.0)
		if car_y <= ground:
			break
	return max(x - KNOLL + 6.0, 10.0)

# ---------------------------------------------------------------- heights
# The road's height: every jump's shape, and a steady climb everywhere else
# that wins back what the landings drop, so the lap closes.
func _sample_curve() -> void:
	super()
	var cnt := pts.size()
	var jump_at := PackedInt32Array()   # per sample: jump index it belongs to, or -1
	jump_at.resize(cnt)
	jump_at.fill(-1)
	var jx := PackedFloat32Array()      # metres from that jump's kicker foot
	jx.resize(cnt)
	var drop := 0.0
	for ji in jumps.size():
		var j: Dictionary = jumps[ji]
		var p: Vector2 = j["pos"]
		var ks := nearest_index(Vector3(p.x, 0, p.y), -1)
		var n := int(ceil(jump_len(j["size"]) / STEP))
		for k in n + 1:
			var idx := (ks + k) % cnt
			jump_at[idx] = ji
			jx[idx] = k * STEP
		j["idx"] = ks
		drop += -jump_shape(j["size"], jump_len(j["size"]) + 1.0)
	var free := 0
	for i in cnt:
		if jump_at[i] < 0:
			free += 1
	var climb: float = drop / maxi(free, 1)    # per sample
	var h := PackedFloat32Array()
	h.resize(cnt)
	var y := 0.0
	for i in cnt:
		if i > 0:
			if jump_at[i] >= 0:
				var sz: int = jumps[jump_at[i]]["size"]
				if jx[i] > 0.0:
					y += jump_shape(sz, jx[i]) - jump_shape(sz, jx[i] - STEP)
			else:
				y += climb
		h[i] = y
	for i in cnt:
		pts[i].y = h[i]
	_build_hfield()

# Land height away from the road: a smooth blend of nearby road heights, so the
# hillside follows the course down and back up (no cliffs 40 m from the road).
func _build_hfield() -> void:
	hf_n = int((T_MAX.x - T_MIN.x) / hf_cell) + 2
	hfield.resize(hf_n * hf_n)
	var cnt := pts.size()
	var sub: Array[Vector3] = []
	for i in range(0, cnt, 8):
		if not _is_gap(i):
			sub.append(pts[i])
	for gz in hf_n:
		for gx in hf_n:
			var wx := T_MIN.x + gx * hf_cell
			var wz := T_MIN.y + gz * hf_cell
			var s := 0.0
			var ws := 0.0
			for p in sub:
				var d2: float = (p.x - wx) * (p.x - wx) + (p.z - wz) * (p.z - wz) + 900.0
				var w := 1.0 / (d2 * d2)
				s += p.y * w
				ws += w
			hfield[gz * hf_n + gx] = s / ws

func base_hill(x: float, z: float) -> float:
	var n := hills.get_noise_2d(x, z) * 3.0 + hills2.get_noise_2d(x, z) * 0.6
	if hfield.is_empty():
		return n
	var fx := clampf((x - T_MIN.x) / hf_cell, 0.0, hf_n - 1.001)
	var fz := clampf((z - T_MIN.y) / hf_cell, 0.0, hf_n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i0 := iz * hf_n + ix
	var a := lerpf(hfield[i0], hfield[i0 + 1], tx)
	var b := lerpf(hfield[i0 + hf_n], hfield[i0 + hf_n + 1], tx)
	return lerpf(a, b, tz) + n

# open grass around the course, clumps of trees, forest round the edge
func tree_density(x: float, z: float, d: float) -> float:
	if d < 20.0:
		return 0.0
	var c := clump.get_noise_2d(x, z)
	var r := Vector2(x, z).length()
	var open_k := 0.25 + 0.6 * sstep(-0.05, 0.4, c)
	return lerpf(open_k, 0.9, sstep(-G_MIN.x - 40.0, -G_MIN.x + 60.0, r))

# for test readouts: metres from the kicker's foot to the lip, and to the end
# of the landing's steep part
func lip_dist(sz: int) -> float:
	return KICK_LEN[sz] + LIP_LEN

func slope_end(sz: int) -> float:
	return lip_dist(sz) + KNOLL + land_len[sz]

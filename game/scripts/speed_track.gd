# Canyon Speedway: a tight, twisty section straight after the start loops round
# into wider and wider bends (150-500 m radius), then a fast lap. About half
# way round, a kilometre-long straight runway ends at a ravine: a long, gentle
# kicker throws the car over the gap, and the landing on the far side slopes
# away for nearly 200 m, long enough for a car at full speed. Too slow and you
# drop into the ravine (Backspace / R brings you back).
#
# Built on the Airtime Park code (the turtle-step layout, the land following
# the road); the ravine is its own jump (size 3).
extends "res://scripts/jump_track.gd"

const RAVINE := 3
const RV_KICK := 80.0        # long curved kicker
const RV_SLOPE := 0.07       # ~4 degrees at the edge
const RV_LIP := 40.0         # straight ramp at RV_SLOPE before the edge (the car launches settled, at that angle)
const RV_GAP := 50.0         # width of the ravine at road level
const RV_DEPTH := 40.0       # ravine floor below the lip
const RV_STEP := 2.5         # far side starts this much lower than the edge (more = harder landings)
const RV_KNOLL := 12.0
const RV_LAND := 0.08        # landing slope (~4.5 degrees)
const RV_OUT := 50.0
const RV_KMH := 300.0        # landing long enough for this

# Straight 1: big rollers, one after another (smooth waves you take off from
# at speed). Straight 2: whoops, smaller bumps packed close together all the
# way to the next corners.
const ROLLERS := 4
const ROLL_N := 7
const ROLL_WAVE := Vector2(55.0, 100.0)  # each roller's length, picked at random in this range (m)
const ROLL_AMP := Vector2(1.8, 4.2)      # and its height (capped so no roller is too steep)
const ROLL_GAP := Vector2(10.0, 40.0)    # flat road between rollers (somewhere to land)
const ROLL_SEED := 2024                  # same "random" rollers every time the map loads
const WHOOPS := 5
const WHOOP_N := 50
const WHOOP_WAVE := 12.0
const WHOOP_AMP := 0.22

var rollers: Array = []      # [start x, length, height] of each roller along straight 1
var rollers_len := 0.0

# straight, turns, straight, turns, straight with the ravine, turns to the finish
const SPEED_COURSE := [
	# straight 1: the rollers
	["S", 20.0], ["J", ROLLERS], ["F", 60.0],
	# turn section 1
	["T", 60.0, 180.0], ["S", 80.0],
	["T", -40.0, 140.0], ["S", 70.0],
	["T", 70.0, 200.0],
	# straight 2: the whoops, right up to the next turns
	["S", 40.0], ["J", WHOOPS], ["S", 30.0],
	# turn section 2
	["T", 60.0, 220.0], ["S", 80.0],
	["T", -30.0, 180.0], ["S", 80.0],
	["T", 110.0, 260.0],
	# straight 3: the runway, the ravine, room to settle
	["S", 600.0], ["J", RAVINE], ["F", 300.0],
	# turn section 3, back to the start
	["T", 80.0, 200.0], ["S", 70.0],
	["T", -35.0, 150.0], ["S", 60.0],
	["T", 85.0, 180.0],   # (the turns add up to 360)
]

var rv_len := 0.0            # ravine landing's long slope
var rv_c := Vector2.ZERO     # middle of the gap, and the road's direction there
var rv_t := Vector2.RIGHT

func _course() -> Array:
	return SPEED_COURSE

func _prepare() -> void:
	super()
	rv_len = _ravine_land_len()
	land_len.append(rv_len)
	# the big rollers: random lengths, heights and gaps (fixed seed, so the map
	# is the same every time)
	var rng := RandomNumberGenerator.new()
	rng.seed = ROLL_SEED
	rollers.clear()
	var x := 0.0
	for k in ROLL_N:
		var wave := rng.randf_range(ROLL_WAVE.x, ROLL_WAVE.y)
		var amp := minf(rng.randf_range(ROLL_AMP.x, ROLL_AMP.y), wave * 0.048)   # steepest face ~8.5 degrees
		rollers.append([x, wave, amp])
		x += wave
		if k < ROLL_N - 1:
			x += rng.randf_range(ROLL_GAP.x, ROLL_GAP.y)
	rollers_len = x

func _settings(path: Dictionary, free_add: Vector2, size: Vector2) -> void:
	super(path, free_add, size)
	gantry_text = "CANYON SPEEDWAY"
	grass_density = 1.0
	blend_far = 30.0
	# a big map: bigger terrain (coarser mesh), coarser land-height grid
	var half: float = max(size.x, size.y) * 0.5 + 260.0
	T_MIN = Vector2(-half, -half)
	T_MAX = Vector2(half, half)
	terrain_step = 5.0
	hf_cell = 40.0
	for j in jumps:
		if j["size"] == RAVINE:
			var dir: Vector2 = j["dir"]
			rv_t = dir
			rv_c = (j["pos"] as Vector2) + dir * (RV_KICK + RV_LIP + RV_GAP * 0.5)
	print("Canyon Speedway: %.0f m lap, ravine landing %.0f m, free straights %+.0f / %+.0f m, %.0f x %.0f m" % [
		path["len"], rv_len, free_add.x, free_add.y, size.x, size.y])

func jump_len(sz: int) -> float:
	if sz == RAVINE:
		return RV_KICK + RV_LIP + RV_GAP + RV_KNOLL + rv_len + RV_OUT
	if sz == ROLLERS:
		return rollers_len
	if sz == WHOOPS:
		return WHOOP_N * WHOOP_WAVE
	return super(sz)

func jump_shape(sz: int, x: float) -> float:
	if sz == ROLLERS:
		# each roller is one smooth hump of its own length and height
		for r in rollers:
			var rx: float = x - float(r[0])
			if rx > 0.0 and rx < float(r[1]):
				return float(r[2]) * 0.5 * (1.0 - cos(TAU * rx / float(r[1])))
		return 0.0
	if sz == WHOOPS:
		# smooth waves, starting and ending level
		if x <= 0.0 or x >= jump_len(sz):
			return 0.0
		# the first few bumps grow from nothing, so you don't hit a wall of them
		var grow := clampf(x / (WHOOP_WAVE * 4.0), 0.0, 1.0)
		return WHOOP_AMP * grow * 0.5 * (1.0 - cos(TAU * x / WHOOP_WAVE))
	if sz != RAVINE:
		return super(sz, x)
	var hk := RV_SLOPE * RV_KICK * 0.5
	if x <= 0.0:
		return 0.0
	if x < RV_KICK:
		var u := x / RV_KICK
		return hk * u * u
	x -= RV_KICK
	if x < RV_LIP:
		return hk + RV_SLOPE * x     # straight ramp up to the edge
	x -= RV_LIP
	hk += RV_SLOPE * RV_LIP          # height of the edge
	if x < RV_GAP:
		return hk - RV_DEPTH      # the ravine floor
	x -= RV_GAP
	var y := hk - RV_STEP
	var t := minf(x, RV_KNOLL)
	y -= RV_LAND * t * t / (2.0 * RV_KNOLL)
	x -= RV_KNOLL
	if x <= 0.0:
		return y
	t = minf(x, rv_len)
	y -= RV_LAND * t
	x -= rv_len
	if x <= 0.0:
		return y
	t = minf(x, RV_OUT)
	y -= RV_LAND * (t - t * t / (2.0 * RV_OUT))
	return y

# where a car leaving the lip at RV_KMH comes down, past the gap
func _ravine_land_len() -> float:
	var v := RV_KMH / 3.6
	var ang := atan(RV_SLOPE)
	var vx := v * cos(ang)
	var vy := v * sin(ang)
	var x := RV_GAP
	while x < 800.0:
		x += 1.0
		var tt := x / vx
		var car_y := vy * tt - 4.905 * tt * tt
		var k := minf(x - RV_GAP, RV_KNOLL)
		var ground: float = -RV_STEP - RV_LAND * k * k / (2.0 * RV_KNOLL) - RV_LAND * max(x - RV_GAP - RV_KNOLL, 0.0)
		if car_y <= ground:
			break
	return x - RV_GAP - RV_KNOLL + 30.0

func _gap_range() -> Vector2i:
	for j in jumps:
		if j["size"] == RAVINE and j.has("idx"):
			var a := int(j["idx"]) + int(ceil((RV_KICK + RV_LIP) / STEP))
			var b := int(j["idx"]) + int(floor((RV_KICK + RV_LIP + RV_GAP) / STEP))
			return Vector2i(a, b)
	return Vector2i(-1, -2)

func _is_gap(i: int) -> bool:
	var r := _gap_range()
	var n := pts.size()
	for k in range(r.x, r.y + 1):
		if k % n == i:
			return true
	return false

func _sample_curve() -> void:
	super()
	road_gap.resize(pts.size())
	road_gap.fill(0)
	var r := _gap_range()
	for k in range(r.x, r.y + 1):
		road_gap[k % pts.size()] = 1

# the land: follows the course, gentle swells, and the ravine cut across the
# runway (it fades out a few hundred metres either side of the road)
func base_hill(x: float, z: float) -> float:
	var h := super(x, z)
	var p := Vector2(x, z) - rv_c
	var u: float = abs(p.dot(rv_t))
	var w: float = abs(p.dot(Vector2(-rv_t.y, rv_t.x)))
	var cut := (1.0 - sstep(RV_GAP * 0.5 - 3.0, RV_GAP * 0.5 + 8.0, u)) * (1.0 - sstep(200.0, 320.0, w))
	return h - RV_DEPTH * cut

# open plains: no trees near the road (it's fast), sparse clumps further out
func tree_density(x: float, z: float, d: float) -> float:
	if d < 35.0:
		return 0.0
	var c := clump.get_noise_2d(x, z)
	return 0.05 + 0.4 * sstep(0.15, 0.5, c)

func lip_dist(sz: int) -> float:
	if sz == ROLLERS or sz == WHOOPS:
		return 0.0
	if sz == RAVINE:
		return RV_KICK + RV_LIP
	return super(sz)

func slope_end(sz: int) -> float:
	if sz == ROLLERS or sz == WHOOPS:
		return jump_len(sz)
	if sz == RAVINE:
		return RV_KICK + RV_LIP + RV_GAP + RV_KNOLL + rv_len
	return super(sz)

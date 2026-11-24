# Stadium biome dressing for the race tracks: grandstands packed with a
# colourful crowd, floodlight towers and a line of advert boards along both
# sides of the circuit. Only placed where there's room (never on another part
# of the road), sitting on the ground the car drives on.
extends RefCounted

const MB = preload("res://scripts/mb.gd")

const CROWD := [Color(0.85, 0.15, 0.12), Color(0.15, 0.3, 0.8), Color(0.95, 0.85, 0.2), Color(0.9, 0.9, 0.9),
	Color(0.12, 0.12, 0.14), Color(0.2, 0.6, 0.25), Color(0.95, 0.5, 0.1), Color(0.55, 0.2, 0.6), Color(0.85, 0.65, 0.5)]
const SKIN := [Color(0.95, 0.8, 0.68), Color(0.8, 0.6, 0.45), Color(0.55, 0.38, 0.26), Color(0.35, 0.24, 0.17)]
const BOARDS := [Color(0.85, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.1, 0.25, 0.75), Color(0.98, 0.78, 0.1),
	Color(0.1, 0.1, 0.12), Color(0.1, 0.6, 0.3), Color(1.0, 0.45, 0.05)]

static func build(track, parent: Node3D) -> void:
	var mb := MB.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var n: int = track.pts.size()
	var hw: float = track.HALF_W
	# ---- grandstands every ~160 m, alternating sides (both sides at the start line)
	var i := 0
	var side := 1.0
	while i < n:
		var sides := [1.0, -1.0] if i == 0 else [side]
		for s in sides:
			_grandstand(mb, rng, track, i, s, hw)
		side = -side
		i += 80
	# ---- floodlight towers every ~200 m
	i = 40
	while i < n:
		_floodlight(mb, track, i, -1.0 if (i / 100) % 2 == 0 else 1.0, hw)
		i += 100
	# ---- advert boards along both sides
	i = 0
	var k := 0
	while i < n:
		for s in [1.0, -1.0]:
			_board(mb, track, i, s, hw, BOARDS[(k + (0 if s > 0 else 3)) % BOARDS.size()])
		k += 1
		i += 4
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.55, 0.55, 0.53)
	concrete.roughness = 0.9
	var crowd := StandardMaterial3D.new()
	crowd.vertex_color_use_as_albedo = true
	crowd.roughness = 0.8
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.75, 0.77, 0.8)
	roof.metallic = 0.6
	roof.roughness = 0.35
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.35, 0.36, 0.38)
	steel.metallic = 0.7
	steel.roughness = 0.45
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1, 1, 0.95)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.97, 0.88)
	lamp.emission_energy_multiplier = 2.5
	var board := StandardMaterial3D.new()
	board.vertex_color_use_as_albedo = true
	board.roughness = 0.5
	board.emission_enabled = true
	board.emission = Color(0.15, 0.15, 0.15)
	var mi := MeshInstance3D.new()
	mi.name = "Stadium"
	mi.mesh = mb.build({"concrete": concrete, "crowd": crowd, "roof": roof, "steel": steel, "lamp": lamp, "board": board})
	parent.add_child(mi)

static func _frame(track, i: int, side: float) -> Array:
	var p: Vector3 = track.pts[i]
	var t: Vector3 = track.tans[i]
	var out := Vector3(-t.z, 0, t.x) * side     # away from the road on this side
	return [Vector3(p.x, 0, p.z), t, out]

# true when a footprint (centre, along t, out) of size length x depth is clear of road
static func _clear(track, c: Vector3, t: Vector3, out: Vector3, length: float, depth: float, hw: float) -> bool:
	for a in [-0.5, 0.0, 0.5]:
		for b in [0.0, 0.5, 1.0]:
			var q: Vector3 = c + t * (length * a) + out * (depth * b)
			if track.road_dist(q.x, q.z) < hw + 3.0:
				return false
	return true

static func _grandstand(mb, rng: RandomNumberGenerator, track, i: int, side: float, hw: float) -> void:
	var f := _frame(track, i, side)
	var t: Vector3 = f[1]
	var out: Vector3 = f[2]
	var L := 38.0
	var rows := 9
	var front: Vector3 = f[0] + out * (hw + 7.5)
	if not _clear(track, front, t, out, L, rows * 1.0 + 2.0, hw):
		return
	var y0: float = track.terrain_h(front.x, front.z)
	for e in [[-0.5, 0.0], [0.5, 0.0], [-0.5, 1.0], [0.5, 1.0]]:
		var q: Vector3 = front + t * (L * e[0]) + out * (rows * 1.0 * e[1])
		y0 = min(y0, track.terrain_h(q.x, q.z))
	var basis := Basis(t, Vector3.UP, out)     # x along the road, z away from it
	_wall(track, front + out * 0.4 - t * (L * 0.5), front + out * 0.4 + t * (L * 0.5), 0.6)
	_wall(track, front + out * 0.4 - t * (L * 0.5), front + out * (rows + 0.5) - t * (L * 0.5), 0.6)
	_wall(track, front + out * 0.4 + t * (L * 0.5), front + out * (rows + 0.5) + t * (L * 0.5), 0.6)
	# a solid base down into the ground, then the stepped tiers with the crowd
	mb.box("concrete", Transform3D(basis, front + out * (rows * 0.5) + Vector3(0, y0 - 1.0, 0)), Vector3(L, 2.4, rows * 1.0 + 0.6))
	for r in rows:
		var h := 0.6 + r * 0.5
		var c: Vector3 = front + out * (0.5 + r * 1.0) + Vector3(0, y0 + h * 0.5, 0)
		mb.box("concrete", Transform3D(basis, c), Vector3(L, h, 1.0))
		# people: little blocks of colour along each step
		var seg := 0.0
		while seg < L - 0.6:
			if rng.randf() < 0.85:
				var pc: Vector3 = front + t * (seg - L * 0.5 + 0.35) + out * (0.55 + r * 1.0) + Vector3(0, y0 + h + 0.32, 0)
				var ph := rng.randf_range(0.45, 0.62)
				mb.box("crowd", Transform3D(basis, pc + Vector3(0, ph * 0.5 - 0.32, 0)), Vector3(0.36, ph, 0.26), CROWD[rng.randi() % CROWD.size()])
				mb.box("crowd", Transform3D(basis, pc + Vector3(0, ph - 0.2, 0)), Vector3(0.2, 0.22, 0.2), SKIN[rng.randi() % SKIN.size()])
			seg += 0.6
	# back wall, pillars and a roof leaning out over the crowd
	var top := 0.6 + rows * 0.5
	mb.box("concrete", Transform3D(basis, front + out * (rows * 1.0 + 0.2) + Vector3(0, y0 + top * 0.5 + 1.0, 0)), Vector3(L, top + 2.0, 0.4))
	for px in [-0.45, -0.15, 0.15, 0.45]:
		mb.box("steel", Transform3D(basis, front + t * (L * px) + out * (rows * 1.0 + 0.5) + Vector3(0, y0 + top + 2.6, 0)), Vector3(0.35, 5.2, 0.35))
	var rb := Basis(t, Vector3.UP, out) * Basis(Vector3.RIGHT, -0.12)
	mb.box("roof", Transform3D(rb, front + out * (rows * 0.55) + Vector3(0, y0 + top + 4.6, 0)), Vector3(L + 2.0, 0.25, rows * 1.0 + 3.0))

# a solid edge: a row of overlapping posts the car collides with like trunks
static func _wall(track, a: Vector3, b: Vector3, r: float) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) / (r * 1.4))))
	for k in n + 1:
		var q := a.lerp(b, float(k) / n)
		track.obstacles.append(Vector3(q.x, q.z, r))

static func _floodlight(mb, track, i: int, side: float, hw: float) -> void:
	var f := _frame(track, i, side)
	var t: Vector3 = f[1]
	var out: Vector3 = f[2]
	var base: Vector3 = f[0] + out * (hw + 6.0)
	if track.road_dist(base.x, base.z) < hw + 4.0:
		return
	base.y = track.terrain_h(base.x, base.z)
	track.obstacles.append(Vector3(base.x, base.z, 0.35))
	mb.cylinder("steel", Transform3D(Basis(), base + Vector3(0, 12.0, 0)), 0.35, 0.22, 24.0, 10)
	var hb := Basis(t, Vector3.UP, out) * Basis(Vector3.RIGHT, 0.35)
	mb.box("steel", Transform3D(hb, base + Vector3(0, 24.2, 0) - out * 0.3), Vector3(3.6, 2.2, 0.35))
	mb.box("lamp", Transform3D(hb, base + Vector3(0, 24.2, 0) - out * 0.5), Vector3(3.3, 1.9, 0.1))

static func _board(mb, track, i: int, side: float, hw: float, col: Color) -> void:
	var f := _frame(track, i, side)
	var t: Vector3 = f[1]
	var out: Vector3 = f[2]
	var c: Vector3 = f[0] + out * (hw + 3.2)
	if track.road_dist(c.x, c.z) < hw + 2.6:
		return
	c.y = track.terrain_h(c.x, c.z)
	_wall(track, c - t * 3.6, c + t * 3.6, 0.25)
	var b := Basis(t, Vector3.UP, out)
	mb.box("board", Transform3D(b, c + Vector3(0, 0.55, 0)), Vector3(7.6, 0.9, 0.12), col)
	mb.box("steel", Transform3D(b, c + Vector3(0, 0.05, 0.1)), Vector3(7.6, 0.12, 0.3))

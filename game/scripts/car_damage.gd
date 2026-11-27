# Soft-body-style car damage (a simplified take on node-and-beam crash physics):
#
#  * Crumple frame: 4 x 3 x 12 points spread through the car, joined by ~1000
#    springy links (along the axes and across the faces). A hit pushes the shape
#    of what was hit - a tree trunk, a guardrail beam, a patch of ground - into
#    the frame over a few frames; the links carry the push through the structure
#    and bend permanently when stretched or squashed too far (the cabin is
#    stiffer than the crumple zones front and back). The body mesh follows the
#    frame on the GPU (trilinear blend of the points' movement), so the whole
#    front can fold back, the bonnet buckle, the roof crush.
#  * Loose parts: bumpers, bonnet, doors and the rear wing are cut out of
#    the body. Each takes damage from hits near it: first it hangs loose on its
#    hinge (doors swing, the bonnet flutters, bumpers droop), then it comes off
#    and tumbles along the ground.
#  * Glass: each window cracks in a spider-web from the impact point and
#    shatters into falling shards when hit hard enough or when its frame bends.
#  * Readings for the physics: how bent each wheel corner is and how badly the
#    engine bay / radiator is crushed (car.gd turns those into mechanical damage).
extends Node3D

const NX := 4
const NY := 3
const NZ := 12
const LMIN := Vector3(-0.9, 0.15, -2.2)
const LSTEP := Vector3(0.6, 0.5, 0.4)
const ITER := 3                  # relaxation passes per physics tick while active
# Settings > Car > Fragility: multiplies how hard every hit lands on the body,
# and so the parts, glass, wheels and engine too (1 = normal; main.gd sets it)
static var fragility := 1.0

# slider 0..1 -> damage multiplier: 0.5 = x1 (normal), 0 = x0.25 (tough), 1 = x4 (fragile)
static func fragility_mult(slider: float) -> float:
	return pow(4.0, (clampf(slider, 0.0, 1.0) - 0.5) * 2.0)

var model                       # car_model.gd
var car                         # car.gd
var split_done := false

# ---- crumple frame
var rest := PackedVector3Array()     # undamaged node positions (car-local)
var pos := PackedVector3Array()
var inv_m := PackedFloat32Array()    # 0 = pinned (cabin floor)
var plast := PackedFloat32Array()    # permanent bending around each node (crumple amount)
var b_a := PackedInt32Array()
var b_b := PackedInt32Array()
var b_rest := PackedFloat32Array()   # current (plastically changed) rest length
var b_rest0 := PackedFloat32Array()
var b_yield := PackedFloat32Array()  # strain the link takes before it bends for good
var obstacles: Array = []            # active crush shapes
var lattice_dirty := false

# ---- parts and glass
var parts := {}       # name -> {pivot, mi, hinge, axis, sign, kind, health, mode, th, w, aabb, vel, ang}
var windows := {}     # name -> {mi, mat, health, aabb, crack, shattered}
var debris: Array = []
var shard_mat: ParticleProcessMaterial
var shard_mesh: QuadMesh

func setup(p_model, p_car) -> void:
	model = p_model
	car = p_car
	_build_lattice()

# ======================================================================= frame
static func _idx(i: int, j: int, k: int) -> int:
	return (k * NY + j) * NX + i

func _build_lattice() -> void:
	var n := NX * NY * NZ
	rest.resize(n)
	pos.resize(n)
	inv_m.resize(n)
	plast.resize(n)
	for k in NZ:
		for j in NY:
			for i in NX:
				var p := LMIN + LSTEP * Vector3(i, j, k)
				var id := _idx(i, j, k)
				rest[id] = p
				# the floor's centre spine is heavy (it holds the car together); the
				# sills along the sides and everything else can bend and fold
				inv_m[id] = 0.25 if (j == 0 and abs(p.x) < 0.5 and p.z > -0.5 and p.z < 0.7) else 1.0
	var offs := [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 1, 0), Vector3i(1, -1, 0),
		Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(0, 1, 1), Vector3i(0, 1, -1)]
	for k in NZ:
		for j in NY:
			for i in NX:
				for o in offs:
					var ov: Vector3i = o
					var i2 := i + ov.x
					var j2 := j + ov.y
					var k2 := k + ov.z
					if i2 < 0 or i2 >= NX or j2 < 0 or j2 >= NY or k2 < 0 or k2 >= NZ:
						continue
					var a := _idx(i, j, k)
					var b := _idx(i2, j2, k2)
					b_a.append(a)
					b_b.append(b)
					var l: float = rest[a].distance_to(rest[b])
					b_rest.append(l)
					b_rest0.append(l)
					var mz: float = (rest[a].z + rest[b].z) * 0.5
					var cabin := mz > -0.66 and mz < 0.9
					b_yield.append(0.05 if cabin else 0.008)
	repair_frame()

func repair_frame() -> void:
	for i in rest.size():
		pos[i] = rest[i]
		plast[i] = 0.0
	for i in b_rest.size():
		b_rest[i] = b_rest0[i]
	obstacles.clear()
	lattice_dirty = true

# Push a crush shape into the frame. Everything in car-local space.
#  kind "cyl": c = axis point, a = axis, r = radius   (tree, guardrail beam)
#  kind "plane": c = contact point, r = patch radius   (ground, roof landing)
#  u = direction the obstacle moves into the car, depth = how far
func crush(kind: String, c: Vector3, a: Vector3, r: float, u: Vector3, depth: float) -> void:
	if depth <= 0.005:
		return
	# a held contact (scraping, leaning on a tree) hits every tick: merge it into
	# the matching crush shape instead of piling up dozens of them - that pile-up
	# was the big frame-rate drop in crashes
	for ob in obstacles:
		if ob["kind"] == kind and (ob["c"] as Vector3).distance_to(c) < max(r, float(ob["r"])) * 0.6:
			ob["d"] = max(float(ob["d"]), depth)
			ob["t"] = min(int(ob["t"]), 3)
			return
	if obstacles.size() >= 4:
		obstacles.pop_front()
	obstacles.append({"kind": kind, "c": c, "a": a, "r": r, "u": u, "d": depth, "t": 0})

var _tick := 0
func _physics_process(_delta: float) -> void:
	_tick += 1
	if not obstacles.is_empty():
		_relax()
	# the crumple shape goes to the GPU every other tick (it's smoothed anyway)
	if lattice_dirty and (_tick % 2 == 0 or obstacles.is_empty()):
		lattice_dirty = false
		_upload_lattice()
	_update_parts(_delta)
	_update_debris(_delta)
	_update_rv(_delta)

# ================================================================ rear-view mirror
# It's glued to the top of the windscreen. Hard knocks shake it (rv_health) and
# a crushed roof / windscreen frame snaps it off; then it falls about inside the
# cabin: gravity in the car's own frame (upside down it drops onto the roof
# lining), bouncing off the cabin's walls, floor and roof.
const RV_BOX_MIN := Vector3(-0.62, 0.42, -0.35)   # cabin, body local
const RV_BOX_MAX := Vector3(0.62, 1.16, 0.95)
var max_throw := 0.0   # fastest a broken part has been thrown off, relative to the car (crash test readout)
var rv_health := 1.0
var rv_loose := false
var rv_pos := Vector3.ZERO
var rv_vel := Vector3.ZERO
var rv_ang := Vector3.ZERO
var rv_prev_v := Vector3.ZERO     # car's velocity last tick (its jolts throw the mirror about)

func _rv_hit(vn: float) -> void:
	if rv_loose or model.get("rv_mirror") == null or model.rv_mirror == null:
		return
	rv_health -= max(vn - 6.0, 0.0) * 0.045
	if rv_health <= 0.0 or frame_disp_near(model.rv_mount, 0.5) > 0.1:
		_rv_fall(vn)

func _rv_fall(vn: float) -> void:
	rv_loose = true
	rv_pos = model.rv_mirror.position
	rv_vel = Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * (0.6 + vn * 0.08)
	rv_ang = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (3.0 + vn * 0.3)
	model.set_rv_mirror_broken(true)
	if car.crash_audio:
		car.crash_audio.clank(model.rv_mirror.global_position, 0.3)

func _update_rv(dt: float) -> void:
	if car == null:
		return
	var cv: Vector3 = car.point_velocity(car.global_position)
	var jolt: Vector3 = (cv - rv_prev_v) / maxf(dt, 1e-4)
	rv_prev_v = cv
	if not rv_loose or model.rv_mirror == null:
		return
	var mn: Node3D = model.rv_mirror
	var body_b: Basis = mn.get_parent().global_transform.basis.orthonormalized()
	# gravity minus the car's own acceleration (a crash throws it forwards), in the car's frame
	var acc: Vector3 = body_b.inverse() * (Vector3(0, -9.81, 0) - jolt.limit_length(200.0))
	rv_vel += acc * dt
	rv_pos += rv_vel * dt
	for k in 3:
		if rv_pos[k] < RV_BOX_MIN[k] or rv_pos[k] > RV_BOX_MAX[k]:
			rv_pos[k] = clampf(rv_pos[k], RV_BOX_MIN[k], RV_BOX_MAX[k])
			if abs(rv_vel[k]) > 1.5 and car.crash_audio:
				car.crash_audio.clank(mn.global_position, clampf(abs(rv_vel[k]) / 10.0, 0.05, 0.3))
			rv_vel[k] = -rv_vel[k] * 0.3
			# lying on something: friction, and the spin dies down
			for j in 3:
				if j != k:
					rv_vel[j] *= 0.85
			rv_ang *= 0.7
	if rv_ang.length() > 0.001:
		mn.basis = (Basis(rv_ang.normalized(), rv_ang.length() * dt) * mn.basis).orthonormalized()
	mn.position = rv_pos

func _rv_repair() -> void:
	rv_health = 1.0
	rv_loose = false
	if model.get("rv_mirror") != null and model.rv_mirror:
		model.rv_mirror.transform = Transform3D(Basis(), model.rv_mount)
		model.set_rv_mirror_broken(false)

func _relax() -> void:
	var nb := b_a.size()
	for it in ITER:
		# links pull towards their (current) length
		for bi in nb:
			var a := b_a[bi]
			var b := b_b[bi]
			var wa := inv_m[a]
			var wb := inv_m[b]
			if wa + wb == 0.0:
				continue
			var d: Vector3 = pos[b] - pos[a]
			var l := d.length()
			if l < 1e-5:
				continue
			var corr := d * ((l - b_rest[bi]) / (l * (wa + wb))) * 0.8
			pos[a] += corr * wa
			pos[b] -= corr * wb
		# the floor spine is held (softly) where it belongs, so the frame bends
		# around it instead of the whole car sliding away from the obstacle
		for i in pos.size():
			if inv_m[i] < 1.0:
				pos[i] = pos[i].lerp(rest[i], 0.35)
		# the obstacles keep the points out of their shape
		for ob in obstacles:
			var dn: float = ob["d"] * min(1.0, (float(ob["t"]) + 1.0) / 4.0)
			var u: Vector3 = ob["u"]
			var cc: Vector3 = ob["c"] + u * dn
			var r: float = ob["r"]
			if ob["kind"] == "cyl":
				var ax: Vector3 = ob["a"]
				for i in pos.size():
					if inv_m[i] == 0.0:
						continue
					var v: Vector3 = pos[i] - cc
					v -= ax * v.dot(ax)
					var vl := v.length()
					if vl < r:
						pos[i] += (v / vl if vl > 1e-4 else u) * (r - vl)
			else:
				var c0: Vector3 = ob["c"]
				for i in pos.size():
					if inv_m[i] == 0.0:
						continue
					var rel: Vector3 = pos[i] - c0
					if (rel - u * rel.dot(u)).length() > r:
						continue
					var s: float = (pos[i] - cc).dot(u)
					if s < 0.0:
						pos[i] -= u * s
	# permanent bending: links stretched or squashed past their limit keep it
	for bi in nb:
		var a := b_a[bi]
		var b := b_b[bi]
		var l: float = pos[a].distance_to(pos[b])
		var lim: float = b_yield[bi] * b_rest0[bi]
		var dl: float = l - b_rest[bi]
		if abs(dl) > lim:
			var nr: float = l - signf(dl) * lim
			var ch: float = abs(nr - b_rest[bi])
			b_rest[bi] = nr
			plast[a] += ch
			plast[b] += ch
	var still := []
	for ob in obstacles:
		ob["t"] += 1
		if ob["t"] < 7:
			still.append(ob)
	obstacles = still
	lattice_dirty = true
	# what the bending does to panels and glass: every third tick, and once the
	# frame settles (it loops over every panel and window, so not every tick)
	if _tick % 3 == 0 or obstacles.is_empty():
		_from_frame()

# parts and glass react to how bent the structure around them is: a panel on a
# crushed section comes loose, then tears off; glass in a bent frame cracks,
# then shatters; a big frontal crush cracks the windscreen
func _from_frame() -> void:
	var eng_now := engine_damage()
	for name in parts.keys():
		var p: Dictionary = parts[name]
		if p["mode"] == 2:
			continue
		var b: AABB = p["aabb"]
		var fd := frame_disp_near(b.get_center(), max(b.size.length() * 0.5, 0.5))
		var off := 0.42 if p["kind"] == "door" else 0.3
		if p["kind"] == "loose":
			# headlights and the radiator go when the nose crushes; the intake,
			# battery and air box break loose once the engine bay itself is wrecked
			# (tail lights the same way, when the back of the car is crushed)
			if name.begins_with("headlight") or name.begins_with("taillight"):
				fd = max(fd, frame_disp_near(b.get_center(), 0.8) * 0.8)
				if fd > 0.08:
					_detach(name, 6.0)
			elif name == "radiator":
				if frame_disp_near(b.get_center(), 0.75) > 0.14 or eng_now > 0.7:
					_detach(name, 6.0)
			else:
				var need := {"intake": 0.85, "battery": 0.95, "airbox": 0.9}
				if eng_now > need.get(name, 0.9):
					_detach(name, 5.0)
			continue
		if p["kind"] == "fender":
			off = 0.26
			if (fd > 0.08 or eng_now > 0.6) and p["mode"] == 0:
				p["mode"] = 1
				p["w"] = 1.5
		if fd > off or (p["kind"] == "mirror" and fd > 0.12):
			_detach(name, 8.0)
		elif fd > 0.12 and p["mode"] == 0:
			p["mode"] = 1
			p["w"] = 1.5
	var eng := engine_damage()
	for name in windows.keys():
		var w: Dictionary = windows[name]
		if w["shattered"]:
			continue
		var b: AABB = w["aabb"]
		var fd := frame_disp_near(b.get_center(), b.size.length() * 0.6)
		var amt: float = max(1.0 - w["health"], (fd - 0.04) * 4.0)
		if name == "win_front":
			amt = max(amt, (eng - 0.5) * 1.6)
		if amt <= 0.0 or amt <= 1.0 - w["health"]:
			continue
		w["health"] = 1.0 - amt
		var c: Vector4 = w["crack"]
		if c.w == 0.0:
			var ctr := b.get_center()
			c = Vector4(ctr.x, ctr.y, ctr.z, 0.0)
		c.w = clampf(amt, 0.0, 1.0)
		w["crack"] = c
		for m in w["mat"]:
			if m is ShaderMaterial:
				m.set_shader_parameter("crack_c", c)
		if fd > 0.3:
			_shatter(name, Vector3.UP)

func _upload_lattice() -> void:
	var arr := PackedVector4Array()
	arr.resize(rest.size())
	for i in rest.size():
		var dv: Vector3 = pos[i] - rest[i]
		# where the frame bent hard, the metal crumples like foil (front, sides,
		# engine bay alike)
		# only properly bent metal crumples like foil: a big hit spreads a little
		# bend right through the frame, and that used to foil the whole car
		arr[i] = Vector4(dv.x, dv.y, dv.z, clampf((plast[i] - 0.06) * 3.0, 0.0, 0.3))
	model.upload_lattice(arr)

# how far the frame around a car-local point has been pushed
func frame_disp_near(p: Vector3, radius: float) -> float:
	var m2 := 0.0
	var r2 := radius * radius
	for i in rest.size():
		if rest[i].distance_squared_to(p) < r2:
			m2 = max(m2, pos[i].distance_squared_to(rest[i]))
	return sqrt(m2)

# 0..1 per wheel: FL, FR, RL, RR
func corner_damage(i: int) -> float:
	var w := [Vector3(-0.77, 0.33, -1.3), Vector3(0.77, 0.33, -1.3), Vector3(-0.78, 0.33, 1.35), Vector3(0.78, 0.33, 1.35)]
	# a crushed nose shoves the front wheels and suspension back, so the front
	# corners feel a wider area and bend sooner
	if i < 2:
		return clampf(frame_disp_near(w[i], 0.75) / 0.2, 0.0, 1.0)
	return clampf(frame_disp_near(w[i], 0.62) / 0.28, 0.0, 1.0)

func part_off(name: String) -> bool:
	return parts.has(name) and parts[name]["mode"] == 2

# 0..1: how crushed the front (engine bay, radiator) is
func engine_damage() -> float:
	# the worst-crushed points of the front decide it (a narrow pole hit can
	# wreck the radiator without crumpling the whole nose)
	var ds: Array = []
	for i in rest.size():
		if rest[i].z < -1.35 and rest[i].y < 1.0:
			ds.append((pos[i] - rest[i]).length())
	ds.sort()
	ds.reverse()
	var s := 0.0
	for i in min(6, ds.size()):
		s += ds[i]
	return clampf((s / 6.0) / 0.28, 0.0, 1.0)

# ======================================================================= hits
# One impact. World-space point / push (into the car) / obstacle axis. kind:
# "tree", "rail" or "ground". vn = closing speed (m/s), radius = obstacle size.
func hit(kind: String, wp: Vector3, push: Vector3, axis: Vector3, vn: float, radius: float) -> void:
	# how easily this car breaks (car_model damage_k: >1 crumples deeper and
	# loses parts and glass sooner)
	var dkv = model.get("damage_k")
	var dk: float = (float(dkv) if dkv != null else 1.0) * fragility
	var inv: Transform3D = model.shell.global_transform.affine_inverse() if model.shell else global_transform.affine_inverse()
	var lp: Vector3 = inv * wp
	var lu: Vector3 = (inv.basis * push).normalized()
	var la := Vector3.ZERO
	if axis != Vector3.ZERO:
		la = (inv.basis * axis).normalized()
	var depth := 0.0
	match kind:
		"tree":
			depth = clampf((vn - 3.0) * 0.045, 0.0, 0.8)
			# the trunk's axis sits a radius behind the contact point; the bumper
			# beam and panels spread the load, so the frame feels a wider shape
			var reff: float = max(radius + 0.35, 0.5)
			crush("cyl", lp - lu * reff, la, reff, lu, minf(depth * dk, 1.0))
		"rail":
			depth = clampf((vn - 2.0) * 0.012, 0.0, 0.15)
			crush("cyl", lp - lu * 0.3, la, 0.3, lu, depth * dk)
		"ground":
			depth = clampf((vn - 4.0) * 0.04, 0.0, 0.35)
			crush("plane", lp, Vector3.ZERO, 0.9, lu, depth * dk)
	_hit_parts(lp, vn * dk)
	_hit_glass(lp, lu, vn * dk, kind)
	_rv_hit(vn * dk)

# ======================================================================= split
# Cut the body shell into the detachable parts and the windows.
func _classify(key: String, c: Vector3, n: Vector3) -> String:
	# models built from other files (car_model_ext.gd) cut themselves up
	if model.has_method("damage_classify"):
		return model.damage_classify(key, c, n)
	var ax: float = abs(c.x)
	# engine-bay pieces that can break loose and fall out
	if key == "radiator" or (key in ["hose", "engine"] and c.z < -1.5 and c.z > -1.67 and c.y > 0.3 and ax < 0.45):
		return "radiator"
	if key in ["hose", "red", "alu"] and c.x > 0.3 and c.z < -1.36 and c.z > -1.64 and c.y > 0.48 and c.y < 0.7:
		return "battery"
	if key == "hose" and c.x < -0.28 and c.z < -1.34 and c.z > -1.62 and c.y > 0.54 and c.y < 0.7:
		return "airbox"
	if (key == "alu" and ax < 0.2 and c.z > -1.5 and c.z < -0.8 and c.y > 0.66) or (key == "red" and ax < 0.36 and c.y > 0.6 and c.z > -1.42 and c.z < -0.8):
		return "intake"
	if key in ["headlight", "projector"] and c.z < -1.4:
		return "headlight_left" if c.x < 0.0 else "headlight_right"
	# the rest of the engine bay, chassis and running gear stay with the car
	# (they still bend with the crumple frame)
	if key in ["engine", "frame", "radiator", "hose", "red"]:
		return "body"
	if key == "glass":
		# side windows face sideways; windscreen and rear glass are in the roof
		if abs(n.x) > 0.55:
			return "win_left" if c.x < 0.0 else "win_right"
		return "win_front" if c.z < 0.5 else "win_rear"
	if c.z > 1.7 and c.y > 1.0 and ax < 0.76:
		return "wing"
	if c.z < -1.72 and c.y < 0.58:
		return "bumper_front"
	if c.z > 1.95 and c.y < 0.62:
		return "bumper_rear"
	if c.z > -2.03 and c.z < -0.70 and c.y > 0.55 and n.y > 0.62 and ax < 0.75 and key in ["paint", "seam"]:
		return "bonnet"
	# front wings (fenders): the side panels from the bumper back to the door
	if key in ["paint", "seam"] and c.z > -1.95 and c.z < -0.62 and ax > 0.5 and abs(n.x) > 0.4 and c.y > 0.25:
		return "fender_left" if c.x < 0.0 else "fender_right"
	var interior := key in ["interior", "leather", "accent", "alu", "gauge"]
	if c.z > -0.555 and c.z < 0.71 and c.y > 0.22 and c.y < 0.98 and ax > (0.72 if interior else 0.5):
		return "door_left" if c.x < 0.0 else "door_right"
	return "body"

const PART_DEF := {
	# hinge point, hinge axis, opening sign, kind
	"door_left": [Vector3(-0.86, 0.6, -0.55), Vector3.UP, -1.0, "door"],
	"door_right": [Vector3(0.86, 0.6, -0.55), Vector3.UP, 1.0, "door"],
	"bonnet": [Vector3(0.0, 0.84, -0.72), Vector3.RIGHT, 1.0, "bonnet"],
	"bumper_front": [Vector3(0.75, 0.35, -1.95), Vector3.BACK, 1.0, "droop"],
	"bumper_rear": [Vector3(-0.75, 0.38, 2.05), Vector3.BACK, -1.0, "droop"],
	"wing": [Vector3(0.48, 1.0, 1.9), Vector3.BACK, 1.0, "droop"],
	# front wings hang off their rear edge and flap open in the wind
	"fender_left": [Vector3(-0.82, 0.55, -0.64), Vector3.UP, 1.0, "fender"],
	"fender_right": [Vector3(0.82, 0.55, -0.64), Vector3.UP, -1.0, "fender"],
	# pieces that just break off
	"headlight_left": [Vector3(-0.6, 0.62, -1.8), Vector3.UP, 1.0, "loose"],
	"headlight_right": [Vector3(0.6, 0.62, -1.8), Vector3.UP, 1.0, "loose"],
	"radiator": [Vector3(0.0, 0.5, -1.62), Vector3.UP, 1.0, "loose"],
	"battery": [Vector3(0.44, 0.58, -1.5), Vector3.UP, 1.0, "loose"],
	"airbox": [Vector3(-0.42, 0.62, -1.48), Vector3.UP, 1.0, "loose"],
	"intake": [Vector3(0.0, 0.72, -1.1), Vector3.UP, 1.0, "loose"],
}

func split() -> void:
	if split_done:
		return
	split_done = true
	var shell: MeshInstance3D = model.shell
	var mesh: ArrayMesh = shell.mesh
	var groups := {}    # part -> {surface index -> PackedInt32Array of triangle starts}
	var srcs := []
	for si in mesh.get_surface_count():
		var key := mesh.surface_get_name(si)
		var arr := _unindexed(mesh.surface_get_arrays(si))
		srcs.append(arr)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for t in range(0, V.size(), 3):
			var c := (V[t] + V[t + 1] + V[t + 2]) / 3.0
			var part := _classify(key, c, N[t])
			if not groups.has(part):
				groups[part] = {}
			if not groups[part].has(si):
				groups[part][si] = PackedInt32Array()
			groups[part][si].append(t)
	var meshes := {}
	for part in groups.keys():
		var am := ArrayMesh.new()
		for si in groups[part].keys():
			var src: Array = srcs[si]
			var tris: PackedInt32Array = groups[part][si]
			var V: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
			var N: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
			var C: PackedColorArray = src[Mesh.ARRAY_COLOR]
			var U: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
			var v2 := PackedVector3Array()
			var n2 := PackedVector3Array()
			var c2 := PackedColorArray()
			var u2 := PackedVector2Array()
			v2.resize(tris.size() * 3)
			n2.resize(tris.size() * 3)
			c2.resize(tris.size() * 3)
			u2.resize(tris.size() * 3)
			var w := 0
			for t in tris:
				for q in 3:
					v2[w] = V[t + q]
					n2[w] = N[t + q]
					c2[w] = C[t + q] if C.size() > 0 else Color.WHITE
					u2[w] = U[t + q] if U.size() > 0 else Vector2.ZERO
					w += 1
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = v2
			arrays[Mesh.ARRAY_NORMAL] = n2
			arrays[Mesh.ARRAY_COLOR] = c2
			arrays[Mesh.ARRAY_TEX_UV] = u2
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var ns := am.get_surface_count() - 1
			am.surface_set_material(ns, mesh.surface_get_material(si))
			am.surface_set_name(ns, mesh.surface_get_name(si))
		meshes[part] = am
	# the body keeps everything else
	shell.mesh = meshes.get("body", ArrayMesh.new())
	for part in meshes.keys():
		if part == "body":
			continue
		var am: ArrayMesh = meshes[part]
		if part.begins_with("win_"):
			var wmi := MeshInstance3D.new()
			wmi.name = part
			wmi.mesh = am
			model.body.add_child(wmi)
			windows[part] = {"mi": wmi, "mat": null, "health": 1.0, "aabb": am.get_aabb(), "crack": Vector4.ZERO, "shattered": false}
			continue
		var def: Array = model.damage_part_defs()[part] if model.has_method("damage_part_defs") else PART_DEF[part]
		var pivot := Node3D.new()
		pivot.name = part
		pivot.position = def[0]
		model.body.add_child(pivot)
		var pmi := MeshInstance3D.new()
		pmi.mesh = am
		pmi.position = -def[0]     # keeps the mesh in car-local coordinates for the shader
		pivot.add_child(pmi)
		parts[part] = {"pivot": pivot, "mi": pmi, "hinge": def[0], "axis": def[1], "sign": def[2], "kind": def[3],
			"health": 1.0, "mode": 0, "th": 0.0, "w": 0.0, "aabb": am.get_aabb(), "vel": Vector3.ZERO, "ang": Vector3.ZERO}

# plain triangle lists (3 vertices per triangle): imported models come indexed,
# but the split works triangle by triangle
static func _unindexed(arr: Array) -> Array:
	var I = arr[Mesh.ARRAY_INDEX]
	if I == null or (I as PackedInt32Array).is_empty():
		return arr
	var idx: PackedInt32Array = I
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var v2 := PackedVector3Array()
	v2.resize(idx.size())
	for k in idx.size():
		v2[k] = V[idx[k]]
	out[Mesh.ARRAY_VERTEX] = v2
	if arr[Mesh.ARRAY_NORMAL] != null:
		var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var n2 := PackedVector3Array()
		n2.resize(idx.size())
		for k in idx.size():
			n2[k] = N[idx[k]]
		out[Mesh.ARRAY_NORMAL] = n2
	else:
		var n3 := PackedVector3Array()
		n3.resize(idx.size())
		for k in range(0, idx.size(), 3):
			var fn := (v2[k + 2] - v2[k]).cross(v2[k + 1] - v2[k]).normalized()
			n3[k] = fn
			n3[k + 1] = fn
			n3[k + 2] = fn
		out[Mesh.ARRAY_NORMAL] = n3
	var C = arr[Mesh.ARRAY_COLOR]
	var c2 := PackedColorArray()
	if C != null and (C as PackedColorArray).size() > 0:
		c2.resize(idx.size())
		for k in idx.size():
			c2[k] = C[idx[k]]
	out[Mesh.ARRAY_COLOR] = c2
	var U = arr[Mesh.ARRAY_TEX_UV]
	var u2 := PackedVector2Array()
	if U != null and (U as PackedVector2Array).size() > 0:
		u2.resize(idx.size())
		for k in idx.size():
			u2[k] = U[idx[k]]
	out[Mesh.ARRAY_TEX_UV] = u2
	return out

# every mesh that shows damage, for the material swap in car_model
func damage_meshes() -> Array:
	var out := [model.shell]
	for p in parts.values():
		if p["mode"] < 2:
			out.append(p["mi"])
	for w in windows.values():
		out.append(w["mi"])
	return out

# ======================================================================= parts
static func _aabb_dist(b: AABB, p: Vector3) -> float:
	var q := Vector3(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y), clampf(p.z, b.position.z, b.end.z))
	return q.distance_to(p)

func _hit_parts(lp: Vector3, vn: float) -> void:
	for name in parts.keys():
		var p: Dictionary = parts[name]
		if p["mode"] == 2:
			continue
		var d := _aabb_dist(p["aabb"], lp)
		if d > 0.45:
			continue
		var tough := 1.3 if p["kind"] == "door" else 1.0
		p["health"] -= max(vn - 2.0, 0.0) * 0.08 * (1.0 - d / 0.45) / tough
		if p["kind"] == "mirror" and p["health"] < 0.6:
			_detach(name, vn)
		elif p["kind"] == "loose":
			if p["health"] < 0.45:
				_detach(name, vn)
		elif p["health"] < 0.1:
			_detach(name, vn)
		elif p["health"] < 0.6 and p["mode"] == 0:
			p["mode"] = 1
			p["w"] = 1.5 * signf(randf() - 0.3)

func _update_parts(dt: float) -> void:
	if parts.is_empty() or car == null:
		return
	var spd: float = car.speed
	for name in parts.keys():
		var p: Dictionary = parts[name]
		if p["mode"] != 1:
			continue
		var th: float = p["th"]
		var w: float = p["w"]
		var acc := 0.0
		var lo := 0.0
		var hi := 1.0
		var side := signf((p["hinge"] as Vector3).x)
		match p["kind"]:
			"door":
				# swings out in corners and under power, the wind pushes it shut
				acc = -car.ay_f * side * 1.6 + car.ax_f * 0.6 - 0.004 * spd * spd * sin(th) + 0.4
				lo = 0.0
				hi = 1.25
			"fender":
				# hinged at the back: braking swings it forward, the wind gets
				# behind it and flaps it open
				acc = -car.ay_f * side * 1.2 - car.ax_f * 0.6 + 0.0025 * spd * spd * cos(th) * 0.5 - 1.5 * th + 0.3
				lo = 0.0
				hi = 0.9
			"bonnet":
				# the wind lifts it, gravity drops it, it flutters
				acc = (0.009 * spd * spd - 5.0) * cos(th) + sin(Time.get_ticks_msec() * 0.023) * spd * 0.06
				lo = 0.05
				hi = 1.15
			"droop":
				# hangs off one end, bouncing on the bumps
				acc = 7.0 * cos(th) - 28.0 * th - car.vy * 0.0 + randf_range(-1.0, 1.0) * min(spd, 25.0) * 0.25
				lo = 0.0
				hi = 0.8
		w += (acc - 2.5 * w) * dt
		th += w * dt
		if th < lo:
			th = lo
			w = -w * 0.3
		elif th > hi:
			th = hi
			w = -w * 0.3
		p["th"] = th
		p["w"] = w
		(p["pivot"] as Node3D).transform.basis = Basis(p["axis"], th * p["sign"])
		# a flapping bonnet or wing at speed tears off
		if p["kind"] == "bonnet" and th > 1.1 and spd > 30.0:
			_detach(name, 6.0)
		elif p["kind"] == "fender" and th > 0.85 and spd > 22.0:
			_detach(name, 6.0)

func _detach(name: String, vn: float) -> void:
	var p: Dictionary = parts[name]
	if p["mode"] == 2:
		return
	p["mode"] = 2
	var mi: MeshInstance3D = p["mi"]
	# freeze its look: its own copies of the materials, no longer following the car
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i)
		if m:
			mi.set_surface_override_material(i, m.duplicate())
	var gt := mi.global_transform
	if car.crash_audio:
		car.crash_audio.clank(gt * mi.mesh.get_aabb().get_center(), 0.8)
	var root: Node = car.get_parent()
	mi.get_parent().remove_child(mi)
	root.add_child(mi)
	mi.global_transform = gt
	# it's flung off hard: away from the middle of the car, up, and with a
	# random spread, on top of how fast that spot of the car was moving (a
	# rolling car slings its parts off the way it's spinning). The harder the
	# hit, the faster it goes.
	var cen: Vector3 = gt * mi.mesh.get_aabb().get_center()
	var push: Vector3 = cen - car.global_position - Vector3.UP * 0.5
	push = push.normalized() if push.length() > 0.01 else Vector3.UP
	var hit_v: float = max(vn, float(car.last_hit_v))
	var kick: float = 4.0 + hit_v * 0.6
	var spread := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)) * kick * 0.35
	max_throw = max(max_throw, (push * kick + spread + Vector3(0, kick * 0.4, 0)).length())
	debris.append({"mi": mi, "vel": car.point_velocity(cen) + push * kick + spread + Vector3(0, kick * 0.4, 0),
		"ang": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (4.0 + hit_v * 0.6),
		"aabb": mi.mesh.get_aabb(), "sleep": false, "t": 0.0})

# A wheel torn off the car (a copy of its tyre + rim node): it flies off,
# lands, rolls on along the ground and finally topples over.
func throw_wheel(node: Node3D, vel: Vector3, r: float) -> void:
	var gt := node.transform          # world placement (node isn't in the tree yet)
	car.get_parent().add_child(node)
	node.global_transform = gt
	var ax := gt.basis.y.normalized()
	var vh := Vector3(vel.x, 0, vel.z)
	max_throw = max(max_throw, (vel - car.point_velocity(gt.origin)).length())
	debris.append({"mi": node, "vel": vel, "ang": Vector3.UP.cross(vh) / r + ax * randf_range(-2, 2),
		"aabb": AABB(Vector3(-r, -0.13, -r), Vector3(2 * r, 0.26, 2 * r)), "sleep": false, "t": 0.0,
		"wheel_r": r, "rolling": true})

func _update_debris(dt: float) -> void:
	if debris.is_empty():
		return
	var track = car.track
	for d in debris:
		if d["sleep"]:
			continue
		var mi: Node3D = d["mi"]
		if not is_instance_valid(mi):
			d["sleep"] = true
			continue
		var v: Vector3 = d["vel"]
		var ang: Vector3 = d["ang"]
		v.y -= 9.81 * dt
		var t := mi.global_transform
		t.origin += v * dt
		if ang.length() > 0.001:
			t.basis = Basis(ang.normalized(), ang.length() * dt) * t.basis
			t.basis = t.basis.orthonormalized()
		var b: AABB = d["aabb"]
		var low := 1e9
		var low_pt := t.origin
		if d.has("wheel_r"):
			# a wheel touches the ground on its round edge, not a box corner
			var R: float = d["wheel_r"]
			var ax := t.basis.y.normalized()
			var down := Vector3.DOWN - ax * ax.dot(Vector3.DOWN)
			low_pt = t.origin + Vector3.DOWN * 0.12 * abs(ax.y)
			if down.length() > 0.001:
				low_pt += down.normalized() * R * down.length()
			low = low_pt.y - track.ground_h(low_pt.x, low_pt.z)
			if low < 0.0 and d["rolling"]:
				var fwdr := ax.cross(Vector3.UP)
				if abs(ax.y) < 0.6 and fwdr.length() > 0.1:
					# rolling: it runs straight on, slowly losing speed, spinning to match
					fwdr = fwdr.normalized()
					var sp := v.dot(fwdr) * (1.0 - 0.25 * dt)
					t.origin.y -= low
					if v.y < -1.5 and car.crash_audio:
						car.crash_audio.clank(t.origin, clampf(-v.y / 8.0, 0.1, 1.0))
					v = fwdr * sp + Vector3(0, max(-v.y * 0.3, 0.0), 0)
					# a slow tilt grows until it falls over
					var tilt: float = d.get("tilt", randf_range(-0.15, 0.15))
					tilt *= 1.0 + dt * 1.2
					d["tilt"] = tilt
					ang = Vector3.UP.cross(v) / R + fwdr * tilt * 2.0
					if abs(sp) < 1.5:
						d["rolling"] = false
					mi.global_transform = t
					d["vel"] = v
					d["ang"] = ang
					d["t"] += dt
					continue
				d["rolling"] = false
		else:
			# ground contact on the lowest corner of the part's box
			for cx in [0, 1]:
				for cy in [0, 1]:
					for cz in [0, 1]:
						var corner: Vector3 = t * (b.position + b.size * Vector3(cx, cy, cz))
						var pen: float = track.ground_h(corner.x, corner.z) - corner.y
						if -pen < low:
							low = -pen
							low_pt = corner
		if low < 0.0:
			t.origin.y -= low
			if v.y < -1.5 and car.crash_audio:
				car.crash_audio.clank(t.origin, clampf(-v.y / 8.0, 0.1, 1.0))
			if v.y < 0.0:
				v.y = -v.y * 0.25
			v.x *= 0.82
			v.z *= 0.82
			ang *= 0.75
			# a corner touching down makes it tumble
			ang += (low_pt - t.origin).cross(Vector3.UP) * 0.5
			if v.length() < 0.4 and ang.length() < 0.4:
				d["sleep"] = true
		mi.global_transform = t
		d["vel"] = v
		d["ang"] = ang
		d["t"] += dt

# ======================================================================= glass
func setup_glass_mats(make_mat: Callable) -> void:
	for name in windows.keys():
		var w: Dictionary = windows[name]
		var mi: MeshInstance3D = w["mi"]
		var mats := []
		for i in mi.mesh.get_surface_count():
			var m: Material = make_mat.call(mi.mesh.surface_get_material(i))
			mi.set_surface_override_material(i, m)
			mats.append(m)
		w["mat"] = mats

func _hit_glass(lp: Vector3, lu: Vector3, vn: float, kind: String) -> void:
	for name in windows.keys():
		var w: Dictionary = windows[name]
		if w["shattered"]:
			continue
		var d := _aabb_dist(w["aabb"], lp)
		var reach := 0.9 if kind == "ground" else 0.55
		var hitk := 0.0
		if d < reach:
			hitk = max(vn - 3.0, 0.0) * 0.07 * (1.0 - d / reach)
		# (a bent frame cracks the glass too - that's handled in _from_frame, not
		# on every single hit)
		var b: AABB = w["aabb"]
		if hitk <= 0.0:
			continue
		w["health"] -= hitk
		var cpt := Vector3(clampf(lp.x, b.position.x, b.end.x), clampf(lp.y, b.position.y, b.end.y), clampf(lp.z, b.position.z, b.end.z))
		var amt := clampf(1.0 - w["health"], 0.0, 1.0)
		if w["crack"].w == 0.0:
			w["crack"] = Vector4(cpt.x, cpt.y, cpt.z, amt)
		else:
			w["crack"].w = amt
		for m in w["mat"]:
			if m is ShaderMaterial:
				m.set_shader_parameter("crack_c", w["crack"])
		if w["health"] <= 0.0:
			_shatter(name, lu)

func _shatter(name: String, lu: Vector3) -> void:
	var w: Dictionary = windows[name]
	w["shattered"] = true
	var mi: MeshInstance3D = w["mi"]
	mi.visible = false
	if car.crash_audio:
		car.crash_audio.glass(0.9)
	_ensure_shards()
	var ps := GPUParticles3D.new()
	var pm: ParticleProcessMaterial = shard_mat.duplicate()
	var b: AABB = w["aabb"]
	pm.emission_box_extents = b.size * 0.5
	var gt: Transform3D = mi.global_transform
	pm.direction = (gt.basis * -lu).normalized() + Vector3(0, 0.3, 0)
	ps.process_material = pm
	ps.draw_pass_1 = shard_mesh
	ps.amount = 120
	ps.lifetime = 1.6
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.local_coords = false
	ps.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	car.get_parent().add_child(ps)
	ps.global_position = gt * b.get_center()
	ps.emitting = true
	get_tree().create_timer(2.5).timeout.connect(ps.queue_free)

# The glass shard particles' shaders compile the first time they're drawn,
# which froze the game for a moment on the first window to break. Draw one
# hidden shard when the car is set up so that happens at load time instead.
func prewarm() -> void:
	_ensure_shards()
	var ps := GPUParticles3D.new()
	ps.process_material = shard_mat
	ps.draw_pass_1 = shard_mesh
	ps.amount = 1
	ps.lifetime = 0.2
	ps.one_shot = true
	add_child(ps)
	ps.position = Vector3(0, -3, 0)     # under the car, out of sight
	ps.emitting = true
	get_tree().create_timer(1.0).timeout.connect(ps.queue_free)

func _ensure_shards() -> void:
	if shard_mat == null:
		shard_mat = ParticleProcessMaterial.new()
		shard_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		shard_mat.spread = 70.0
		shard_mat.initial_velocity_min = 1.0
		shard_mat.initial_velocity_max = 4.0
		shard_mat.gravity = Vector3(0, -9.8, 0)
		shard_mat.scale_min = 0.4
		shard_mat.scale_max = 1.2
		shard_mat.angle_min = -180.0
		shard_mat.angle_max = 180.0
		shard_mesh = QuadMesh.new()
		shard_mesh.size = Vector2(0.035, 0.025)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.85, 0.92, 1.0, 0.85)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.metallic = 0.6
		sm.roughness = 0.05
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		shard_mesh.material = sm

# ======================================================================= repair
func repair() -> void:
	repair_frame()
	_rv_repair()
	for name in parts.keys():
		var p: Dictionary = parts[name]
		var mi: MeshInstance3D = p["mi"]
		if p["mode"] == 2:
			mi.get_parent().remove_child(mi)
			p["pivot"].add_child(mi)
			mi.transform = Transform3D(Basis(), -p["hinge"])
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, null)
		p["mode"] = 0
		p["health"] = 1.0
		p["th"] = 0.0
		p["w"] = 0.0
		(p["pivot"] as Node3D).transform.basis = Basis()
	for d in debris:
		if d.has("wheel_r") and is_instance_valid(d["mi"]):
			(d["mi"] as Node3D).queue_free()      # thrown wheels are copies
	debris.clear()
	for name in windows.keys():
		var w: Dictionary = windows[name]
		w["health"] = 1.0
		w["shattered"] = false
		w["crack"] = Vector4.ZERO
		(w["mi"] as MeshInstance3D).visible = true
		if w["mat"]:
			for m in w["mat"]:
				if m is ShaderMaterial:
					m.set_shader_parameter("crack_c", Vector4.ZERO)

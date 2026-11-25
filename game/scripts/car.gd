# Rear-wheel-drive drift car: bicycle model with Pacejka-style tyres,
# friction circle on the driven axle, wheelspin, handbrake and weight transfer.
extends Node3D

const CarModel = preload("res://scripts/car_model.gd")
const CrashAudio = preload("res://scripts/crash_audio.gd")
const SmokeFx = preload("res://scripts/smoke_fx.gd")

signal drift_banked(points: int)
signal drift_failed
signal lap_completed(time: float, best: float)

# --- vehicle constants (350Z-ish, drift setup)
const MASS := 1450.0
const IZ := 2350.0
const A := 1.25            # CG -> front axle
const B := 1.40            # CG -> rear axle
const WB := A + B
const H_CG := 0.48
const G := 9.81
# --- handling (grippy tarmac drift setup)
var mu_road := 1.05
var mu_grass := 0.6
var tyre_bf := 9.0
var tyre_cf := 1.4
var tyre_br := 9.5
var tyre_cr := 1.55
var drag_k := 0.42
var roll_road := 0.015
var hb_k := 0.42
var stab_k := 1.0
var stab_start := 0.6
var long_k := 1.0          # forward grip multiplier
const WHEEL_R := 0.33
const GEARS := [0.0, 3.79, 2.32, 1.62, 1.27, 1.0, 0.79]
const REV_RATIO := 3.38
const FINAL := 3.54
const IDLE := 900.0
const REDLINE := 7400.0
const MAX_STEER := 0.72    # ~41 deg drift lock
const BRAKE_FORCE := 13000.0

var track
var forest
var model

# --- state
var vel := Vector3.ZERO
var yaw := 0.0
var yaw_rate := 0.0
var steer := 0.0
var gear := 1
var rpm := IDLE
var auto_gear := true
var spin := 0.0            # rear wheelspin surplus (m/s)
var ax_f := 0.0            # filtered longitudinal accel
var ay_f := 0.0            # filtered lateral accel
var track_idx := -1
var on_road := true
var rear_slide := 0.0
var body_slip := 0.0
var speed := 0.0
var rev_hold := 0.0
var shift_timer := 0.0
var wf := 0.0
var wr := 0.0
var odometer := 0.0
# ---- sprung rigid body: height, pitch and roll are simulated, not copied from the
# ground. Four spring/damper wheels push the body up wherever they touch; gravity
# pulls it down; the chassis itself can hit the ground if it bottoms out or flips.
const K_SPRING := 32000.0      # per wheel (~1.5 Hz ride)
const C_BUMP := 1900.0         # damper, compression
const C_REBOUND := 3300.0      # damper, extension
const BUMP_TRAVEL := 0.10      # travel above static before the bump stop
const I_PITCH := 2200.0
const I_ROLL := 620.0
const WHEEL_LOCAL := [Vector3(-0.77, 0, -A), Vector3(0.77, 0, -A), Vector3(-0.78, 0, B), Vector3(0.78, 0, B)]
const CHASSIS_PTS := [
	Vector3(-0.85, 0.16, -2.05), Vector3(0.85, 0.16, -2.05), Vector3(-0.85, 0.16, 2.1), Vector3(0.85, 0.16, 2.1),
	Vector3(-0.7, 1.28, -0.5), Vector3(0.7, 1.28, -0.5), Vector3(-0.7, 1.28, 0.9), Vector3(0.7, 1.28, 0.9),
	Vector3(-0.9, 0.7, 0.0), Vector3(0.9, 0.7, 0.0)]
# The body's outer shell as contact points, for the free rigid-body mode
# (airborne, tumbling, on its side or roof). Each one pushes back off the
# ground and drags along it with friction wherever it touches, so the roof,
# pillars, sides and bumpers all take their own hits.
const HULL_PTS := [
	# bumper corners, low
	Vector3(-0.85, 0.16, -2.05), Vector3(0.85, 0.16, -2.05), Vector3(-0.85, 0.16, 2.1), Vector3(0.85, 0.16, 2.1),
	# tops of the front wings and rear quarters
	Vector3(-0.88, 0.72, -1.95), Vector3(0.88, 0.72, -1.95), Vector3(-0.88, 0.75, 2.05), Vector3(0.88, 0.75, 2.05),
	# door sides
	Vector3(-0.9, 0.7, 0.0), Vector3(0.9, 0.7, 0.0), Vector3(-0.9, 0.3, -0.7), Vector3(0.9, 0.3, -0.7),
	Vector3(-0.9, 0.3, 0.9), Vector3(0.9, 0.3, 0.9),
	# base of the windscreen pillars and the top of the rear hatch
	Vector3(-0.8, 0.95, -1.05), Vector3(0.8, 0.95, -1.05), Vector3(-0.75, 1.0, 1.7), Vector3(0.75, 1.0, 1.7),
	# roof: four corners and the middle
	Vector3(-0.66, 1.28, -0.45), Vector3(0.66, 1.28, -0.45), Vector3(-0.66, 1.28, 0.85), Vector3(0.66, 1.28, 0.85),
	Vector3(0.0, 1.31, 0.2)]
const CG_LOCAL := Vector3(0.0, H_CG, 0.0)   # centre of mass above the body origin (road level at rest)
const MU_BODY := 0.55                       # paint / metal sliding on tarmac
# free rigid-body state (only while `rigid`): orientation, spin, centre of mass
var rigid := false
var rb_basis := Basis.IDENTITY
var rb_w := Vector3.ZERO       # angular velocity, world frame (rad/s)
var rb_v := Vector3.ZERO       # velocity of the centre of mass
var rb_cg := Vector3.ZERO      # position of the centre of mass
var rb_wheels := 0             # wheels touching the ground this step
var c0 := [0.0, 0.0, 0.0, 0.0]          # static compression per wheel
var wheel_comp := [0.0, 0.0, 0.0, 0.0]
var wheel_load := [0.0, 0.0, 0.0, 0.0]
var wheel_gh := [NAN, NAN, NAN, NAN]    # last effective ground height per wheel
var vy := 0.0
var pitch := 0.0
var roll := 0.0
var pitch_rate := 0.0
var roll_rate := 0.0
var grip_f := 1.0              # front / rear tyre load vs. what the tyre model expects
var grip_r := 1.0
var nf_model := 1.0
var nr_model := 1.0
var grounded := true
var air_time := 0.0
var flipped_time := 0.0
var land_damp := 0.0      # 0..1, extra suspension damping just after a hard landing
signal air_landed(seconds: float, points: int)

func _land(_impact: float) -> void:
	if air_time > 0.3:
		var pts := int(air_time * 150.0 * (1.0 + speed / 30.0))
		total_score += pts
		air_landed.emit(air_time, pts)
	air_time = 0.0

var dbg := ""
var hits := 0

# --- inputs (set by main each frame)
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0        # -1 left .. +1 right
var in_handbrake := 0.0
var in_analog := false
var wheel_hold := false     # VR: a hand is on the steering wheel
var wheel_target := 0.0     # VR: front-wheel angle the steering wheel asks for (rad, + = left)
var assist := 0.6          # countersteer assist (0..1)

# --- scoring
var drift_points := 0.0
var drift_time := 0.0
var drift_idle := 0.0
var drift_mult := 1
var total_score := 0
var best_combo := 0
var lap_time := 0.0
var best_lap := 0.0
var last_lap := 0.0
var laps := 0
var passed_half := false
# --- Cache points: at the end of every lap the score earned in that lap (drifts
# + jumps) is multiplied by how quick the lap was vs. a par time, and paid out.
# The endless road has no laps, so every kilometre counts as one.
signal points_earned(lap_score: int, time_mult: float, points: int)
const PAR_SPEED := 75.0 / 3.6     # m/s: a lap at this average speed pays x1.0
const MULT_MIN := 0.25
const MULT_MAX := 3.0
const ENDLESS_STAGE := 1000.0      # metres per "lap" on the endless road
var lap_score_start := 0           # total_score when this lap started
var stage_time := 0.0              # endless road: time in the current kilometre
var stage_odo := 0.0               # endless road: odometer when it started

func time_mult(t: float, length: float) -> float:
	if t <= 0.0:
		return MULT_MIN
	return clampf((length / PAR_SPEED) / t, MULT_MIN, MULT_MAX)

func _pay_lap(t: float, length: float) -> void:
	var lap_score := total_score - lap_score_start
	lap_score_start = total_score
	var m := time_mult(t, length)
	points_earned.emit(lap_score, m, int(round(lap_score * m)))

# --- effects
var smoke: Array[GPUParticles3D] = []
var skid_mm: MultiMesh
var skid_next := 0
const SKID_MAX := 4000
var skid_last := [Vector3.INF, Vector3.INF]

func setup(p_track, p_forest, fx_parent: Node3D) -> void:
	track = p_track
	forest = p_forest
	model = CarModel.new()
	add_child(model)
	model.build()
	_build_effects(fx_parent)
	crash_audio = CrashAudio.new()
	crash_audio.name = "CrashAudio"
	add_child(crash_audio)
	crash_audio.setup(self)
	reset_to(0)

var steer_k := 1.0         # steering lock multiplier
var front_k := 1.0         # front tyre grip multiplier

func reset_to(idx: int) -> void:
	var p: Vector3 = track.pts[idx]
	var t: Vector3 = track.tans[idx]
	yaw = atan2(-t.x, -t.z)
	vel = Vector3.ZERO
	yaw_rate = 0.0
	steer = 0.0
	spin = 0.0
	gear = 1
	global_position = Vector3(p.x, p.y + 0.05, p.z) + t * 8.0
	global_position.y = track.ground_h(global_position.x, global_position.z) + 0.05
	var sf := MASS * G * B / WB * 0.5
	var sr := MASS * G * A / WB * 0.5
	c0 = [sf / K_SPRING, sf / K_SPRING, sr / K_SPRING, sr / K_SPRING]
	wheel_gh = [NAN, NAN, NAN, NAN]
	vy = 0.0
	pitch = 0.0
	roll = 0.0
	pitch_rate = 0.0
	roll_rate = 0.0
	grip_f = 1.0
	grip_r = 1.0
	grounded = true
	air_time = 0.0
	flipped_time = 0.0
	rigid = false
	rb_w = Vector3.ZERO
	track_idx = track.nearest_index(global_position, -1)
	_cancel_drift(false)

# Backspace: back to the start line with a fresh lap timer (best lap is kept)
func restart() -> void:
	reset_to(0)
	lap_time = 0.0
	laps = 0
	passed_half = false
	odometer = 0.0
	lap_score_start = total_score
	stage_time = 0.0
	stage_odo = 0.0
	skid_last = [Vector3.INF, Vector3.INF]
	model.repair()   # Backspace also fixes all body damage
	repair_mech()

func reset_on_track() -> void:
	reset_to(track.nearest_index(global_position, track_idx))

# ---------------------------------------------------------------- physics
static func pacejka(alpha: float, b: float, c: float) -> float:
	return sin(c * atan(b * alpha))

func torque_at(r: float) -> float:
	# drift-tuned VQ35: ~430 Nm peak around 4800 rpm
	var x := (r - 4800.0) / 4300.0
	return 430.0 * clampf(1.0 - x * x * 0.85, 0.45, 1.0)

var prof_ms := 0.0     # time this physics tick took (read by the --fps test)

# ---------------------------------------------------------------- mechanical damage
# (only with Car damage on) read from the crumple frame after each hit
var wheel_dmg := [0.0, 0.0, 0.0, 0.0]   # FL FR RL RR, 0 = fine .. 1 = wrecked
var engine_dmg := 0.0                    # radiator / engine bay crush
var engine_temp := 0.0                   # 0 = normal, 1 = overheating
var axle_broken := [false, false]        # RL, RR driveshafts
var steer_bias := 0.0                    # bent front wheels pull the car
var yaw_bias := 0.0                      # bent rear wheels drag it round
var grip_dmg_f := 1.0
var grip_dmg_r := 1.0
var power_k := 1.0
var spring_k := [1.0, 1.0, 1.0, 1.0]
var steer_broken := 0.0                   # 0..1, a bent steering arm loses lock
var mech_dirty := false
var steam: GPUParticles3D
var engine_smoke_dark: GPUParticles3D
var mech_on := true        # Settings > Car damage > Effects
var force_smoke := false   # dev aid for screenshots

var mech_engine := true    # Effects > Engine damage
var mech_wheels := true    # Effects > Wheel damage
var wheels_fall := true    # Effects > Wheel damage > Wheels fall off
var wheel_off := [false, false, false, false]
var hub_drag := [0.0, 0.0, 0.0, 0.0]     # ground force on a bare hub (for the drag)

func set_mech_effects(on: bool) -> void:
	mech_on = on
	if not on:
		repair_mech()      # looks-only damage: the car drives as normal

func set_mech_options(engine_on: bool, wheels_on: bool, fall_on: bool) -> void:
	mech_engine = engine_on
	mech_wheels = wheels_on
	wheels_fall = fall_on
	if not engine_on:
		engine_dmg = 0.0
		engine_temp = 0.0
	if not wheels_on:
		wheel_dmg = [0.0, 0.0, 0.0, 0.0]
		axle_broken = [false, false]
		steer_bias = 0.0
		yaw_bias = 0.0
		grip_dmg_f = 1.0
		grip_dmg_r = 1.0
		spring_k = [1.0, 1.0, 1.0, 1.0]
		steer_broken = 0.0
		model.wheel_camber = [0.0, 0.0, 0.0, 0.0]
		model.wheel_wobble = [0.0, 0.0, 0.0, 0.0]
	mech_dirty = true

# a wrecked wheel tears off: tyre and rim fly away, the hub drops onto the road
func _lose_wheel(i: int) -> void:
	if wheel_off[i]:
		return
	wheel_off[i] = true
	var node: Node3D = model.detach_wheel(i)
	if node and model.damage:
		var bas := _body_basis()
		var out: Vector3 = bas.x * signf((WHEEL_LOCAL[i] as Vector3).x)
		model.damage.throw_wheel(node, vel * 0.9 + out * randf_range(2.0, 4.0) + Vector3(0, randf_range(1.5, 3.0), 0), WHEEL_R)
	if crash_audio:
		crash_audio.clank(global_position, 1.0)
	if i >= 2:
		axle_broken[i - 2] = true

# ---------------------------------------------------------------- crash feel
var shake := 0.0           # camera shake (camera_rig.gd reads it), decays
var scrape_level := 0.0    # metal scraping on a rail / the ground, for the sound
var crash_audio            # crash_audio.gd
var crash_cool := 0.0

# every collision, damage setting on or off: the body lurches with the impact,
# the camera shakes and the crash is heard
func _crash_feel(j: Vector3, vn: float, kind: String) -> void:
	if vn < 1.0:
		return
	if j != Vector3.ZERO:
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		# hard braking from the hit dives the nose; a side hit rolls the body away
		pitch_rate += j.dot(fwd) * 0.045
		roll_rate -= j.dot(right) * 0.05
	shake = max(shake, clampf((vn - 1.5) / 16.0, 0.0, 1.0))
	if crash_audio and crash_cool <= 0.0:
		crash_audio.crash(vn, kind)
		crash_cool = 0.12

# one collision: body damage (if enabled) and mechanical damage
func _impact(kind: String, wp: Vector3, push: Vector3, axis: Vector3, vn: float, radius: float) -> void:
	if not model.damage_enabled:
		return
	model.impact(kind, wp, push, axis, vn, radius)
	mech_dirty = true

func _update_mech(dt: float) -> void:
	if not model.damage_enabled or model.damage == null or not mech_on:
		return
	var dmg = model.damage
	# keep reading the frame while a crush is still working its way through it
	if mech_dirty or not dmg.obstacles.is_empty():
		mech_dirty = false
		if mech_wheels:
			for i in 4:
				wheel_dmg[i] = max(wheel_dmg[i], dmg.corner_damage(i))
				if wheel_off[i]:
					wheel_dmg[i] = 1.0
				elif wheels_fall and wheel_dmg[i] >= 0.99:
					_lose_wheel(i)
		if mech_engine:
			engine_dmg = max(engine_dmg, dmg.engine_damage())
		axle_broken[0] = axle_broken[0] or wheel_dmg[2] > 0.85
		axle_broken[1] = axle_broken[1] or wheel_dmg[3] > 0.85
		# a bent front wheel toes out and pulls the car towards that side
		steer_bias = (wheel_dmg[0] - wheel_dmg[1]) * 0.09
		yaw_bias = (wheel_dmg[2] - wheel_dmg[3]) * 2600.0
		grip_dmg_f = 1.0 - 0.35 * (wheel_dmg[0] + wheel_dmg[1]) * 0.5
		grip_dmg_r = 1.0 - 0.35 * (wheel_dmg[2] + wheel_dmg[3]) * 0.5
		for i in 4:
			spring_k[i] = 0.35 if wheel_dmg[i] > 0.7 else 1.0 - wheel_dmg[i] * 0.2
			model.wheel_camber[i] = wheel_dmg[i] * 0.2
			model.wheel_wobble[i] = max(wheel_dmg[i] - 0.3, 0.0) * 0.12
		# a wrecked front corner: the steering arm is bent, you lose lock
		steer_broken = clampf((max(wheel_dmg[0], wheel_dmg[1]) - 0.6) / 0.4, 0.0, 1.0)
		if not mech_wheels:
			steer_bias = 0.0
			yaw_bias = 0.0
			steer_broken = 0.0
		# parts torn out of the engine bay
		if mech_engine:
			if dmg.part_off("radiator"):
				engine_dmg = max(engine_dmg, 0.6)        # no cooling: it will overheat
			if dmg.part_off("intake"):
				engine_dmg = max(engine_dmg, 0.75)
			if dmg.part_off("battery"):
				engine_dmg = 1.0                          # no electrics: the engine dies
		model.headlight_broken(0, dmg.part_off("headlight_left"))
		model.headlight_broken(1, dmg.part_off("headlight_right"))
	# a crushed radiator: the engine heats up under load, then limps
	if engine_dmg > 0.2:
		var heat: float = rpm / REDLINE * engine_dmg * 0.6 * in_throttle
		var cool: float = 0.18 * (1.0 - engine_dmg)
		engine_temp = clampf(engine_temp + (heat - cool) * dt, 0.0, 1.3)
	else:
		engine_temp = max(engine_temp - 0.1 * dt, 0.0)
	power_k = 1.0 - 0.5 * engine_dmg
	if engine_temp > 1.0:
		power_k *= 0.35       # limp mode
	if engine_dmg > 0.97:
		power_k = 0.0         # engine's gone
	var drive_wheels := 2 - int(axle_broken[0]) - int(axle_broken[1])
	power_k *= drive_wheels / 2.0
	# white steam when the radiator's hit or the engine's hot; thick dark smoke
	# when the engine itself is wrecked or cooking
	var steaming := engine_dmg > 0.3 or engine_temp > 0.8
	var burning := engine_dmg > 0.6 or engine_temp > 1.0
	if steaming and steam == null:
		steam = SmokeFx.engine_smoke(false)
		add_child(steam)
	if burning and engine_smoke_dark == null:
		engine_smoke_dark = SmokeFx.engine_smoke(true)
		add_child(engine_smoke_dark)
	if steam:
		steam.emitting = steaming
		steam.amount_ratio = clampf(max(engine_dmg, engine_temp - 0.4), 0.25, 1.0)
	if engine_smoke_dark:
		engine_smoke_dark.emitting = burning
		engine_smoke_dark.amount_ratio = clampf(max(engine_dmg - 0.4, engine_temp - 0.9) * 1.6, 0.3, 1.0)

func repair_mech() -> void:
	wheel_dmg = [0.0, 0.0, 0.0, 0.0]
	wheel_off = [false, false, false, false]
	hub_drag = [0.0, 0.0, 0.0, 0.0]
	model.reattach_wheels()
	engine_dmg = 0.0
	engine_temp = 0.0
	axle_broken = [false, false]
	steer_bias = 0.0
	yaw_bias = 0.0
	grip_dmg_f = 1.0
	grip_dmg_r = 1.0
	power_k = 1.0
	spring_k = [1.0, 1.0, 1.0, 1.0]
	steer_broken = 0.0
	model.headlight_broken(0, false)
	model.headlight_broken(1, false)
	model.wheel_camber = [0.0, 0.0, 0.0, 0.0]
	model.wheel_wobble = [0.0, 0.0, 0.0, 0.0]
	if steam:
		steam.emitting = false
	if engine_smoke_dark:
		engine_smoke_dark.emitting = false

func _physics_process(delta: float) -> void:
	var t_start := Time.get_ticks_usec()
	_physics_tick(delta)
	prof_ms = (Time.get_ticks_usec() - t_start) / 1000.0

func _physics_tick(delta: float) -> void:
	var sub := 4
	var dt := delta / sub
	for i in sub:
		# off the ground, or tipped past ~45 degrees: the tyre model no longer
		# applies, so the car becomes a free rigid body until it's back on its wheels
		if not rigid and (not grounded or _body_basis().y.y < 0.7):
			_enter_rigid()
		if rigid:
			_step_rigid(dt)
			if rb_wheels >= 3 and rb_basis.y.y > 0.9 and (rb_w - Vector3.UP * rb_w.y).length() < 2.0:
				_exit_rigid()
		else:
			_step(dt)
			_step_body(dt)
	_post_step(delta)

func _body_basis() -> Basis:
	if rigid:
		return rb_basis
	return Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(pitch, 0.0, roll))

# ---------------------------------------------------------------- free rigid body
# Hand-over from the driving model (yaw / pitch / roll angles and their rates,
# rotating about the body origin) to a full 3D rigid body rotating about its
# centre of mass, with the same motion at the moment of switching.
func _enter_rigid() -> void:
	var bas := _body_basis()
	var pitch_ax := Vector3(cos(yaw), 0.0, -sin(yaw))
	rb_w = Vector3.UP * yaw_rate + pitch_ax * pitch_rate + bas.z * roll_rate
	rb_basis = bas
	var r_cg: Vector3 = bas * CG_LOCAL
	rb_cg = global_position + r_cg
	rb_v = Vector3(vel.x, vy, vel.z) + rb_w.cross(r_cg)
	rb_wheels = 0
	rigid = true

func _exit_rigid() -> void:
	var bas := rb_basis
	var e := bas.get_euler(EULER_ORDER_YXZ)
	pitch = e.x
	yaw = e.y
	roll = e.z
	# angular velocity -> rates of the three angles (well conditioned: upright here)
	var pitch_ax := Vector3(cos(yaw), 0.0, -sin(yaw))
	var rates: Vector3 = Basis(Vector3.UP, pitch_ax, bas.z).inverse() * rb_w
	yaw_rate = rates.x
	pitch_rate = rates.y
	roll_rate = rates.z
	var v_o: Vector3 = rb_v + rb_w.cross(global_position - rb_cg)
	vel = Vector3(v_o.x, 0.0, v_o.z)
	vy = v_o.y
	wheel_gh = [NAN, NAN, NAN, NAN]
	rigid = false

func _ground_normal(x: float, z: float, h: float) -> Vector3:
	var hx: float = track.ground_h(x + 0.3, z)
	var hz: float = track.ground_h(x, z + 0.3)
	return Vector3(h - hx, 0.3, h - hz).normalized()

# One step of a rigid body: gravity at the centre of mass, and a contact force
# (stiff spring + damper along the ground normal, Coulomb friction along it) at
# every point of the shell or wheel that's in the ground. Spin follows Euler's
# equations with the car's own inertia, so tumbles, roof landings and slides
# all come out of the same physics.
func _step_rigid(dt: float) -> void:
	var bas := rb_basis
	var origin: Vector3 = rb_cg - bas * CG_LOCAL
	var force := Vector3(0.0, -MASS * G, 0.0)
	var torque := Vector3.ZERO
	var scrape := 0.0
	var wheels := 0
	var hard_hit := 0.0
	var hit_pt := Vector3.ZERO
	var hit_n := Vector3.UP
	# --- shell (and any bare hub where a wheel has come off)
	var pts: Array = HULL_PTS.duplicate()
	for i in 4:
		if wheel_off[i]:
			pts.append((WHEEL_LOCAL[i] as Vector3) + Vector3(0.0, WHEEL_R - 0.165, 0.0))
	for p in pts:
		var wp: Vector3 = origin + bas * (p as Vector3)
		var gh: float = track.ground_h(wp.x, wp.z)
		var pen := gh - wp.y
		if pen <= 0.0:
			continue
		var n := _ground_normal(wp.x, wp.z, gh)
		var r := wp - rb_cg
		var vp: Vector3 = rb_v + rb_w.cross(r)
		var vn := vp.dot(n)
		var pn := pen * n.y
		# metal on the ground: stiff going in, almost no push back out
		# (the panels crumple and soak up the energy rather than bouncing)
		var fn: float = max(160000.0 * pn - 18000.0 * vn, 0.0) if vn <= 0.0 else max(40000.0 * pn - 30000.0 * vn, 0.0)
		var vt := vp - n * vn
		# Coulomb friction; below 2 cm/s it acts as a stiff damper so a resting car grips
		var ft: Vector3 = -vt / max(vt.length(), 0.02) * MU_BODY * fn
		var f: Vector3 = n * fn + ft
		force += f
		torque += r.cross(f)
		scrape += fn
		if -vn > hard_hit:
			hard_hit = -vn
			hit_pt = wp
			hit_n = n
	# --- wheels: suspension springs pushing off the ground, tyres resisting
	# sideways sliding (they roll freely forwards). Only when they're underneath.
	if bas.y.y > 0.2:
		for i in 4:
			wheel_load[i] = 0.0
			if wheel_off[i]:
				continue
			var wp: Vector3 = origin + bas * (WHEEL_LOCAL[i] as Vector3)
			var gh: float = track.ground_h(wp.x, wp.z)
			var comp: float = gh - wp.y + c0[i]
			wheel_comp[i] = comp
			if comp <= 0.0:
				continue
			wheels += 1
			var n := _ground_normal(wp.x, wp.z, gh)
			var r := wp - rb_cg
			var vp: Vector3 = rb_v + rb_w.cross(r)
			var vn := vp.dot(n)
			var fs: float = K_SPRING * spring_k[i] * comp - (C_REBOUND if vn > 0.0 else C_BUMP) * vn
			var over: float = comp - c0[i] - BUMP_TRAVEL
			if over > 0.0:
				fs += K_SPRING * 10.0 * over - C_BUMP * 3.0 * min(vn, 0.0)
			fs = max(fs, 0.0)
			wheel_load[i] = fs
			var side := bas.x - n * bas.x.dot(n)
			side = side.normalized() if side.length() > 0.01 else bas.x
			var fwd_ax := side.cross(n)
			var v_side := vp.dot(side)
			var v_fwd := vp.dot(fwd_ax)
			var f := n * fs
			f -= side * clampf(v_side / 0.4, -1.0, 1.0) * mu_road * fs
			f -= fwd_ax * clampf(v_fwd / 0.4, -1.0, 1.0) * roll_road * fs
			force += f
			torque += r.cross(f)
	else:
		for i in 4:
			wheel_load[i] = 0.0
			wheel_comp[i] = -1.0
	# --- air drag on the body
	var hv := Vector3(rb_v.x, 0.0, rb_v.z)
	force -= hv * hv.length() * drag_k
	# --- integrate: linear, then Euler's equations in the body frame
	rb_v += force / MASS * dt
	rb_cg += rb_v * dt
	var inertia := Vector3(I_PITCH, IZ, I_ROLL)
	var bt := bas.transposed()
	var wb: Vector3 = bt * rb_w
	var tb: Vector3 = bt * torque
	wb += (tb - wb.cross(wb * inertia)) / inertia * dt
	rb_w = bas * wb
	var wl := rb_w.length()
	if wl > 1e-6:
		bas = Basis(rb_w / wl, wl * dt) * bas
	rb_basis = bas.orthonormalized()
	# --- hand the result to the rest of the car (camera, HUD, sound, trees, rails)
	origin = rb_cg - rb_basis * CG_LOCAL
	global_position = origin
	var e := rb_basis.get_euler(EULER_ORDER_YXZ)
	pitch = e.x
	yaw = e.y
	roll = e.z
	var v_o: Vector3 = rb_v + rb_w.cross(origin - rb_cg)
	vel = Vector3(v_o.x, 0.0, v_o.z)
	vy = v_o.y
	speed = vel.length()
	yaw_rate = rb_w.y
	# trees and guardrails push the car around in the plane: carry their
	# corrections back into the rigid body
	var vel0 := vel
	var yr0 := yaw_rate
	_collide_trees(dt)
	rb_cg += global_position - origin
	rb_v += vel - vel0
	rb_w.y += yaw_rate - yr0
	# --- effects of the contacts
	if scrape > 0.0:
		scrape_level = max(scrape_level, clampf(speed / 12.0, 0.0, 1.0) * clampf(scrape / (MASS * G * 0.3), 0.2, 1.0))
		_cancel_drift(drift_points > 0.0)
	if hard_hit > 3.5:
		# slamming the roof, a pillar, a corner or a side into the ground
		_crash_feel(Vector3.ZERO, hard_hit * 0.8, "ground")
		_impact("ground", hit_pt, hit_n, Vector3.ZERO, hard_hit, 0.0)
	var was_wheels := rb_wheels > 0
	rb_wheels = wheels
	grounded = wheels > 0
	if grounded and not was_wheels:
		_land(hard_hit)
	# engine and wheels with nothing to push against
	steer = move_toward(steer, -in_steer * MAX_STEER * 0.8, 4.0 * dt)
	var thr := in_throttle if gear != -1 else in_brake
	rpm = move_toward(rpm, lerpf(IDLE + 1500.0, REDLINE, thr), 9000.0 * dt)
	rear_slide = 0.0
	wr = lerpf(wr, rpm / 9.549 / (GEARS[max(gear, 1)] * FINAL), min(1.0, dt * 5.0))

# Ground height a wheel of radius WHEEL_R actually rides on: the tyre touches a
# step or kerb before its centre is over it, so edges become short ramps.
func _wheel_ground(x: float, z: float, dir: Vector3) -> float:
	var h: float = track.ground_h(x, z)
	for d in [-0.22, 0.22]:
		var dd: float = d
		var hs: float = track.ground_h(x + dir.x * dd, z + dir.z * dd)
		h = max(h, hs - (WHEEL_R - sqrt(WHEEL_R * WHEEL_R - dd * dd)))
	return h

# Vertical rigid-body step: heave, pitch and roll driven by the four suspension
# corners, chassis contacts, gravity and the tyres' weight-transfer torques.
func _step_body(dt: float) -> void:
	var bas := _body_basis()
	var pos := global_position
	var hv := Vector3(vel.x, 0, vel.z)
	var hs := hv.length()
	var dir: Vector3 = hv / hs if hs > 0.5 else Vector3(-sin(yaw), 0.0, -cos(yaw))
	# the body is Ry(yaw) * Rx(pitch) * Rz(roll): pitch turns about the level
	# "right" axis, roll about the body's own z. (Using the body's x for pitch
	# flipped the sign upside down, so the ground pushed the car over instead of
	# settling it: it floated and spun on its roof.)
	var pitch_ax := Vector3(cos(yaw), 0.0, -sin(yaw))
	var omega: Vector3 = pitch_ax * pitch_rate + bas.z * roll_rate + Vector3.UP * yaw_rate
	var fy := -MASS * G
	var torque := Vector3.ZERO
	var n_contact := 0
	var was_grounded := grounded
	var hub_scrape := 0.0
	for i in 4:
		var r: Vector3 = bas * (WHEEL_LOCAL[i] as Vector3)
		var wp := pos + r
		if wheel_off[i]:
			# no wheel: the bare hub / brake disc (0.165 m above where the tyre
			# touched) digs into the road - metal contact, no spring, no grip
			var hr: Vector3 = r + bas.y * (WHEEL_R - 0.165)
			var hp := pos + hr
			var hpen: float = track.ground_h(hp.x, hp.z) - hp.y
			var hf := 0.0
			if hpen > 0.0:
				var hv2: float = vy + omega.cross(hr).y
				hf = max(160000.0 * hpen - 18000.0 * hv2, 0.0) if hv2 <= 0.0 else max(40000.0 * hpen - 30000.0 * hv2, 0.0)
			hub_drag[i] = hf
			hub_scrape += hf
			wheel_comp[i] = -1.0
			wheel_load[i] = 0.0
			wheel_gh[i] = NAN
			fy += hf
			torque += hr.cross(Vector3(0, hf, 0))
			continue
		var gh := _wheel_ground(wp.x, wp.z, dir)
		var g_rate := 0.0
		if not is_nan(wheel_gh[i]):
			g_rate = clampf((gh - wheel_gh[i]) / dt, -6.0, 6.0)
		wheel_gh[i] = gh
		var comp: float = gh - wp.y + c0[i]
		var rel_v: float = vy + omega.cross(r).y - g_rate      # + = extending
		var f := 0.0
		if comp > 0.0:
			n_contact += 1
			# after a hard landing the dampers soak it up instead of springing back
			var reb: float = C_REBOUND * (1.0 + 5.0 * land_damp)
			f = K_SPRING * spring_k[i] * comp - (reb if rel_v > 0.0 else C_BUMP) * rel_v
			var over: float = comp - c0[i] - BUMP_TRAVEL
			if over > 0.0:
				# bump stop: hard going in, but it hardly pushes back out (rubber
				# and bent metal absorb the energy: a thud, not a bounce)
				if rel_v < 0.0:
					f += K_SPRING * 10.0 * over - C_BUMP * 3.0 * rel_v
				else:
					f += K_SPRING * 1.5 * over
			f = max(f, 0.0)
		wheel_comp[i] = comp
		wheel_load[i] = f
		fy += f
		torque += r.cross(Vector3(0, f, 0))
	# chassis / roof contacts (bottoming out, landing on the nose, rolling over)
	var scrape := 0.0
	for cp in CHASSIS_PTS:
		var r: Vector3 = bas * (cp as Vector3)
		var wp := pos + r
		var pen: float = track.ground_h(wp.x, wp.z) - wp.y
		if pen > 0.0:
			var pv: float = vy + omega.cross(r).y
			# metal on the ground: stiff going in, almost no push back out (it
			# crunches and stays down, it doesn't bounce)
			var f: float = max(160000.0 * pen - 18000.0 * pv, 0.0) if pv <= 0.0 else max(40000.0 * pen - 30000.0 * pv, 0.0)
			fy += f
			torque += r.cross(Vector3(0, f, 0))
			scrape += f
			# slamming the nose, floor or roof into the ground
			if pv < -3.5:
				_crash_feel(Vector3.ZERO, -pv * 0.8, "ground")
				_impact("ground", wp, Vector3.UP, Vector3.ZERO, -pv, 0.0)
	if scrape > 0.0:
		scrape_level = max(scrape_level, clampf(hs / 12.0, 0.0, 1.0) * clampf(scrape / (MASS * G * 0.3), 0.2, 1.0))
		# metal sliding on the ground: Coulomb friction (mu ~0.6) against the motion
		var dv: float = min(0.6 * scrape / MASS * dt, hs)
		if hs > 0.01:
			vel.x -= vel.x / hs * dv
			vel.z -= vel.z / hs * dv
		yaw_rate = move_toward(yaw_rate, 0.0, 0.6 * scrape / IZ * dt)
	if hub_scrape > 0.0 and hs > 0.05:
		# a bare hub grinding on the road drags that corner back: the car slows
		# and is pulled round towards the missing wheel
		scrape_level = max(scrape_level, clampf(hs / 10.0, 0.3, 1.0))
		var dv2: float = min(0.55 * hub_scrape / MASS * dt, hs)
		vel.x -= vel.x / hs * dv2
		vel.z -= vel.z / hs * dv2
		for i in 4:
			if hub_drag[i] > 0.0:
				var hr2: Vector3 = bas * (WHEEL_LOCAL[i] as Vector3)
				var fdrag: Vector3 = -dir * 0.55 * hub_drag[i]
				yaw_rate += hr2.cross(fdrag).y / IZ * dt
	grounded = n_contact > 0
	var contact := n_contact / 4.0
	# tyre forces act at the road, below the centre of mass: the body squats,
	# dives and leans (only as much as the wheels are actually on the ground)
	var tp: float = torque.dot(pitch_ax) + MASS * ax_f * H_CG * 0.9 * contact
	var tr: float = torque.dot(bas.z) + MASS * ay_f * H_CG * 0.35 * contact
	pitch_rate += tp / I_PITCH * dt
	roll_rate += tr / I_ROLL * dt
	if not grounded:
		pitch_rate *= 1.0 - 0.15 * dt
		roll_rate *= 1.0 - 0.15 * dt
	vy += fy / MASS * dt
	pitch += pitch_rate * dt
	roll += roll_rate * dt
	pitch = wrapf(pitch, -PI, PI)
	roll = wrapf(roll, -PI, PI)
	global_position.y += vy * dt
	# tyre load vs. what the tyre model assumes: a wheel in the air has no grip
	var lf: float = wheel_load[0] + wheel_load[1]
	var lr: float = wheel_load[2] + wheel_load[3]
	# full grip while the axle carries at least ~45% of its expected load (ordinary
	# bumps), fading to nothing as the wheels go light and leave the ground
	grip_f = lerpf(grip_f, clampf(lf / max(nf_model, 1.0) / 0.45, 0.0, 1.0), min(1.0, dt * 20.0))
	grip_r = lerpf(grip_r, clampf(lr / max(nr_model, 1.0) / 0.45, 0.0, 1.0), min(1.0, dt * 20.0))
	if grounded and not was_grounded:
		_land(-vy)
		# a drop from height: extra damping for a moment, and the body's spin
		# is mostly killed by the impact instead of rocking on
		if -vy > 3.0 or air_time > 0.5:
			land_damp = clampf((-vy - 2.0) / 5.0, 0.4, 1.0)
			pitch_rate *= 0.5
			roll_rate *= 0.5
		air_time = 0.0
	land_damp = move_toward(land_damp, 0.0, dt * 1.6)

func _step(dt: float) -> void:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var vlong := vel.dot(fwd)
	var vlat := vel.dot(right)
	speed = Vector2(vel.x, vel.z).length()
	var pos := global_position

	# ---- gear logic: brake at standstill engages reverse
	var thr := in_throttle
	var brk := in_brake
	if gear >= 1 and speed < 1.0 and in_brake > 0.3 and in_throttle < 0.1:
		rev_hold += dt
		if rev_hold > 0.35:
			gear = -1
	elif gear == -1 and in_throttle > 0.1 and vlong > -1.0:
		gear = 1
		rev_hold = 0.0
	else:
		rev_hold = 0.0
	if gear == -1:
		thr = in_brake
		brk = in_throttle

	# ---- steering
	var target: float
	var max_st: float = min(MAX_STEER * steer_k, 1.05) * (1.0 - 0.55 * steer_broken)
	if wheel_hold:
		# VR hands on the steering wheel: the front wheels follow it directly
		# (no speed limit, no countersteer assist - you're doing the steering)
		target = clampf(wheel_target, -max_st, max_st)
	elif in_analog:
		target = -in_steer * max_st
	else:
		var lim := lerpf(max_st, 0.32 * steer_k, clampf(speed / 55.0, 0.0, 1.0))
		target = -in_steer * lim
	if wheel_hold:
		pass
	elif vlong > 2.0:
		# countersteer assist: front wheels drift towards the direction of travel
		var vlat_f := vlat - yaw_rate * A
		var align := -atan2(vlat_f, vlong)
		var k := assist * clampf((speed - 2.0) / 6.0, 0.0, 1.0)
		target = clampf(target + align * k, -max_st, max_st)
	var srate := (9.0 if in_analog else 4.0) * lerpf(0.8, 1.3, clampf(steer_k - 0.6, 0.0, 1.0))
	if wheel_hold:
		srate = 8.0   # the steering rack takes a moment to follow, like a real car
	steer = move_toward(steer, target + steer_bias, srate * dt)

	# ---- surface
	var fpos := pos + fwd * A
	var rpos := pos - fwd * B
	var m_road: float = mu_road
	var m_off: float = mu_grass
	var mu_f: float = (m_road if track.road_dist(fpos.x, fpos.z) < track.HALF_W + 0.6 else m_off) * front_k
	var mu_r: float = m_road if track.road_dist(rpos.x, rpos.z) < track.HALF_W + 0.6 else m_off
	mu_f *= grip_dmg_f    # bent wheels / suspension grip less
	mu_r *= grip_dmg_r
	on_road = track.road_dist(pos.x, pos.z) < track.HALF_W + 0.6

	# ---- loads with longitudinal weight transfer
	var nf := MASS * G * B / WB - MASS * ax_f * H_CG / WB
	var nr := MASS * G * A / WB + MASS * ax_f * H_CG / WB
	nf = max(nf, 1500.0)
	nr = max(nr, 1500.0)
	nf_model = nf
	nr_model = nr
	# the suspension says how hard each axle is really pressed into the road
	nf *= grip_f
	nr *= grip_r

	# ---- slip angles
	var vx: float = max(abs(vlong), 1.0)
	var dir := 1.0 if vlong >= 0.0 else -1.0
	var af := atan2(vlat - yaw_rate * A, vx) + steer * dir
	var ar := atan2(vlat + yaw_rate * B, vx)

	# ---- drivetrain
	var ratio: float = GEARS[gear] * FINAL if gear > 0 else REV_RATIO * FINAL
	var wheel_speed: float = abs(vlong) + spin
	rpm = clampf(wheel_speed / WHEEL_R * ratio * 9.549, IDLE, REDLINE + 150.0)
	if thr > 0.05 and speed < 3.0:
		rpm = max(rpm, lerpf(IDLE, 3500.0, thr))   # clutch slip launch
	var drive := 0.0
	if thr > 0.0 and shift_timer <= 0.0:
		drive = torque_at(rpm) * ratio * 0.85 / WHEEL_R * thr * power_k
		if rpm >= REDLINE:
			drive *= 0.1
		if gear == -1:
			drive = -drive
	var lk: float = long_k
	var max_r: float = max(mu_r * nr * lk, 1.0)
	var fx_r := drive
	if abs(fx_r) > max_r and thr > 0.3:
		var straight := 0.3 if abs(ar) < 0.08 else 1.0   # launch traction vs power-oversteer
		spin = min(spin + (abs(fx_r) - max_r * 0.9) / MASS * dt * 5.0 * straight, 18.0)
	else:
		spin = max(spin - (14.0 + 30.0 * (1.0 - thr)) * dt, 0.0)
	if spin > 0.4:
		fx_r = signf(fx_r) * max_r * 0.9
	fx_r = clampf(fx_r, -max_r, max_r)

	# ---- brakes
	var fx_f := 0.0
	if brk > 0.0 and speed > 0.3:
		fx_f = -dir * min(BRAKE_FORCE * 0.65 * brk, mu_f * nf * lk)
		fx_r += -dir * min(BRAKE_FORCE * 0.35 * brk, max_r * 0.8)
	var hb_lat := 1.0
	if in_handbrake > 0.0:
		hb_lat = lerpf(1.0, hb_k, in_handbrake)
		if speed > 0.3:
			fx_r += -dir * min(max_r * 0.7, 6000.0) * in_handbrake
		spin = 0.0
	fx_r = clampf(fx_r, -max_r, max_r)

	# ---- lateral forces (friction circle on the rear)
	var lat_avail_r: float = sqrt(max(0.0, 1.0 - (fx_r / max_r) * (fx_r / max_r)))
	lat_avail_r = max(lat_avail_r, 0.45) * hb_lat
	var fyf := -mu_f * nf * pacejka(af, tyre_bf, tyre_cf)
	var fyr := -mu_r * nr * lat_avail_r * pacejka(ar, tyre_br, tyre_cr)

	var wfwd := fwd * cos(steer) - right * sin(steer)
	var wright := right * cos(steer) + fwd * sin(steer)
	var F_front := wright * fyf + wfwd * fx_f
	var F_rear := right * fyr + fwd * fx_r

	# ---- resistances & slope
	var F := F_front + F_rear
	var hv := Vector3(vel.x, 0, vel.z)
	F -= hv * speed * drag_k
	if speed > 0.05:
		var roll_c := roll_road if on_road else 0.07
		F -= hv.normalized() * MASS * G * roll_c * min(speed, 1.0)
	var hfront: float = track.ground_h(fpos.x, fpos.z)
	var hrear: float = track.ground_h(rpos.x, rpos.z)
	F -= fwd * MASS * G * (hfront - hrear) / WB
	# a badly bent wheel shakes the car from side to side as it turns
	var wob: float = max(max(wheel_dmg[0], wheel_dmg[1]), max(wheel_dmg[2], wheel_dmg[3])) - 0.3
	if wob > 0.0 and speed > 2.0:
		F += right * sin(odometer / WHEEL_R) * wob * 1400.0 * min(speed / 15.0, 1.0)

	vel += F / MASS * dt
	vel.y = 0.0
	var torque := (fwd * A).cross(F_front).y + (-fwd * B).cross(F_rear).y
	# a bent rear wheel drags on its side
	torque += yaw_bias * min(speed / 10.0, 1.0) * (1.0 if vlong >= 0.0 else -1.0)
	# drift stability assist: past ~35 deg of slip, gently rotate the nose back
	# towards the direction of travel so big angles are holdable instead of spinning
	if speed > 4.0:
		var beta := atan2(vlat, vlong)   # full range: > 90 deg means sliding backwards
		var excess: float = abs(beta) - stab_start
		if excess > 0.0:
			# the assist can't twist the car harder than the tyres could
			var stab := (0.6 + assist) * stab_k * clampf(m_road / mu_road, 0.0, 1.0)
			var t_as := -signf(beta) * excess * 10000.0 * stab
			# damp the yaw rate component that is increasing the slip
			if signf(yaw_rate) == -signf(beta):
				t_as -= yaw_rate * 6000.0 * min(excess, 1.0) * stab
			torque += clampf(t_as, -30000.0, 30000.0) * clampf((speed - 4.0) / 4.0, 0.0, 1.0)
	yaw_rate += torque / IZ * dt
	# low-speed stability: blend to kinematic yaw rate, kill creeping
	if speed < 3.0:
		var kin := vlong * tan(steer) / WB
		yaw_rate = lerpf(yaw_rate, kin, clampf((3.0 - speed) / 3.0, 0.0, 1.0) * min(1.0, dt * 20.0))
		if thr < 0.05 and speed < 0.4:
			vel = vel.lerp(Vector3.ZERO, min(1.0, dt * 3.0))
	yaw += yaw_rate * dt

	var a_long := F.dot(fwd) / MASS
	var a_lat := F.dot(right) / MASS
	ax_f = lerpf(ax_f, a_long, min(1.0, dt * 6.0))
	ay_f = lerpf(ay_f, a_lat, min(1.0, dt * 6.0))

	global_position.x += vel.x * dt
	global_position.z += vel.z * dt
	_collide_trees(dt)

	# ---- auto gearbox
	shift_timer -= dt
	if auto_gear and gear >= 1 and shift_timer <= 0.0:
		var road_rpm: float = speed / WHEEL_R * GEARS[gear] * FINAL * 9.549
		if rpm > 7000.0 and gear < 6 and road_rpm > 5200.0:
			gear += 1
			shift_timer = 0.18
		elif gear > 1:
			# use ground speed, not forward speed, so sliding sideways never drops to 1st
			var down_rpm: float = speed / WHEEL_R * GEARS[gear - 1] * FINAL * 9.549
			if down_rpm < 4600.0 and road_rpm < 3000.0:
				gear -= 1
				shift_timer = 0.12

	wf = vlong / WHEEL_R
	wr = 0.0 if in_handbrake > 0.5 else (vlong + spin * dir) / WHEEL_R
	body_slip = atan2(vlat, max(abs(vlong), 0.5)) if speed > 1.0 else 0.0
	rear_slide = clampf((abs(ar) - 0.14) / 0.3 + spin / 7.0, 0.0, 1.0) if speed > 2.5 else clampf(spin / 7.0, 0.0, 1.0)
	if in_handbrake > 0.5 and speed > 4.0:
		rear_slide = max(rear_slide, 0.6)

func shift(up: bool) -> void:
	auto_gear = false
	if up and gear < 6:
		gear = max(gear + 1, 1)
	elif not up and gear > 1:
		gear -= 1
	shift_timer = 0.12

func _collide_trees(dt: float) -> void:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var pos := global_position
	var trees: Array = forest.trees_near(pos.x, pos.z)
	for c in [1.45, 0.45, -0.55, -1.5]:
		var cc: float = c
		var cp := pos + fwd * cc
		for t in trees:
			var tv: Vector3 = t
			var d := Vector2(cp.x - tv.x, cp.z - tv.y)
			var rr := tv.z + 0.88
			var dist := d.length()
			if dist < rr and dist > 0.001:
				var n := Vector3(d.x / dist, 0, d.y / dist)
				var push := rr - dist
				global_position += n * push
				pos = global_position
				var vn := -vel.dot(n)
				if vn > 0.0:
					# a crash is mostly plastic: hard hits soak up the energy (the
					# car crumples) instead of bouncing off; light taps still rebound
					var e := lerpf(0.25, 0.03, clampf(vn / 12.0, 0.0, 1.0))
					var j := n * vn * (1.0 + e)
					vel += j
					var vt := vel - n * vel.dot(n)
					vel -= vt * min(0.15 + vn * 0.035, 0.75)     # scraping round the trunk
					var rc := fwd * cc
					yaw_rate += rc.cross(j * MASS).y / IZ * 0.6
					yaw_rate *= 0.75
					_crash_feel(j, vn, "tree")
					if vn > 4.0:
						_cancel_drift(true)
					# body damage: the panel wraps around the trunk (vertical round dent)
					if vn > 2.0:
						_impact("tree", Vector3(tv.x, pos.y + 0.6, tv.y) + n * tv.z, n, Vector3.UP, vn, tv.z)
	# guardrails (maps that have them): each body corner is held inside the rail
	if track.has_method("rail_push"):
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		for c in [Vector2(0.9, 2.05), Vector2(-0.9, 2.05), Vector2(0.9, -2.1), Vector2(-0.9, -2.1)]:
			var cv: Vector2 = c
			var rc := right * cv.x + fwd * cv.y
			var push: Vector3 = track.rail_push(global_position + rc, track_idx)
			if push != Vector3.ZERO:
				global_position += push
				var n := push.normalized()           # points back towards the road
				var vn := -vel.dot(n)
				if vn > 0.0:
					# glancing blow: kill most of the push into the rail, scrape some speed
					var j := n * vn * lerpf(1.2, 1.05, clampf(vn / 10.0, 0.0, 1.0))
					vel += j
					var vt := vel - n * vel.dot(n)
					vel -= vt * min(0.12 + vn * 0.03, 0.5)
					yaw_rate += rc.cross(j * MASS).y / IZ * 0.5
					_crash_feel(j, vn, "rail")
					scrape_level = max(scrape_level, clampf(vt.length() / 15.0, 0.0, 1.0))
					hits += 1
					if vn > 5.0:
						_cancel_drift(true)
					# body damage: a long horizontal crease at the height of the rail beam
					if vn > 1.5:
						_impact("rail", global_position + rc + Vector3(0, 0.58, 0), n, n.cross(Vector3.UP).normalized(), vn, 0.12)
	# keep inside the world
	var lim_min: Vector2 = track.T_MIN + Vector2(30, 30)
	var lim_max: Vector2 = track.T_MAX - Vector2(30, 30)
	global_position.x = clampf(global_position.x, lim_min.x, lim_max.x)
	global_position.z = clampf(global_position.z, lim_min.y, lim_max.y)

func _post_step(delta: float) -> void:
	var p := global_position
	_update_mech(delta)
	shake = move_toward(shake, 0.0, delta * 2.5)
	crash_cool -= delta
	if crash_audio:
		crash_audio.set_loops(scrape_level, steam.emitting if steam else false, engine_temp)
	scrape_level = move_toward(scrape_level, 0.0, delta * 4.0)
	# the node is the sprung body: its orientation is the simulated one
	basis = _body_basis()
	if not grounded:
		air_time += delta
	# upside down / on its side: it just stays there (R or Backspace puts it
	# back on the road); the HUD shows a hint after a moment
	if basis.y.y < 0.35 and speed < 3.0:
		flipped_time += delta
	else:
		flipped_time = 0.0

	# wheels move up and down in their arches with the suspension
	var offs := []
	for i in 4:
		offs.append(clampf(wheel_comp[i] - c0[i], -c0[i], BUMP_TRAVEL + 0.02))
	model.update_visuals(steer, wf, wr, 0.0, 0.0, delta, offs)
	model.set_brake(in_brake > 0.1 and gear != -1 or (gear == -1 and in_throttle > 0.1))

	# ---- track progress / laps
	var cnt: int = track.pts.size()
	var prev := track_idx
	track_idx = track.nearest_index(p, track_idx)
	odometer += speed * delta
	if track.endless:
		# no laps on the endless road - each kilometre pays out like a lap
		stage_time += delta
		if odometer - stage_odo >= ENDLESS_STAGE:
			_pay_lap(stage_time, odometer - stage_odo)
			stage_odo = odometer
			stage_time = 0.0
	elif track_idx > cnt * 0.45 and track_idx < cnt * 0.55:
		passed_half = true
	lap_time += delta
	if not track.endless and prev > cnt * 0.9 and track_idx < cnt * 0.1 and passed_half:
		laps += 1
		last_lap = lap_time
		if best_lap == 0.0 or lap_time < best_lap:
			best_lap = lap_time
		lap_completed.emit(last_lap, best_lap)
		_pay_lap(last_lap, track.total_len)
		lap_time = 0.0
		passed_half = false

	_update_drift(delta)
	_update_effects(delta)

# ---------------------------------------------------------------- scoring
func _update_drift(delta: float) -> void:
	var ang: float = abs(body_slip)
	var drifting := speed > 8.0 and ang > 0.18 and ang < 1.75 and on_road
	if drifting:
		drift_time += delta
		drift_idle = 0.0
		drift_mult = clampi(1 + int(drift_time / 2.5), 1, 5)
		drift_points += speed * rad_to_deg(ang) * 0.12 * delta * drift_mult
	elif drift_points > 0.0:
		drift_idle += delta
		if not on_road:
			_cancel_drift(true)
		elif drift_idle > 1.4:
			var pts := int(drift_points)
			total_score += pts
			best_combo = max(best_combo, pts)
			drift_banked.emit(pts)
			_cancel_drift(false)

func _cancel_drift(failed: bool) -> void:
	if failed and drift_points > 0.0:
		drift_failed.emit()
	drift_points = 0.0
	drift_time = 0.0
	drift_idle = 0.0
	drift_mult = 1

# ---------------------------------------------------------------- effects
func _soft_circle() -> ImageTexture:
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x - S / 2.0 + 0.5, y - S / 2.0 + 0.5).length() / (S / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

func _build_effects(fx_parent: Node3D) -> void:
	# billowing tyre smoke from each rear contact patch (smoke_fx.gd)
	for side in [-1.0, 1.0]:
		var p: GPUParticles3D = SmokeFx.tyre_smoke()
		p.position = Vector3(0.78 * side, 0.12, B)
		add_child(p)
		smoke.append(p)
	# skid marks: ring buffer of flat quads
	skid_mm = MultiMesh.new()
	skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(1, 1)
	var skm := StandardMaterial3D.new()
	skm.albedo_color = Color(0.02, 0.02, 0.02, 0.55)
	skm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skm.roughness = 1.0
	pm2.material = skm
	skid_mm.mesh = pm2
	skid_mm.instance_count = SKID_MAX
	skid_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = skid_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_parent.add_child(mmi)

func _update_effects(_delta: float) -> void:
	# drifting or spinning the rear wheels (burnouts) makes smoke
	var burn: float = max(rear_slide, clampf(spin / 9.0, 0.0, 1.0))
	if force_smoke:
		burn = 1.0
	var smoking := burn > 0.28 and on_road and (speed > 2.0 or spin > 3.0 or force_smoke)
	for p in smoke:
		p.emitting = smoking
		p.amount_ratio = clampf(burn * 1.15, 0.25, 1.0)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		var wp := global_position - fwd * B + right * 0.78 * side
		wp.y = track.ground_h(wp.x, wp.z) + 0.02
		if rear_slide > 0.35 and on_road:
			var last: Vector3 = skid_last[k]
			if last != Vector3.INF:
				var seg := wp - last
				var l := seg.length()
				if l > 0.25 and l < 3.0:
					var xdir := seg / l
					var zdir := xdir.cross(Vector3.UP).normalized()
					var bas := Basis(zdir * 0.24, Vector3.UP, xdir * l)
					# PlaneMesh lies in XZ: x = width, z = length
					bas = Basis(xdir.cross(Vector3.UP).normalized() * 0.24, Vector3.UP, xdir * (l + 0.02))
					skid_mm.set_instance_transform(skid_next, Transform3D(bas, (wp + last) * 0.5))
					skid_next = (skid_next + 1) % SKID_MAX
					skid_mm.visible_instance_count = min(skid_mm.visible_instance_count + 1, SKID_MAX)
					skid_last[k] = wp
				elif l >= 3.0:
					skid_last[k] = wp
			else:
				skid_last[k] = wp
		else:
			skid_last[k] = Vector3.INF

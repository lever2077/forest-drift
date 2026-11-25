# Procedural Nissan 350Z (Z33) model.
# Local axes: +X right, +Y up, -Z forward. Internally the body is described with
# f = forward coordinate (f = -z), length 4.32 m, width 1.82 m, height 1.31 m,
# wheelbase 2.65 m.
extends Node3D

const MB = preload("res://scripts/mb.gd")

const HALF_L := 2.16
const FA := 1.30          # front axle (f)
const RA := -1.35         # rear axle (f)
const WHEEL_R := 0.33
const AXLE_Y := 0.33
const TRACK_F := 0.765
const TRACK_R := 0.775
const ARCH_R := 0.375
const BELT_TH := 0.56     # section angle (rad) where the glasshouse meets the body

var paint_color := Color(0.012, 0.012, 0.015)   # gloss black (Nismo build)

var body: Node3D          # everything that rolls/pitches with suspension
var wheels: Array = []    # each: {"pivot": Node3D, "spin": Node3D, "left": bool, "front": bool}
var steering_wheel: Node3D
var tail_mat: StandardMaterial3D
var head_mat: StandardMaterial3D
var head_lights: Array[SpotLight3D] = []
var dash_label: Label3D
var mats := {}

const T_KEYS := [[-2.17, 0.90], [-2.08, 0.955], [-1.9, 0.978], [-1.75, 0.982], [-1.4, 0.985], [-1.0, 0.99], [-0.3, 0.99],
	[0.3, 0.96], [0.62, 0.86], [1.0, 0.815], [1.5, 0.765], [1.85, 0.70], [2.05, 0.62], [2.17, 0.55]]
const ROOF_KEYS := [[-1.64, 0.975], [-1.5, 1.015], [-1.3, 1.10], [-1.0, 1.215], [-0.75, 1.29], [-0.5, 1.31],
	[-0.3, 1.305], [-0.15, 1.27], [0.1, 1.15], [0.4, 0.99], [0.66, 0.875]]

# ---------------------------------------------------------------- shape functions
static func sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func gauss(x: float, s: float) -> float:
	return exp(-(x / s) * (x / s))

static func spow(v: float, e: float) -> float:
	return signf(v) * pow(abs(v), e)

static func interp(keys: Array, x: float) -> float:
	var n := keys.size()
	if x <= keys[0][0]:
		return keys[0][1]
	if x >= keys[n - 1][0]:
		return keys[n - 1][1]
	for i in n - 1:
		var x0: float = keys[i][0]
		var x1: float = keys[i + 1][0]
		if x >= x0 and x <= x1:
			var y0: float = keys[i][1]
			var y1: float = keys[i + 1][1]
			var ym: float = keys[max(i - 1, 0)][1]
			var yp: float = keys[min(i + 2, n - 1)][1]
			var xm: float = keys[max(i - 1, 0)][0]
			var xp: float = keys[min(i + 2, n - 1)][0]
			var t := (x - x0) / (x1 - x0)
			# cubic Hermite with finite-difference tangents
			var m0: float = (y1 - ym) / max(x1 - xm, 1e-4) * (x1 - x0)
			var m1: float = (yp - y0) / max(xp - x0, 1e-4) * (x1 - x0)
			var t2 := t * t
			var t3 := t2 * t
			return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1
	return keys[n - 1][1]

func half_width(f: float) -> float:
	var w := 0.85 + 0.05 * gauss(f - FA, 0.42) + 0.06 * gauss(f - RA, 0.5) - 0.012 * gauss(f + 0.1, 0.5)
	# rounded nose and squarer tail in plan view
	var af := clampf((f - 0.9) / (HALF_L - 0.9), 0.0, 1.0)
	var ar := clampf((-f - 1.72) / (HALF_L - 1.72), 0.0, 1.0)
	var shape: float = pow(max(1.0 - pow(af, 2.3), 0.0), 1.0 / 2.3) * pow(max(1.0 - pow(ar, 4.5), 0.0), 1.0 / 4.5)
	return w * shape

func bottom_y(f: float) -> float:
	return 0.165 + 0.08 * sstep(1.65, HALF_L, f) + 0.09 * sstep(1.85, HALF_L, -f)

func top_y(f: float) -> float:
	return interp(T_KEYS, f)

func roof_y(f: float) -> float:
	return interp(ROOF_KEYS, f)

# raw body surface point in (x, y, f) space; th = section angle, 0 = right side
func body_raw(f: float, th: float) -> Vector3:
	var w := half_width(f)
	var b := bottom_y(f)
	var t := top_y(f)
	var yc := b + (t - b) * 0.42
	var c := cos(th)
	var s := sin(th)
	var x: float
	var y: float
	if s >= 0.0:
		var e := 2.0 / 3.0
		x = w * spow(c, e)
		y = yc + (t - yc) * pow(s, e)
	else:
		var e2 := 2.0 / 7.0
		x = w * spow(c, e2)
		y = yc - (yc - b) * pow(-s, e2)
	# tumblehome above the shoulder, tuck under the sills
	var k: float = clampf((y - 0.52) / max(t - 0.52, 0.05), 0.0, 1.0)
	x *= 1.0 - 0.10 * k * k
	x *= 1.0 - 0.07 * clampf((0.32 - y) / 0.15, 0.0, 1.0)
	# hood sits a touch lower than the front fenders
	if s > 0.0 and f > 0.5:
		var xn: float = clampf(abs(x) / max(w, 0.01), 0.0, 1.0)
		y -= 0.022 * sstep(0.5, 0.9, f) * sstep(2.12, 1.7, f) * pow(1.0 - xn * xn, 2.0)
	return Vector3(x, y, f)

# applies the wheel-arch cutouts; returns Vector4(x, y, f, arch_flag)
func body_pt(f: float, th: float) -> Vector4:
	var p := body_raw(f, th)
	var flag := 0.0
	# hollow out the cockpit: inside the beltline the top drops to the floor
	var cab_k := sstep(0.66, 0.58, f) * sstep(-1.64, -1.55, f)
	if cab_k > 0.0 and th > BELT_TH + 0.01 and th < PI - BELT_TH - 0.01:
		var floor_y := lerpf(0.66, 0.24, sstep(-1.05, -0.9, f) * sstep(0.62, 0.52, f))
		p.y = lerpf(p.y, floor_y, cab_k)
		var belt := body_raw(f, BELT_TH)
		p.x = signf(p.x) * min(abs(p.x), belt.x - 0.035)
	if abs(p.x) > 0.42:
		for ax in [FA, RA]:
			var axf: float = ax
			var d := Vector2(p.z - axf, p.y - AXLE_Y).length()
			if d < ARCH_R:
				# soft edge over ~1.5 cm keeps the arch outline smooth
				var k2 := sstep(ARCH_R, ARCH_R - 0.015, d)
				p.x = signf(p.x) * lerpf(abs(p.x), min(abs(p.x), 0.6), k2)
				flag = k2
			elif d < ARCH_R + 0.05:
				p.x += signf(p.x) * 0.014 * (1.0 - (d - ARCH_R) / 0.05)
	return Vector4(p.x, p.y, p.z, flag)

# forward position of the front bumper face at lateral offset x (bumper height)
func nose_f(x: float) -> float:
	var f := HALF_L
	while f > 1.0:
		if half_width(f) * 0.93 >= abs(x):
			return f
		f -= 0.004
	return f

static func L(p: Vector3) -> Vector3:
	# (x, y, f) -> local
	return Vector3(p.x, p.y, -p.z)

# ---------------------------------------------------------------- materials
func _make_materials() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = paint_color
	paint.vertex_color_use_as_albedo = true
	paint.metallic = 0.45
	paint.roughness = 0.32
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.06
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["paint"] = paint

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.02, 0.025, 0.03, 0.62)   # dark tint
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.4
	glass.roughness = 0.04
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["glass"] = glass

	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.025, 0.025, 0.028)
	trim.roughness = 0.45
	trim.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["trim"] = trim

	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.85, 0.86, 0.88)
	chrome.metallic = 1.0
	chrome.roughness = 0.12
	mats["chrome"] = chrome

	head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.5, 0.52, 0.55)
	head_mat.metallic = 0.85
	head_mat.roughness = 0.08
	head_mat.clearcoat_enabled = true
	head_mat.clearcoat = 1.0
	mats["headlight"] = head_mat

	var proj := StandardMaterial3D.new()
	proj.albedo_color = Color(0.9, 0.95, 1.0)
	proj.emission_enabled = true
	proj.emission = Color(0.85, 0.92, 1.0)
	proj.emission_energy_multiplier = 0.4
	proj.metallic = 0.5
	proj.roughness = 0.05
	mats["projector"] = proj

	tail_mat = StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.55, 0.02, 0.02)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.03)
	tail_mat.emission_energy_multiplier = 0.35
	tail_mat.roughness = 0.1
	tail_mat.clearcoat_enabled = true
	mats["taillight"] = tail_mat

	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(0.35, 0.2, 0.05)
	amber.emission_enabled = true
	amber.emission = Color(1.0, 0.5, 0.05)
	amber.emission_energy_multiplier = 0.05
	amber.roughness = 0.1
	mats["amber"] = amber

	var seam := StandardMaterial3D.new()
	seam.albedo_color = Color(0.01, 0.01, 0.01)
	seam.roughness = 0.8
	mats["seam"] = seam

	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.045, 0.045, 0.048)
	rubber.roughness = 0.88
	rubber.albedo_texture = _tread_texture()
	mats["rubber"] = rubber

	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.34, 0.35, 0.37)   # gunmetal
	rim.metallic = 0.85
	rim.roughness = 0.32
	mats["rim"] = rim

	var rim_dark := StandardMaterial3D.new()
	rim_dark.albedo_color = Color(0.18, 0.18, 0.19)
	rim_dark.metallic = 0.8
	rim_dark.roughness = 0.4
	mats["rim_dark"] = rim_dark

	var disc := StandardMaterial3D.new()
	disc.albedo_color = Color(0.36, 0.35, 0.34)
	disc.metallic = 0.9
	disc.roughness = 0.45
	mats["disc"] = disc

	var caliper := StandardMaterial3D.new()
	caliper.albedo_color = Color(0.9, 0.5, 0.1)   # gold/orange calipers
	caliper.roughness = 0.35
	caliper.clearcoat_enabled = true
	mats["caliper"] = caliper

	var interior := StandardMaterial3D.new()
	interior.albedo_color = Color(0.07, 0.07, 0.075)
	interior.roughness = 0.75
	mats["interior"] = interior

	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.11, 0.105, 0.10)
	leather.roughness = 0.6
	mats["leather"] = leather

	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.55, 0.12, 0.05)
	accent.roughness = 0.6
	mats["accent"] = accent

	var alu := StandardMaterial3D.new()
	alu.albedo_color = Color(0.7, 0.7, 0.72)
	alu.metallic = 0.9
	alu.roughness = 0.35
	mats["alu"] = alu

	var gauge := StandardMaterial3D.new()
	gauge.albedo_color = Color(0.05, 0.05, 0.05)
	gauge.emission_enabled = true
	gauge.emission = Color(1.0, 0.45, 0.1)
	gauge.emission_energy_multiplier = 0.6
	mats["gauge"] = gauge

	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.93, 0.93, 0.9)
	plate.roughness = 0.5
	mats["plate"] = plate

	# mechanical parts under the panels (seen once the bonnet / bumpers come off)
	var engine := StandardMaterial3D.new()
	engine.albedo_color = Color(0.16, 0.16, 0.17)
	engine.metallic = 0.6
	engine.roughness = 0.55
	mats["engine"] = engine
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.09, 0.09, 0.095)
	frame.metallic = 0.4
	frame.roughness = 0.7
	mats["frame"] = frame
	var radiator := StandardMaterial3D.new()
	radiator.albedo_color = Color(0.05, 0.05, 0.055)
	radiator.metallic = 0.3
	radiator.roughness = 0.6
	radiator.albedo_texture = _fin_texture()
	radiator.uv1_scale = Vector3(6, 3, 1)
	mats["radiator"] = radiator
	var hose := StandardMaterial3D.new()
	hose.albedo_color = Color(0.03, 0.03, 0.03)
	hose.roughness = 0.85
	mats["hose"] = hose
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.6, 0.06, 0.04)
	red.roughness = 0.5
	mats["red"] = red

	# gunmetal aero parts: front lip, side skirts
	var lip := StandardMaterial3D.new()
	lip.albedo_color = Color(0.1, 0.1, 0.11)
	lip.metallic = 0.5
	lip.roughness = 0.4
	lip.clearcoat_enabled = true
	lip.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["lip"] = lip

# radiator core: thin horizontal fins
func _fin_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var v := 0.55 if y % 4 == 0 else (1.0 if x % 8 != 0 else 0.7)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# Engine bay, radiator, chassis rails, suspension arms, driveshaft, exhaust and
# fuel tank: hidden under the panels until they bend or come off. Local space
# (+X right, +Y up, -Z forward). Kept inside the zones the damage system cuts
# the bumpers / bonnet from, so they stay with the car.
func _build_mechanicals(mb) -> void:
	var I := Basis()
	# --- chassis: frame rails, radiator support, firewall, inner wings
	for side in [-1.0, 1.0]:
		mb.box("frame", Transform3D(I, Vector3(0.55 * side, 0.24, 0.1)), Vector3(0.09, 0.12, 3.55))
		# inner wing and strut tower: kept well inside the front wings (the wing
		# surface curves down to ~0.69 m at this width, so these stay below it)
		mb.box("frame", Transform3D(I, Vector3(0.57 * side, 0.5, -1.2)), Vector3(0.03, 0.22, 0.7))
		mb.cylinder("frame", Transform3D(I, Vector3(0.53 * side, 0.55, -1.3)), 0.08, 0.065, 0.18, 12)
		mb.cylinder("alu", Transform3D(I, Vector3(0.53 * side, 0.645, -1.3)), 0.045, 0.045, 0.02, 10)
	mb.box("frame", Transform3D(I, Vector3(0, 0.42, -1.69)), Vector3(1.25, 0.1, 0.07))              # radiator support beam
	mb.box("frame", Transform3D(I, Vector3(0, 0.56, -0.78)), Vector3(1.36, 0.5, 0.03))              # firewall
	mb.box("frame", Transform3D(I, Vector3(0, 0.2, -1.2)), Vector3(1.0, 0.04, 0.9))                  # front undertray
	# --- radiator with twin fans and hoses
	mb.box("radiator", Transform3D(I, Vector3(0, 0.5, -1.63)), Vector3(1.05, 0.38, 0.05))
	for fx in [-0.25, 0.25]:
		mb.cylinder("hose", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(fx, 0.5, -1.585)), 0.16, 0.16, 0.04, 16)
		mb.cylinder("engine", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(fx, 0.5, -1.56)), 0.04, 0.04, 0.03, 10)
	mb.beam("hose", Vector3(0.4, 0.62, -1.6), Vector3(0.2, 0.66, -1.3), Vector3.UP, 0.035, 0.035, 0.035, 0.035)
	mb.beam("hose", Vector3(-0.4, 0.36, -1.6), Vector3(-0.15, 0.35, -1.35), Vector3.UP, 0.035, 0.035, 0.035, 0.035)
	# --- VQ35-style V6: block, two angled heads with valve covers, intake plenum
	mb.box("engine", Transform3D(I, Vector3(0, 0.42, -1.12)), Vector3(0.42, 0.3, 0.6))
	for side in [-1.0, 1.0]:
		var hb := Basis(Vector3.BACK, 0.55 * side)
		mb.box("engine", Transform3D(hb, Vector3(0.2 * side, 0.6, -1.12)), Vector3(0.18, 0.16, 0.58))
		mb.box("red", Transform3D(hb, Vector3(0.24 * side, 0.67, -1.12)), Vector3(0.12, 0.04, 0.54))  # valve cover
	mb.box("alu", Transform3D(I, Vector3(0, 0.71, -1.08)), Vector3(0.3, 0.07, 0.48))                # plenum
	mb.cylinder("alu", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.7, -1.4)), 0.06, 0.06, 0.16, 14)  # throttle body
	mb.box("hose", Transform3D(I, Vector3(-0.42, 0.62, -1.48)), Vector3(0.22, 0.14, 0.26))          # air box
	mb.box("hose", Transform3D(I, Vector3(0.44, 0.58, -1.5)), Vector3(0.2, 0.17, 0.24))             # battery
	mb.box("red", Transform3D(I, Vector3(0.4, 0.675, -1.46)), Vector3(0.03, 0.02, 0.03))
	mb.box("alu", Transform3D(I, Vector3(0.48, 0.675, -1.54)), Vector3(0.03, 0.02, 0.03))
	# --- suspension: lower arms and hubs at each corner
	for e in [[-1.3, 1.0], [1.35, 1.0]]:
		var az: float = e[0]
		for side in [-1.0, 1.0]:
			mb.beam("frame", Vector3(0.5 * side, 0.24, az - 0.18), Vector3(0.66 * side, 0.27, az), Vector3.UP, 0.04, 0.035, 0.03, 0.03)
			mb.beam("frame", Vector3(0.5 * side, 0.24, az + 0.18), Vector3(0.66 * side, 0.27, az), Vector3.UP, 0.04, 0.035, 0.03, 0.03)
	# --- driveline, exhaust, fuel tank, rear diff
	mb.cylinder("engine", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.25, 0.25)), 0.04, 0.04, 1.9, 10)
	mb.box("engine", Transform3D(I, Vector3(0, 0.3, 1.35)), Vector3(0.3, 0.2, 0.25))                # differential
	mb.box("frame", Transform3D(I, Vector3(0, 0.28, 0.95)), Vector3(0.8, 0.18, 0.45))               # fuel tank
	for side in [-1.0, 1.0]:
		mb.beam("hose", Vector3(0.22 * side, 0.21, -0.8), Vector3(0.3 * side, 0.21, 1.7), Vector3.UP, 0.045, 0.045, 0.045, 0.045)
		mb.beam("hose", Vector3(0.3 * side, 0.21, 1.7), Vector3(0.52 * side, 0.27, 2.0), Vector3.UP, 0.045, 0.045, 0.045, 0.045)
		mb.cylinder("hose", Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.35 * side, 0.24, 1.6)), 0.11, 0.11, 0.3, 14)  # muffler

func _tread_texture() -> ImageTexture:
	var img := Image.create(64, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 64:
			var v := 1.0
			# 4 circumferential grooves
			for gx in [12, 26, 38, 52]:
				if abs(x - gx) < 2:
					v = 0.35
			# angled sipes on the shoulders
			if (x < 10 or x > 54) and int(y + x * 0.6) % 16 < 3:
				v = 0.4
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- build
func build() -> void:
	_make_materials()
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var mb := MB.new()
	_build_lower_body(mb)
	_build_cabin(mb)
	_build_lights_and_seams(mb)
	_build_details(mb)
	_build_interior(mb)
	_build_mechanicals(mb)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(mats)
	mi.name = "Shell"
	body.add_child(mi)
	_build_steering_wheel()
	_build_mirrors()
	_build_labels()
	_build_wheels()
	_build_lamps()

# ---------------------------------------------------------------- mirrors
# Real mirrors: each glass shows what a small camera at the mirror sees looking
# back (flipped left-right like a mirror). They only render while you're in the
# driver's seat (cockpit view or VR) because each one draws the world again.
const MIRROR_EYE := Vector3(-0.37, 1.07, 0.36)   # driver's eyes (body local)
var mirrors: Array = []    # {"vp": SubViewport, "cam": Camera3D, "xf": Transform3D (body local)}
var mirrors_on := false

func _build_mirrors() -> void:
	# side mirrors: glass on the back of each housing (same spot as _build_details)
	for side in [1.0, -1.0]:
		var p := body_raw(0.50, BELT_TH)
		var housing := L(Vector3(p.x * side, p.y, p.z)) + Vector3(0.10 * side, 0.08, 0.02)
		var glass := housing + Vector3(-0.022 * side, 0, 0.072)   # over the chrome back of the housing
		# looking back along the car's flank, a little outwards
		var view := Vector3(0.14 * side, -0.03, 1.0).normalized()
		_add_mirror(glass, view, Vector2(0.14, 0.07), Vector2i(360, 180), 17.0)
	# rear-view mirror hanging from the top of the windscreen
	var rv := L(Vector3(0.0, 1.165, -0.08))
	var stem := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.008
	sm.bottom_radius = 0.008
	sm.height = 0.07
	stem.mesh = sm
	stem.material_override = mats["interior"]
	stem.position = rv + Vector3(0, 0.05, -0.015)
	body.add_child(stem)
	_add_mirror(rv, Vector3(0.0, -0.04, 1.0).normalized(), Vector2(0.25, 0.065), Vector2i(560, 146), 11.0, true)

func _add_mirror(pos: Vector3, view: Vector3, glass_size: Vector2, res: Vector2i, fov_deg: float, framed := false) -> void:
	# the glass faces halfway between the driver's eyes and the view behind
	var to_eye := (MIRROR_EYE - pos).normalized()
	var n := (to_eye + view).normalized()
	var gz := n
	var gx := Vector3.UP.cross(gz).normalized()
	var gy := gz.cross(gx)
	var gb := Basis(gx, gy, gz)
	var vp := SubViewport.new()
	vp.size = res
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	body.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = fov_deg
	cam.near = 0.08
	cam.far = 400.0
	vp.add_child(cam)
	cam.current = true
	var cz := -view            # a camera looks along its -Z
	var cx := Vector3.UP.cross(cz).normalized()
	var cy := cz.cross(cx)
	var xf := Transform3D(Basis(cx, cy, cz), pos + n * 0.01)
	var glass := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = glass_size
	glass.mesh = qm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = vp.get_texture()
	gm.uv1_scale = Vector3(-1, 1, 1)    # mirrored left-right
	gm.uv1_offset = Vector3(1, 0, 0)
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	glass.transform = Transform3D(gb, pos + n * 0.002)
	body.add_child(glass)
	if framed:
		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(glass_size.x + 0.02, glass_size.y + 0.02, 0.025)
		frame.mesh = fm
		frame.material_override = mats["interior"]
		frame.transform = Transform3D(gb, pos - n * 0.013)
		body.add_child(frame)
	mirrors.append({"vp": vp, "cam": cam, "xf": xf})
	_place_mirror_cam(mirrors[-1])

func _place_mirror_cam(m: Dictionary) -> void:
	if body.is_inside_tree():
		(m["cam"] as Camera3D).global_transform = body.global_transform * (m["xf"] as Transform3D)

# render the mirrors every frame (driver's seat) or freeze them (outside views)
func set_mirrors_active(on: bool) -> void:
	mirrors_on = on
	for m in mirrors:
		_place_mirror_cam(m)
		(m["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_ONCE

func _grid_normals(grid: Array, nu: int, nv: int, closed_v: bool) -> Array:
	var norms := []
	for i in nu:
		var row := []
		for j in nv:
			var pu: Vector3 = grid[min(i + 1, nu - 1)][j] - grid[max(i - 1, 0)][j]
			var jn: int = (j + 1) % nv if closed_v else min(j + 1, nv - 1)
			var jp: int = (j - 1 + nv) % nv if closed_v else max(j - 1, 0)
			var pv: Vector3 = grid[i][jn] - grid[i][jp]
			var n := pu.cross(pv)
			if n.length() < 1e-9:
				n = Vector3(0, 0, -1) if i > nu / 2 else Vector3(0, 0, 1)
			row.append(n.normalized())
		norms.append(row)
	return norms

func _build_lower_body(mb) -> void:
	var NU := 300
	var NV := 180
	var grid := []
	var cols := []
	for i in NU:
		var u := float(i) / (NU - 1)
		var f_lin := lerpf(-HALF_L, HALF_L, u)
		var f_cos := -HALF_L * cos(PI * u)
		var f := lerpf(f_lin, f_cos, 0.45)
		var row := []
		var crow := []
		for j in NV:
			var th := -PI / 2.0 + TAU * j / NV
			var p := body_pt(f, th)
			var loc := L(Vector3(p.x, p.y, p.z))
			row.append(loc)
			var c := Color.WHITE
			if p.w > 0.0:
				c = Color.WHITE.lerp(Color(0.02, 0.02, 0.02), p.w)
			elif f > 1.9 and p.y > 0.215 and p.y < 0.44 and abs(p.x) < 0.66:
				c = Color(0.02, 0.02, 0.02)   # front intake
			elif f < -2.02 and p.y < 0.31 and abs(p.x) < 0.62:
				c = Color(0.05, 0.05, 0.055)  # rear diffuser
			elif p.y < 0.19:
				c = Color(0.04, 0.04, 0.04)   # underside
			crow.append(c)
		grid.append(row)
		cols.append(crow)
	var norms := _grid_normals(grid, NU, NV, true)
	# one consistent orientation for the whole surface: the right flank at mid-car must face +X
	var flip := (norms[NU / 2][NV / 4] as Vector3).x < 0.0
	for i in NU:
		var end_ring := i <= 1 or i >= NU - 2
		for j in NV:
			var n: Vector3 = norms[i][j]
			if flip:
				n = -n
			if end_ring:
				# collapsed nose/tail rings: blend towards the axis direction
				var ax := Vector3(0, 0, -1) if i > NU / 2 else Vector3(0, 0, 1)
				n = (n * 0.3 + ax).normalized() if n.dot(ax) > -0.5 else ax
			norms[i][j] = n
	for i in NU - 1:
		for j in NV:
			var j2 := (j + 1) % NV
			mb.tri("paint", grid[i][j], grid[i + 1][j], grid[i + 1][j2], norms[i][j], norms[i + 1][j], norms[i + 1][j2],
				cols[i][j], cols[i + 1][j], cols[i + 1][j2])
			mb.tri("paint", grid[i][j], grid[i + 1][j2], grid[i][j2], norms[i][j], norms[i + 1][j2], norms[i][j2],
				cols[i][j], cols[i + 1][j2], cols[i][j2])

# glasshouse: windscreen, roof, side glass and the fastback hatch
func _cabin_ctrl(f: float) -> Array:
	var belt := body_raw(f, BELT_TH)
	var yt := roof_y(f)
	var front_k := sstep(0.0, 0.66, f)
	var rear_k := sstep(-0.9, -1.64, f)
	var wr := 0.565 + 0.15 * front_k - 0.07 * rear_k
	wr = min(wr, belt.x - 0.02)
	var yr: float = max(yt - 0.065, belt.y + 0.005)
	var pts := [
		Vector2(belt.x - 0.06, belt.y - 0.12),
		Vector2(belt.x, belt.y),
		Vector2(wr, yr),
		Vector2(wr * 0.55, yt - 0.014),
		Vector2(0.0, yt),
	]
	# left side (base -> centre) mirrored, then right side (centre -> base)
	var out := []
	for i in pts.size():
		var p: Vector2 = pts[i]
		out.append(Vector2(-p.x, p.y))
	for i in range(pts.size() - 2, -1, -1):
		out.append(pts[i])
	return out   # 9 points: L0 L1 L2 L3 C R3 R2 R1 R0

static func _cr2(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _build_cabin(mb) -> void:
	var NU := 110
	var SUB := 8
	var f0 := 0.66
	var f1 := -1.64
	var grid := []
	var segs := []   # per column: segment index + frac
	for i in NU:
		var f := lerpf(f0, f1, float(i) / (NU - 1))
		var c: Array = _cabin_ctrl(f)
		var row := []
		var n := c.size()
		for k in n - 1:
			var steps := SUB * 3 if (k == 1 or k == 6) else SUB
			for s in steps:
				var t := float(s) / steps
				var p: Vector2 = _cr2(c[max(k - 1, 0)], c[k], c[k + 1], c[min(k + 2, n - 1)], t)
				if k == 1 or k == 6:
					p = (c[k] as Vector2).lerp(c[k + 1], t)   # flat side glass
				row.append(L(Vector3(p.x, p.y, f)))
				if i == 0:
					segs.append(Vector2(k, t))
		var pe: Vector2 = c[n - 1]
		row.append(L(Vector3(pe.x, pe.y, f)))
		if i == 0:
			segs.append(Vector2(n - 1, 0.0))
		grid.append(row)
	var NV: int = grid[0].size()
	var norms := _grid_normals(grid, NU, NV, false)
	for i in NU:
		for j in NV:
			var n: Vector3 = norms[i][j]
			var p: Vector3 = grid[i][j]
			if n.dot(p - Vector3(0, 0.75, p.z)) < 0.0:
				norms[i][j] = -n
	for i in NU - 1:
		var fc := lerpf(f0, f1, (i + 0.5) / (NU - 1))
		for j in NV - 1:
			var sg: Vector2 = segs[j]
			var sg2: Vector2 = segs[j + 1]
			var k := int(sg.x)
			var fr := (sg.y + (sg2.y if sg2.x == sg.x else 1.0)) * 0.5
			var key := _cabin_material(fc, k, fr)
			mb.tri(key, grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], norms[i][j], norms[i + 1][j], norms[i + 1][j + 1])
			mb.tri(key, grid[i][j], grid[i + 1][j + 1], grid[i][j + 1], norms[i][j], norms[i + 1][j + 1], norms[i][j + 1])

func _cabin_material(f: float, k: int, fr: float) -> String:
	if k == 0 or k == 7:
		return "paint"
	if k == 1 or k == 6:
		var t := fr if k == 1 else 1.0 - fr     # 0 at belt, 1 at roof edge
		var front_edge := 0.60 - t * 0.12       # glass runs right up to the A-pillar
		var rear_edge := -1.02 + t * 0.40       # swept "Z" quarter window line
		if f < front_edge and f > rear_edge and t > 0.015 and t < 0.93:
			if f > front_edge - 0.02 or f < rear_edge + 0.025 or t > 0.9 or t < 0.035:
				return "trim"
			return "glass"
		if t >= 0.93 and f < front_edge + 0.05 and f > rear_edge - 0.05:
			return "trim"
		return "paint"
	# top section k = 2..5 -> q from 0 (left roof edge) to 1 (right roof edge)
	var q := (k - 2 + fr) / 4.0
	var e: float = min(q, 1.0 - q)
	if f > -0.17:
		if e > 0.055:
			return "glass" if (f < 0.62 and e > 0.07 and f > -0.14) else "trim"
		return "paint"   # slim A-pillars
	if f < -0.82 and f > -1.60:
		if e > 0.13:
			return "glass" if (f < -0.85 and f > -1.56 and e > 0.15) else "trim"
		return "paint"
	return "paint"

# ---------------------------------------------------------------- lights, seams
func _patch(mb, key: String, fa: float, fb: float, tha: float, thb: float, nf: int, nt: int, mask: Callable, off: float, both := true) -> void:
	var grid := []
	var nrm := []
	for i in nf + 1:
		var f := lerpf(fa, fb, float(i) / nf)
		var row := []
		var nrow := []
		for j in nt + 1:
			var th := lerpf(tha, thb, float(j) / nt)
			var p := body_raw(f, th)
			var pf := body_raw(f + 0.003, th)
			var pt := body_raw(f, th + 0.003)
			var n := (pf - p).cross(pt - p).normalized()
			var cen := Vector3(0, bottom_y(f) + (top_y(f) - bottom_y(f)) * 0.42, f)
			if n.dot(p - cen) < 0.0:
				n = -n
			row.append(p + n * off)
			nrow.append(n)
		grid.append(row)
		nrm.append(nrow)
	for side in ([1.0, -1.0] if both else [1.0]):
		for i in nf:
			for j in nt:
				var fc := lerpf(fa, fb, (i + 0.5) / nf)
				var tc := lerpf(tha, thb, (j + 0.5) / nt)
				if not mask.call(fc, tc):
					continue
				var q := [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
				var qn := [nrm[i][j], nrm[i + 1][j], nrm[i + 1][j + 1], nrm[i][j + 1]]
				var lp := []
				var ln := []
				for m in 4:
					var pp: Vector3 = q[m]
					var nn: Vector3 = qn[m]
					lp.append(L(Vector3(pp.x * side, pp.y, pp.z)))
					ln.append(L(Vector3(nn.x * side, nn.y, nn.z)))
				mb.quad(key, lp[0], lp[1], lp[2], lp[3], ln[0], ln[1], ln[2], ln[3])

func _build_lights_and_seams(mb) -> void:
	var D := PI / 180.0
	# headlights: long swept teardrops running up the front fenders
	var head_mask := func(f: float, th: float) -> bool:
		var tf := (f - 1.27) / 0.80
		if tf < 0.0 or tf > 1.0:
			return false
		var lo := lerpf(47.0, 9.0, pow(tf, 0.65)) * D
		var hi := lerpf(56.0, 54.0, tf) * D
		if f > 2.03:
			hi -= (f - 2.03) * 3.0
		return th > lo and th < hi
	_patch(mb, "headlight", 1.25, 2.09, 5 * D, 60 * D, 180, 110, head_mask, 0.004)
	# inner black headlight bezel line (thin trim border)
	var bezel := func(f: float, th: float) -> bool:
		var tf := (f - 1.27) / 0.80
		if tf < 0.0 or tf > 1.0:
			return false
		var lo := lerpf(47.0, 9.0, pow(tf, 0.65)) * D
		var hi := lerpf(56.0, 54.0, tf) * D
		return (th > lo - 1.2 * D and th < hi + 1.2 * D) and not (th > lo and th < hi)
	_patch(mb, "trim", 1.25, 2.09, 5 * D, 60 * D, 180, 110, bezel, 0.003)
	# taillights: boomerang shapes wrapping the rear corners
	var tail_mask := func(f: float, th: float) -> bool:
		var tf := (-f - 1.70) / 0.45
		if tf < 0.0 or tf > 1.0:
			return false
		var lo := lerpf(41.0, 6.0, pow(tf, 0.7)) * D
		var hi := lerpf(52.0, 47.0, tf) * D
		# notch that gives the Z33 lamp its arrow shape
		if tf > 0.55 and th > (lo + hi) * 0.5 and th < hi - 2.0 * D:
			return tf > 0.8
		return th > lo and th < hi
	_patch(mb, "taillight", -2.16, -1.68, 0 * D, 56 * D, 150, 100, tail_mask, 0.004)
	# amber side markers on the front fenders
	# vertical amber markers on the bumper corners
	var marker := func(f: float, th: float) -> bool:
		return f > 1.815 and f < 1.845 and th > -18 * D and th < 2 * D
	_patch(mb, "amber", 1.78, 1.88, -24 * D, 8 * D, 10, 24, marker, 0.003)
	# door seams (front and rear cut lines) and sill line
	var door_f := func(f: float, th: float) -> bool:
		return th < BELT_TH - 0.02
	_patch(mb, "seam", 0.552, 0.558, -38 * D, BELT_TH * 1.0, 1, 30, door_f, 0.002)
	_patch(mb, "seam", -0.716, -0.710, -38 * D, BELT_TH * 1.0, 1, 30, door_f, 0.002)
	var sill := func(f: float, th: float) -> bool:
		return true
	_patch(mb, "seam", -0.716, 0.558, -38.4 * D, -37.8 * D, 40, 1, sill, 0.002)
	# clamshell hood cut lines along the fender tops + across the nose
	_patch(mb, "seam", 0.70, 2.02, 60.0 * D, 60.6 * D, 60, 1, sill, 0.002)
	_patch(mb, "seam", 0.70, 0.705, 60.0 * D, 90.0 * D, 1, 16, sill, 0.002)
	# hatch / bumper line at the rear
	_patch(mb, "seam", -1.985, -1.98, 0.0 * D, 90.0 * D, 1, 30, sill, 0.002)
	# fuel door (right rear fender)
	var fuel := func(f: float, th: float) -> bool:
		return Vector2((f + 0.98) * 1.0, (th - 30 * D) * 0.8).length() < 0.075 and Vector2((f + 0.98), (th - 30 * D) * 0.8).length() > 0.068
	_patch(mb, "seam", -1.08, -0.88, 20 * D, 40 * D, 30, 30, fuel, 0.002, false)

func _build_details(mb) -> void:
	var D := PI / 180.0
	# headlight projectors
	for side in [1.0, -1.0]:
		for e in [[1.90, 30.0], [1.70, 42.0]]:
			var f: float = e[0]
			var th: float = e[1] * D
			var p := body_raw(f, th)
			var lp := L(Vector3(p.x * side, p.y, p.z))
			mb.ellipsoid("projector", Transform3D(Basis(), lp), Vector3(0.035, 0.03, 0.035), 12, 8)
	# side mirrors
	for side in [1.0, -1.0]:
		var p := body_raw(0.50, BELT_TH)
		var base := L(Vector3(p.x * side, p.y, p.z))
		var housing := base + Vector3(0.10 * side, 0.08, 0.02)
		mb.beam("paint", base + Vector3(-0.02 * side, 0.0, 0), housing, Vector3.UP, 0.05, 0.04, 0.03, 0.03)
		var hb := Basis(Vector3.UP, -0.12 * side)
		mb.ellipsoid("paint", Transform3D(hb, housing), Vector3(0.095, 0.055, 0.06), 16, 10)
		mb.ellipsoid("chrome", Transform3D(hb, housing + Vector3(0, 0, 0.032)), Vector3(0.085, 0.046, 0.032), 16, 10)
	# vertical door handles
	for side in [1.0, -1.0]:
		var p := body_raw(-0.52, 0.18)
		var lp := L(Vector3((p.x + 0.004) * side, p.y, p.z))
		mb.ellipsoid("chrome", Transform3D(Basis(), lp), Vector3(0.013, 0.07, 0.022), 10, 8)
	# twin exhaust tips
	for side in [1.0, -1.0]:
		var c := Vector3(0.52 * side, 0.27, 2.10)
		var bz := Basis(Vector3.RIGHT, PI / 2)
		mb.cylinder("chrome", Transform3D(bz, c), 0.048, 0.05, 0.2, 20, false)
		mb.cylinder("trim", Transform3D(bz, c + Vector3(0, 0, -0.01)), 0.04, 0.04, 0.2, 20, true)
	# rear hatch spoiler with 3rd brake light
	# hatch lip + 3rd brake light
	var sy := roof_y(-1.62) + 0.012
	var sp_b := Basis(Vector3.RIGHT, 0.12)
	mb.box("paint", Transform3D(sp_b, L(Vector3(0, sy, -1.65))), Vector3(1.0, 0.02, 0.09))
	mb.box("taillight", Transform3D(sp_b, L(Vector3(0, sy + 0.012, -1.64))), Vector3(0.36, 0.008, 0.025))
	# Nismo rear wing on the deck: uprights, airfoil, end plates, gurney flap
	var deck_f := -1.86
	var deck_y := top_y(deck_f)
	for side in [1.0, -1.0]:
		var up_base := L(Vector3(0.48 * side, deck_y - 0.01, deck_f))
		var up_top := L(Vector3(0.48 * side, deck_y + 0.15, deck_f - 0.05))
		mb.beam("paint", up_base, up_top, Vector3(0, 0, 1), 0.025, 0.02, 0.15, 0.11)
		mb.box("paint", Transform3D(Basis(), L(Vector3(0.71 * side, deck_y + 0.17, deck_f - 0.07))), Vector3(0.012, 0.11, 0.3))
	var wing_b := Basis(Vector3.RIGHT, -0.1)
	var wing_c := L(Vector3(0, deck_y + 0.175, deck_f - 0.07))
	mb.ellipsoid("paint", Transform3D(wing_b, wing_c), Vector3(0.70, 0.018, 0.13), 32, 8)
	mb.box("paint", Transform3D(wing_b, wing_c + Vector3(0, 0.022, 0.125)), Vector3(1.38, 0.025, 0.008))
	# front: gunmetal lip that follows the nose, intake fins, grille bar
	var prev_o := Vector3.ZERO
	var prev_i := Vector3.ZERO
	var steps := 24
	for k in steps + 1:
		var x := lerpf(-0.74, 0.74, float(k) / steps)
		var nf := nose_f(x) + 0.035 - 0.03 * pow(abs(x) / 0.74, 2.0)
		var po := L(Vector3(x, 0.19, nf))
		var pi := L(Vector3(x * 0.9, 0.19, min(nf - 0.3, 1.82)))
		if k > 0:
			mb.flat_quad("lip", prev_o, po, pi, prev_i, Vector3.UP)
			mb.flat_quad("lip", prev_o - Vector3(0, 0.022, 0), po - Vector3(0, 0.022, 0), pi - Vector3(0, 0.022, 0), prev_i - Vector3(0, 0.022, 0), Vector3.DOWN)
			mb.flat_quad("lip", prev_o, po, po - Vector3(0, 0.022, 0), prev_o - Vector3(0, 0.022, 0), (po - pi).normalized())
		prev_o = po
		prev_i = pi
	for fx in [-0.42, -0.24, 0.24, 0.42]:
		var fxf: float = fx
		mb.box("lip", Transform3D(Basis(), L(Vector3(fxf, 0.31, nose_f(fxf) - 0.07))), Vector3(0.018, 0.2, 0.14))
	mb.box("chrome", Transform3D(Basis(), L(Vector3(0, 0.455, nose_f(0.0) - 0.03))), Vector3(0.36, 0.01, 0.02))
	# side skirts between the wheel arches
	for side in [1.0, -1.0]:
		var pa := body_raw(0.86, -0.75)
		var pb := body_raw(-0.94, -0.75)
		mb.beam("lip", L(Vector3((pa.x + 0.015) * side, 0.24, 0.86)), L(Vector3((pb.x + 0.015) * side, 0.24, -0.94)),
			Vector3.UP, 0.05, 0.05, 0.1, 0.1)
	# license plates
	mb.box("plate", Transform3D(Basis(), L(Vector3(0, 0.33, 2.15))), Vector3(0.32, 0.16, 0.012))
	mb.box("plate", Transform3D(Basis(), L(Vector3(0, 0.60, -2.168))), Vector3(0.32, 0.16, 0.012))
	# windscreen wipers
	for side in [1.0, -1.0]:
		var a := L(Vector3(0.05 * side, 0.885, 0.64))
		var b := L(Vector3(0.58 * side - 0.3, 0.9, 0.60))
		if side < 0:
			b = L(Vector3(-0.15, 0.9, 0.60))
			a = L(Vector3(-0.62, 0.885, 0.63))
		mb.beam("trim", a, b, Vector3.UP, 0.02, 0.015, 0.015, 0.012)
	# underbody tray
	mb.box("trim", Transform3D(Basis(), Vector3(0, 0.17, 0)), Vector3(1.3, 0.01, 3.6))

func _build_interior(mb) -> void:
	# floor and tunnel
	mb.box("interior", Transform3D(Basis(), L(Vector3(0, 0.22, -0.25))), Vector3(1.45, 0.02, 2.0))
	mb.box("interior", Transform3D(Basis(), L(Vector3(0, 0.36, -0.1))), Vector3(0.24, 0.26, 1.2))
	# dashboard
	mb.box("interior", Transform3D(Basis(Vector3.RIGHT, -0.15), L(Vector3(0, 0.73, 0.52))), Vector3(1.42, 0.2, 0.42))
	mb.box("interior", Transform3D(Basis(), L(Vector3(0, 0.55, 0.45))), Vector3(1.4, 0.2, 0.3))
	# driver's binnacle (moves with the column on the real car) - driver sits on the left (LHD)
	var dx := -0.37
	mb.box("interior", Transform3D(Basis(Vector3.RIGHT, 0.25), L(Vector3(dx, 0.87, 0.42))), Vector3(0.42, 0.10, 0.18))
	for g in [[-0.09, 0.075], [0.07, 0.06], [0.17, 0.04]]:
		var gp := L(Vector3(dx + float(g[0]), 0.86, 0.335))
		mb.cylinder("gauge", Transform3D(Basis(Vector3.RIGHT, PI / 2 - 0.25), gp), float(g[1]), float(g[1]), 0.01, 20)
		mb.torus("alu", Transform3D(Basis(Vector3.RIGHT, PI / 2 - 0.25), gp), float(g[1]), 0.006, 20, 6)
	# the three centre gauge pods on top of the dash
	for i in 3:
		var gx := -0.07 + i * 0.07
		var gp := L(Vector3(gx, 0.86, 0.47))
		var b := Basis(Vector3.UP, -0.35) * Basis(Vector3.RIGHT, PI / 2 - 0.35)
		mb.cylinder("interior", Transform3D(b, gp), 0.034, 0.034, 0.05, 16)
		mb.cylinder("gauge", Transform3D(b, gp + Vector3(0.008, 0.01, 0.02)), 0.028, 0.028, 0.012, 16)
	# centre stack and shifter
	mb.box("interior", Transform3D(Basis(Vector3.RIGHT, 0.3), L(Vector3(0, 0.58, 0.36))), Vector3(0.26, 0.28, 0.08))
	mb.box("alu", Transform3D(Basis(Vector3.RIGHT, 0.3), L(Vector3(0, 0.6, 0.325))), Vector3(0.2, 0.08, 0.005))
	mb.cylinder("interior", Transform3D(Basis(), L(Vector3(0, 0.55, 0.05))), 0.012, 0.01, 0.16, 8)
	mb.ellipsoid("alu", Transform3D(Basis(), L(Vector3(0, 0.64, 0.05))), Vector3(0.028, 0.03, 0.028), 12, 8)
	mb.box("interior", Transform3D(Basis(), L(Vector3(0, 0.5, -0.3))), Vector3(0.18, 0.06, 0.4))
	# seats
	for sx in [-0.37, 0.37]:
		var sxf: float = sx
		var fb := -0.38
		mb.box("leather", Transform3D(Basis(Vector3.RIGHT, -0.08), L(Vector3(sxf, 0.32, fb))), Vector3(0.48, 0.11, 0.5))
		for bs in [-1.0, 1.0]:
			mb.box("leather", Transform3D(Basis(Vector3.FORWARD, 0.25 * bs), L(Vector3(sxf + 0.22 * bs, 0.38, fb))), Vector3(0.08, 0.13, 0.48))
		var back := Basis(Vector3.RIGHT, 0.26)
		mb.box("leather", Transform3D(back, L(Vector3(sxf, 0.68, fb - 0.32))), Vector3(0.48, 0.66, 0.11))
		for bs in [-1.0, 1.0]:
			mb.box("leather", Transform3D(back * Basis(Vector3.UP, 0.4 * bs), L(Vector3(sxf + 0.22 * bs, 0.62, fb - 0.28))), Vector3(0.08, 0.5, 0.14))
		mb.box("accent", Transform3D(back, L(Vector3(sxf, 0.68, fb - 0.265))), Vector3(0.22, 0.5, 0.01))
		mb.box("leather", Transform3D(back, L(Vector3(sxf, 1.08, fb - 0.43))), Vector3(0.26, 0.17, 0.1))
	# door cards
	for side in [1.0, -1.0]:
		mb.box("interior", Transform3D(Basis(), L(Vector3(0.71 * side, 0.6, -0.08))), Vector3(0.04, 0.5, 1.25))
		mb.box("alu", Transform3D(Basis(), L(Vector3(0.69 * side, 0.72, 0.05))), Vector3(0.012, 0.03, 0.18))
	# strut-tower brace behind the seats, rear bulkhead, cargo floor, headliner
	mb.cylinder("alu", Transform3D(Basis(Vector3.FORWARD, PI / 2), L(Vector3(0, 0.98, -0.92))), 0.022, 0.022, 1.3, 10)
	mb.box("interior", Transform3D(Basis(Vector3.RIGHT, 0.2), L(Vector3(0, 0.62, -0.95))), Vector3(1.35, 0.7, 0.04))
	mb.box("interior", Transform3D(Basis(), L(Vector3(0, 0.66, -1.4))), Vector3(1.3, 0.02, 0.8))
	mb.box("interior", Transform3D(Basis(), L(Vector3(0, 1.262, -0.5))), Vector3(0.78, 0.012, 0.6))

func _build_steering_wheel() -> void:
	var pivot := Node3D.new()
	pivot.name = "SteeringColumn"
	pivot.position = L(Vector3(-0.37, 0.85, 0.16))
	pivot.rotation = Vector3(-0.38, 0, 0)   # tilted towards the driver
	body.add_child(pivot)
	steering_wheel = Node3D.new()
	pivot.add_child(steering_wheel)
	var mb := MB.new()
	var face := Basis(Vector3.RIGHT, PI / 2)   # wheel lies in the XY plane, facing +Z (driver)
	mb.torus("leather", Transform3D(face, Vector3.ZERO), 0.18, 0.017, 36, 10)
	mb.cylinder("interior", Transform3D(face, Vector3(0, 0, -0.02)), 0.055, 0.06, 0.05, 16)
	mb.ellipsoid("alu", Transform3D(face, Vector3(0, 0, 0.008)), Vector3(0.025, 0.006, 0.025), 12, 6)
	for a in [0.0, PI, -PI / 2]:
		var dir := Vector3(cos(a), sin(a), 0)
		mb.beam("interior", dir * 0.05, dir * 0.17, Vector3(0, 0, 1), 0.04, 0.03, 0.014, 0.012)
	mb.box("accent", Transform3D(Basis(), Vector3(0, 0.18, 0)), Vector3(0.012, 0.02, 0.036))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build(mats)
	steering_wheel.add_child(mi)
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.04
	cm.height = 0.3
	col.mesh = cm
	col.material_override = mats["interior"]
	col.rotation = Vector3(PI / 2, 0, 0)
	col.position = Vector3(0, 0, -0.17)
	pivot.add_child(col)

func _build_labels() -> void:
	for e in [[Vector3(0, 0.33, -2.158), 0.0], [Vector3(0, 0.60, 2.176), PI]]:
		var lbl := Label3D.new()
		lbl.text = "350Z"
		lbl.font_size = 64
		lbl.pixel_size = 0.0018
		lbl.modulate = Color(0.08, 0.1, 0.25)
		lbl.outline_size = 0
		lbl.position = e[0]
		lbl.rotation = Vector3(0, float(e[1]) + PI, 0)
		lbl.double_sided = false
		body.add_child(lbl)
	# round "Z" badges on the front fenders, behind the wheels
	for side in [1.0, -1.0]:
		var p := body_raw(0.78, 0.12)
		var pos := L(Vector3((p.x + 0.004) * side, p.y, p.z))
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.032
		cm.bottom_radius = 0.032
		cm.height = 0.004
		disc.mesh = cm
		disc.material_override = mats["chrome"]
		disc.position = pos
		disc.rotation = Vector3(0, 0, PI / 2)
		body.add_child(disc)
		var z := Label3D.new()
		z.text = "Z"
		z.font_size = 64
		z.pixel_size = 0.0007
		z.modulate = Color(0.05, 0.05, 0.05)
		z.outline_size = 0
		z.position = pos + Vector3(0.004 * side, 0, 0)
		z.rotation = Vector3(0, PI / 2 * side, 0)
		z.double_sided = false
		body.add_child(z)
	dash_label = Label3D.new()
	dash_label.text = ""
	dash_label.font_size = 48
	dash_label.pixel_size = 0.0007
	dash_label.modulate = Color(1.0, 0.6, 0.2)
	dash_label.outline_size = 0
	dash_label.shaded = false
	dash_label.position = L(Vector3(-0.37, 0.935, 0.34))
	dash_label.rotation = Vector3(-0.35, 0, 0)
	dash_label.double_sided = false
	body.add_child(dash_label)

func _build_lamps() -> void:
	for side in [1.0, -1.0]:
		var sl := SpotLight3D.new()
		var p := body_raw(1.85, 0.55)
		sl.position = L(Vector3(p.x * 0.8 * side, p.y, p.z + 0.1))
		sl.rotation = Vector3(-0.06, 0, 0)
		sl.spot_range = 70.0
		sl.spot_angle = 28.0
		sl.spot_attenuation = 0.8
		sl.light_energy = 6.0
		sl.light_color = Color(1.0, 0.95, 0.85)
		sl.shadow_enabled = false
		sl.visible = false
		body.add_child(sl)
		head_lights.append(sl)

# ---------------------------------------------------------------- wheels
func _build_wheel_meshes() -> Array:
	# axle along local Y here; rotated onto X when placed. Outer face = +Y.
	var tire := MB.new()
	var prof := [Vector2(0.232, -0.112), Vector2(0.27, -0.124), Vector2(0.305, -0.122), Vector2(0.322, -0.112),
		Vector2(0.33, -0.09), Vector2(0.331, 0.0), Vector2(0.33, 0.09), Vector2(0.322, 0.112),
		Vector2(0.305, 0.122), Vector2(0.27, 0.124), Vector2(0.232, 0.112)]
	tire.lathe("rubber", Transform3D(), prof, 48, Color.WHITE, 1.0)
	var tire_mesh: ArrayMesh = tire.build(mats)

	var rim := MB.new()
	var barrel := [Vector2(0.232, 0.106), Vector2(0.226, 0.112), Vector2(0.214, 0.106), Vector2(0.21, 0.07),
		Vector2(0.205, -0.02), Vector2(0.212, -0.1), Vector2(0.226, -0.108)]
	rim.lathe("rim", Transform3D(), barrel, 48)
	# inner barrel darker
	rim.lathe("rim_dark", Transform3D(), [Vector2(0.204, 0.07), Vector2(0.2, -0.1)], 48)
	# Nismo-style 5 wide, deeply concave spokes that flare out towards the lip
	for i in 5:
		var a := TAU * i / 5.0
		var hub := Vector3(cos(a) * 0.058, 0.035, sin(a) * 0.058)
		var mid := Vector3(cos(a) * 0.14, 0.072, sin(a) * 0.14)
		var outer := Vector3(cos(a) * 0.212, 0.098, sin(a) * 0.212)
		rim.beam("rim", hub, mid, Vector3(0, 1, 0), 0.042, 0.05, 0.034, 0.03)
		rim.beam("rim", mid, outer, Vector3(0, 1, 0), 0.05, 0.075, 0.03, 0.024)
		# machined groove down the middle of each spoke
		rim.beam("rim_dark", hub + Vector3(0, 0.018, 0), outer + Vector3(0, 0.013, 0), Vector3(0, 1, 0), 0.006, 0.01, 0.004, 0.004)
	rim.cylinder("rim", Transform3D(Basis(), Vector3(0, 0.05, 0)), 0.072, 0.066, 0.035, 20)
	rim.cylinder("rim_dark", Transform3D(Basis(), Vector3(0, 0.07, 0)), 0.03, 0.026, 0.012, 16)
	for i in 5:
		var a := TAU * i / 5.0 + TAU / 10.0
		rim.cylinder("chrome", Transform3D(Basis(), Vector3(cos(a) * 0.048, 0.07, sin(a) * 0.048)), 0.009, 0.008, 0.02, 6)
	# brake disc + hat (spins with the wheel)
	rim.cylinder("disc", Transform3D(Basis(), Vector3(0, -0.035, 0)), 0.165, 0.165, 0.026, 40)
	rim.cylinder("rim_dark", Transform3D(Basis(), Vector3(0, -0.012, 0)), 0.09, 0.09, 0.03, 24)
	var rim_mesh: ArrayMesh = rim.build(mats)

	var cal := MB.new()
	# caliper arcs over the back-top of the disc
	for k in 5:
		var a := lerpf(0.55, 1.45, k / 4.0)
		cal.box("caliper", Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 0.15, -0.035, sin(a) * 0.15)), Vector3(0.05, 0.075, 0.06))
	var cal_mesh: ArrayMesh = cal.build(mats)
	return [tire_mesh, rim_mesh, cal_mesh]

func _build_wheels() -> void:
	var meshes := _build_wheel_meshes()
	var defs := [[FA, TRACK_F, true, false], [FA, TRACK_F, true, true], [RA, TRACK_R, false, false], [RA, TRACK_R, false, true]]
	for d in defs:
		var f: float = d[0]
		var tw: float = d[1]
		var front: bool = d[2]
		var left: bool = d[3]
		var pivot := Node3D.new()
		pivot.position = Vector3(-tw if left else tw, AXLE_Y, -f)
		add_child(pivot)
		var mount := Node3D.new()
		# Y axis -> X axis; left wheels turned around so their face points outward
		mount.basis = Basis(Vector3.UP, PI if left else 0.0) * Basis(Vector3.FORWARD, PI / 2)
		pivot.add_child(mount)
		var spin := Node3D.new()
		mount.add_child(spin)
		for m in [meshes[0], meshes[1]]:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			spin.add_child(mi)
		var cmi := MeshInstance3D.new()
		cmi.mesh = meshes[2]
		mount.add_child(cmi)
		wheels.append({"pivot": pivot, "spin": spin, "left": left, "front": front})

# ---------------------------------------------------------------- runtime
var brake_on := false
func set_brake(on: bool) -> void:
	if on == brake_on:
		return
	brake_on = on
	tail_mat.emission_energy_multiplier = 3.0 if on else 0.35
	_sync_dent_mat(tail_mat)

var lights_on := false
var hl_broken := [false, false]     # left, right (knocked out in a crash)

# side 0 = left, 1 = right; head_lights[] was built right first
func headlight_broken(side: int, broken: bool) -> void:
	if hl_broken[side] == broken:
		return
	hl_broken[side] = broken
	set_headlights(lights_on)

func set_headlights(on: bool) -> void:
	lights_on = on
	for i in head_lights.size():
		var side := 1 if i == 0 else 0
		head_lights[i].visible = on and not hl_broken[side]
	(mats["projector"] as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.4
	_sync_dent_mat(mats["projector"])

# ---------------------------------------------------------------- body damage
# Dents are done on the GPU: each dent is a centre, a push direction, a radius,
# a depth and (optionally) the axis of the thing that was hit - vertical for a
# tree trunk, along the beam for a guardrail - so the panel bends around its
# shape. Every material on the body shell gets a copy of its own shader with a
# few lines added to vertex() that push nearby vertices in and bend the normals,
# so the creases catch the light. No mesh data is rebuilt, any vertex count works.
const MAX_DENTS := 24
const DENT_CODE := """
uniform int dent_count = 0;
uniform vec4 dent_c[24];
uniform vec4 dent_u[24];
uniform vec4 dent_a[24];
// crumple frame: movement (xyz) and bending (w) of 4 x 3 x 12 points
uniform vec4 lat[144];
uniform int lat_on = 0;
varying float dent_amt;
varying vec3 rest_pos;
// value noise for the crumple wrinkles
float _h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float _vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(_h3(i), _h3(i + vec3(1, 0, 0)), f.x), mix(_h3(i + vec3(0, 1, 0)), _h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(_h3(i + vec3(0, 0, 1)), _h3(i + vec3(1, 0, 1)), f.x), mix(_h3(i + vec3(0, 1, 1)), _h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
// sharp-ridged folds, like scrunched foil (ridges where the noise crosses 0.5)
float _crumple(vec3 p) {
	// two layers of folds (~9 cm and ~4 cm): finer than that would be smaller
	// than the spacing of the body's vertices and turn into jagged spikes
	float a = 1.0 - abs(_vn(p * 11.0) * 2.0 - 1.0);
	float b = 1.0 - abs(_vn(p * 24.0 + 17.0) * 2.0 - 1.0);
	return (a * a * 0.65 + b * b * 0.35) * 2.0 - 0.9;
}
vec4 _lat(int i, int j, int k) {
	return lat[(k * 3 + j) * 4 + i];
}
// trilinear blend of the crumple frame's points around p
vec4 _lattice(vec3 p) {
	vec3 g = clamp((p - vec3(-0.9, 0.15, -2.2)) / vec3(0.6, 0.5, 0.4), vec3(0.0), vec3(2.999, 1.999, 10.999));
	ivec3 b = ivec3(floor(g));
	vec3 f = g - vec3(b);
	vec4 x00 = mix(_lat(b.x, b.y, b.z), _lat(b.x + 1, b.y, b.z), f.x);
	vec4 x10 = mix(_lat(b.x, b.y + 1, b.z), _lat(b.x + 1, b.y + 1, b.z), f.x);
	vec4 x01 = mix(_lat(b.x, b.y, b.z + 1), _lat(b.x + 1, b.y, b.z + 1), f.x);
	vec4 x11 = mix(_lat(b.x, b.y + 1, b.z + 1), _lat(b.x + 1, b.y + 1, b.z + 1), f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}
float _apply_dents(inout vec3 v, inout vec3 n) {
	vec3 disp = vec3(0.0);
	vec3 g = vec3(0.0);
	float wrinkle = 0.0;
	for (int i = 0; i < dent_count; i++) {
		vec3 d = v - dent_c[i].xyz;
		float r = dent_c[i].w;
		float fade = 1.0;
		if (dent_a[i].w > 0.0) {
			float al = dot(d, dent_a[i].xyz);
			d -= dent_a[i].xyz * al;
			fade = 1.0 - smoothstep(dent_a[i].w * 0.6, dent_a[i].w, abs(al));
		}
		float s = length(d) / r;
		if (s < 1.0) {
			float q = 1.0 - s * s;
			float h = dent_u[i].w * fade;
			disp += dent_u[i].xyz * h * q * q;
			// crumple: strongest in the walls of the dent, still there in the middle
			wrinkle += h * (0.3 * q * q + 1.1 * q * (1.0 - q));
			if (s > 0.0001) {
				// slope of the dent: walls of the dimple face its centre
				g += normalize(d) * (h * -4.0 * s * q / r) * max(dot(-dent_u[i].xyz, n), 0.0);
			}
		}
	}
	// the structure folding: the whole panel follows the crumple frame
	if (lat_on == 1) {
		vec4 L = _lattice(v);
		disp += L.xyz;
		wrinkle += L.w;
	}
	// fold the metal in and out along the surface normal (sampled on the
	// undamaged position, so the folds stay put as a dent deepens)
	vec3 fold = vec3(0.0);
	if (wrinkle > 0.0) {
		fold = n * _crumple(v) * min(wrinkle, 0.12) * 0.4;
	}
	v += disp + fold;
	n = normalize(n + (g - n * dot(g, n)));
	return min(wrinkle, 0.12) * 0.6 + (length(disp) > 0.01 ? 0.012 : 0.0);
}
"""
# spider-web cracks for the glass (Voronoi cell edges, denser near the impact)
const CRACK_CODE := """
uniform vec4 crack_c = vec4(0.0);
float _cracks(vec3 p) {
	if (crack_c.w <= 0.0) {
		return 0.0;
	}
	float r = distance(p, crack_c.xyz);
	float reach = 0.12 + crack_c.w * 0.9;
	if (r > reach) {
		return 0.0;
	}
	vec3 q = p * mix(14.0, 46.0, smoothstep(reach, 0.0, r));
	vec3 ip = floor(q);
	float f1 = 9.0;
	float f2 = 9.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 cell = ip + vec3(float(x), float(y), float(z));
				vec3 pt = cell + vec3(_h3(cell), _h3(cell + 7.1), _h3(cell + 13.7));
				float d = distance(q, pt);
				if (d < f1) {
					f2 = f1;
					f1 = d;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	float web = 1.0 - smoothstep(0.0, 0.07, f2 - f1);
	return web * (1.0 - smoothstep(reach * 0.7, reach, r)) + smoothstep(reach * 0.25, 0.0, r) * 0.5;
}
"""
var damage_enabled := false
var shell: MeshInstance3D
var dent_mats := {}          # original material -> its denting ShaderMaterial copy
var extra_mats: Array = []   # per-window glass copies (get the same updates)
var dents: Array = []        # each: {c, u, a, L, r, h, t}
var damage                   # car_damage.gd (crumple frame, loose parts, glass)
var car_ref

const CarDamage = preload("res://scripts/car_damage.gd")

func set_damage_enabled(on: bool, p_car = null) -> void:
	damage_enabled = on
	if p_car:
		car_ref = p_car
	if shell == null:
		shell = body.get_node_or_null("Shell")
	if shell == null:
		return
	if on and damage == null:
		damage = CarDamage.new()
		damage.name = "Damage"
		add_child(damage)
		damage.setup(self, car_ref)
		damage.split()
		damage.setup_glass_mats(func(orig):
			var gm = _make_dent_mat(orig)
			if gm is ShaderMaterial:
				gm = gm.duplicate()
				extra_mats.append(gm)
			return gm)
	_apply_dent_overrides(on)
	repair()

func _apply_dent_overrides(on: bool) -> void:
	var meshes: Array = damage.damage_meshes() if damage else [shell]
	for mi in meshes:
		var mm: MeshInstance3D = mi
		if damage and mm.name.begins_with("win_"):
			# windows keep their own glass copies (each has its own cracks)
			for i in mm.mesh.get_surface_count():
				if not on:
					mm.set_surface_override_material(i, null)
			if on:
				var w: Dictionary = damage.windows[String(mm.name)]
				for i in mm.mesh.get_surface_count():
					mm.set_surface_override_material(i, w["mat"][i])
			continue
		for i in mm.mesh.get_surface_count():
			var orig: Material = mm.mesh.surface_get_material(i)
			if on:
				if not dent_mats.has(orig):
					dent_mats[orig] = _make_dent_mat(orig)
				mm.set_surface_override_material(i, dent_mats[orig])
			else:
				mm.set_surface_override_material(i, null)

# a car-part shader with the dent code built in; it reproduces what the body's
# StandardMaterial3Ds use (colour / vertex colour, metal, roughness, glow,
# clear coat, transparency, culling) so the car looks the same with damage on
const PART_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, diffuse_burley, specular_schlick_ggx%s;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_vcol = false;
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform float specular = 0.5;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float clearcoat = 0.0;
uniform float clearcoat_roughness = 0.5;
uniform vec3 uv1_scale = vec3(1.0);
%s
void vertex() {
	rest_pos = VERTEX;
	dent_amt = _apply_dents(VERTEX, NORMAL);
	UV = UV * uv1_scale.xy;
}
void fragment() {
	vec4 c = albedo * texture(tex_albedo, UV);
	if (use_vcol) {
		c *= COLOR;
	}
	// crumpled metal is faceted: light it by the actual folded faces (sharp
	// creases catching the light like scrunched foil) instead of smooth normals
	float crum = smoothstep(0.008, 0.05, dent_amt);
	if (crum > 0.0) {
		vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		if (dot(fn, NORMAL) < 0.0) {
			fn = -fn;
		}
		NORMAL = normalize(mix(NORMAL, fn, crum * 0.9));
	}
	// bent metal: scuffed, scraped paint (lighter, duller, clear coat gone)
	float scuff = smoothstep(0.05, 0.2, dent_amt);
	ALBEDO = mix(c.rgb, vec3(0.32, 0.31, 0.3), scuff * 0.55);
	METALLIC = metallic;
	ROUGHNESS = mix(roughness, 0.75, scuff);
	SPECULAR = specular;
	EMISSION = emission.rgb * emission_energy * (1.0 - scuff * 0.8);
	CLEARCOAT = clearcoat * (1.0 - scuff);
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	%s
}
"""
var part_shaders := {}       # "cull/alpha" key -> Shader

func _part_shader(cull_off: bool, alpha: bool) -> Shader:
	var key := "%s%s" % [cull_off, alpha]
	if not part_shaders.has(key):
		var sh := Shader.new()
		var alpha_code := "float ck = _cracks(rest_pos);\n\tALBEDO = mix(ALBEDO, vec3(0.86, 0.9, 0.92), ck);\n\tROUGHNESS = mix(ROUGHNESS, 0.5, ck);\n\tALPHA = clamp(c.a + ck * 0.8, 0.0, 1.0);"
		sh.code = PART_SHADER % [", cull_disabled" if cull_off else "", DENT_CODE + (CRACK_CODE if alpha else ""), alpha_code if alpha else ""]
		part_shaders[key] = sh
	return part_shaders[key]

# a denting copy of one of the body's materials
func _make_dent_mat(orig: Material) -> Material:
	if not orig is StandardMaterial3D:
		return orig
	var m: StandardMaterial3D = orig
	var alpha := m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	var sm := ShaderMaterial.new()
	sm.shader = _part_shader(m.cull_mode == BaseMaterial3D.CULL_DISABLED, alpha)
	sm.set_shader_parameter("albedo", m.albedo_color)
	if m.albedo_texture:
		sm.set_shader_parameter("tex_albedo", m.albedo_texture)
	sm.set_shader_parameter("use_vcol", m.vertex_color_use_as_albedo)
	sm.set_shader_parameter("metallic", m.metallic)
	sm.set_shader_parameter("roughness", m.roughness)
	sm.set_shader_parameter("specular", m.metallic_specular)
	sm.set_shader_parameter("uv1_scale", m.uv1_scale)
	sm.set_shader_parameter("clearcoat", m.clearcoat if m.clearcoat_enabled else 0.0)
	sm.set_shader_parameter("clearcoat_roughness", m.clearcoat_roughness)
	_sync_emission(m, sm)
	sm.render_priority = m.render_priority
	return sm

func _sync_emission(m: StandardMaterial3D, sm: ShaderMaterial) -> void:
	sm.set_shader_parameter("emission", m.emission)
	sm.set_shader_parameter("emission_energy", m.emission_energy_multiplier if m.emission_enabled else 0.0)

func _sync_dent_mat(orig: Material) -> void:
	if dent_mats.has(orig) and dent_mats[orig] is ShaderMaterial:
		_sync_emission(orig, dent_mats[orig])

# One impact: local dent + crumple frame + loose parts + glass.
# kind "tree" / "rail" / "ground"; push = world direction into the car;
# axis = obstacle axis (trunk vertical, rail along its beam); vn = closing speed.
func impact(kind: String, wp: Vector3, push: Vector3, axis: Vector3, vn: float, radius: float) -> void:
	if not damage_enabled:
		return
	match kind:
		"tree":
			add_dent(wp, push, axis, 4.0, radius + 0.3 + min(vn * 0.012, 0.2), clampf((vn - 2.0) * 0.016, 0.0, 0.22))
		"rail":
			add_dent(wp, push, axis, 1.3, 0.17 + min(vn * 0.008, 0.12), clampf((vn - 1.5) * 0.016, 0.0, 0.14))
		"ground":
			add_dent(wp, push, Vector3.ZERO, 0.0, 0.5, clampf((vn - 3.5) * 0.025, 0.0, 0.2))
	if damage:
		damage.hit(kind, wp, push, axis, vn, radius)

# A hit at world point p, pushing the body along world direction push (into the
# car). axis/half_len: shape of what was hit (ZERO = round). Dents at the same
# spot deepen instead of piling up.
func add_dent(p: Vector3, push: Vector3, axis: Vector3, half_len: float, radius: float, depth: float) -> void:
	if not damage_enabled or shell == null or depth <= 0.002:
		return
	var inv := shell.global_transform.affine_inverse()
	var c := inv * p
	var u := (inv.basis * push).normalized()
	var a := Vector3.ZERO
	if axis != Vector3.ZERO:
		a = (inv.basis * axis).normalized()
	var now := Time.get_ticks_msec() / 1000.0
	depth = min(depth, radius * 0.55)
	for dn in dents:
		if (dn["c"] as Vector3).distance_to(c) < max(dn["r"], radius) * 0.5 and (dn["u"] as Vector3).dot(u) > 0.6:
			var fresh: bool = now - dn["t"] > 0.35   # a new hit adds to the dent, a held contact doesn't
			dn["h"] = min(max(dn["h"], depth) + (depth * 0.6 if fresh else 0.0), max(dn["r"], radius) * 0.6)
			dn["r"] = max(dn["r"], radius)
			dn["t"] = now
			_upload_dents()
			return
	if dents.size() >= MAX_DENTS:
		dents.pop_front()   # oldest, smallest detail goes first
	dents.append({"c": c, "u": u, "a": a, "L": half_len if a != Vector3.ZERO else 0.0, "r": radius, "h": depth, "t": now})
	_upload_dents()

func repair() -> void:
	dents.clear()
	_upload_dents()
	if damage:
		damage.repair()
		if damage_enabled:
			_apply_dent_overrides(true)

func damage_amount() -> float:
	var s := 0.0
	for dn in dents:
		s += dn["h"]
	return s

func _all_dent_mats() -> Array:
	var out := []
	for sm in dent_mats.values():
		if sm is ShaderMaterial:
			out.append(sm)
	out.append_array(extra_mats)
	return out

func _upload_dents() -> void:
	var cs := PackedVector4Array()
	var us := PackedVector4Array()
	var as_ := PackedVector4Array()
	cs.resize(MAX_DENTS)
	us.resize(MAX_DENTS)
	as_.resize(MAX_DENTS)
	for i in dents.size():
		var dn: Dictionary = dents[i]
		var c: Vector3 = dn["c"]
		var u: Vector3 = dn["u"]
		var a: Vector3 = dn["a"]
		cs[i] = Vector4(c.x, c.y, c.z, dn["r"])
		us[i] = Vector4(u.x, u.y, u.z, dn["h"])
		as_[i] = Vector4(a.x, a.y, a.z, dn["L"])
	for sm in _all_dent_mats():
		sm.set_shader_parameter("dent_count", dents.size())
		sm.set_shader_parameter("dent_c", cs)
		sm.set_shader_parameter("dent_u", us)
		sm.set_shader_parameter("dent_a", as_)

# crumple frame movement from car_damage.gd
func upload_lattice(arr: PackedVector4Array) -> void:
	var any := false
	for v in arr:
		if v != Vector4.ZERO:
			any = true
			break
	for sm in _all_dent_mats():
		sm.set_shader_parameter("lat", arr)
		sm.set_shader_parameter("lat_on", 1 if any else 0)

# wheel damage from car.gd: camber (rad) and wobble amount per wheel, FL FR RL RR
var wheel_camber := [0.0, 0.0, 0.0, 0.0]
var wheel_wobble := [0.0, 0.0, 0.0, 0.0]

func set_paint(c: Color) -> void:
	paint_color = c
	(mats["paint"] as StandardMaterial3D).albedo_color = c
	# with damage on the body draws with a shader copy of the paint: recolour that too
	var dm = dent_mats.get(mats["paint"])
	if dm is ShaderMaterial:
		dm.set_shader_parameter("albedo", c)

# wheel i (FL FR RL RR) has come off: hide the tyre + rim on the car (the
# hub and brake caliper stay) and return a copy of it to throw
func detach_wheel(i: int) -> Node3D:
	for w in wheels:
		var wi: int = (0 if w["front"] else 2) + (0 if w["left"] else 1)
		if wi == i and not w.get("off", false):
			w["off"] = true
			var spin: Node3D = w["spin"]
			var copy: Node3D = spin.duplicate()
			copy.transform = spin.global_transform   # world placement, not in the tree yet
			spin.visible = false
			return copy
	return null

func reattach_wheels() -> void:
	for w in wheels:
		w["off"] = false
		(w["spin"] as Node3D).visible = true

func update_visuals(steer: float, wheel_spin_f: float, wheel_spin_r: float, roll: float, pitch: float, dt: float, wheel_offsets: Array = []) -> void:
	for w in wheels:
		var pivot: Node3D = w["pivot"]
		var spin: Node3D = w["spin"]
		if wheel_offsets.size() == 4:
			# order matches car.gd WHEEL_LOCAL: FL, FR, RL, RR
			var wi: int = (0 if w["front"] else 2) + (0 if w["left"] else 1)
			pivot.position.y = AXLE_Y + float(wheel_offsets[wi])
		var wj: int = (0 if w["front"] else 2) + (0 if w["left"] else 1)
		if w["front"]:
			pivot.rotation.y = steer
		var ds: float = (wheel_spin_f if w["front"] else wheel_spin_r) * dt
		# local Y of spin node is the axle; left wheels are mirrored
		if not w.get("off", false):
			spin.rotate_object_local(Vector3.UP, ds if w["left"] else -ds)
		# a bent wheel / suspension: leans in and wobbles as it turns
		var spin_ang: float = w.get("ang", 0.0) + ds
		w["ang"] = spin_ang
		var lean: float = wheel_camber[wj] * (-1.0 if w["left"] else 1.0)
		pivot.rotation.z = lean + sin(spin_ang) * wheel_wobble[wj]
		pivot.rotation.x = cos(spin_ang) * wheel_wobble[wj] * 0.6
	if steering_wheel:
		steering_wheel.rotation.z = steer * 14.0   # 14:1 steering ratio (full lock ~1.6 turns)
	body.rotation = Vector3(pitch, 0, roll)
	if mirrors_on:
		for m in mirrors:
			_place_mirror_cam(m)

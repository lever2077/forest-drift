# A car built from downloaded model files (see res://models/cars/) instead of
# the procedural 350Z. It plugs into everything the 350Z model offers - wheels
# that steer, spin and move with the suspension, the steering wheel (and the VR
# hands on it), headlights, brake lights, paint skins, dents and the dash
# readout - so car.gd drives it with exactly the same physics.
#
# CC96 by IceMaan (CC0): 3 body kits, 4 rims, a spoiler, as FBX. The body is
# modelled nose towards +X, about 3.5 m long; it's scaled up so its wheelbase
# matches the physics (2.65 m) and turned to face -Z like the rest of the game.
extends "res://scripts/car_model.gd"

var def := {}                 # the car's entry in profile.gd CARS
const CC96_DIR := "res://models/cars/cc96/"
const CC96_SCALE := 1.29      # model wheelbase ~2.05 m -> 2.65 m
const CC96_WHEEL_K := 1.375   # rims 0.24 m radius -> the physics' 0.33 m
static var _part_cache := {}  # path -> [ArrayMesh, Transform3D]

func build() -> void:
	_make_materials()
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var bi: int = def.get("body", 1)
	# centre the model's axles on the physics' axles (kit 1's axles sit 0.14 m
	# further back in its file than kits 2 and 3)
	var dz := -0.0976 - (0.14 * CC96_SCALE if bi == 1 else 0.0)
	var to_car := Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO).scaled_local(Vector3.ONE * CC96_SCALE)
	to_car.origin = Vector3(0, 0, dz)
	# ---- body shell (named Shell so dents work on it)
	var part = _part(CC96_DIR + "Body/CC96_Body_%d.fbx" % bi)
	if part == null:
		push_warning("car model missing: " + CC96_DIR + "Body/CC96_Body_%d.fbx" % bi)
		return
	# baked into real car-space metres: the file stores the mesh at 1/100 scale
	# with a x100 node scale, and the dent shader works in the mesh's own units -
	# a small dent became 100x too big and threw the whole body out of sight
	var shell_mesh := _bake(part[0], to_car * (part[1] as Transform3D))
	_setup_materials(shell_mesh)
	if def.get("spoiler", false):
		var sp = _part(CC96_DIR + "Spoiler/CC96_Spoiler.fbx")
		if sp != null:
			# the spoiler file is placed at its own origin: put it on the boot lid.
			# It's merged into the shell (surface "spoiler") so it dents with the
			# body and can be torn off like the 350Z's wing.
			var rear_x := -1.55 if bi != 1 else -1.69
			var sp_mesh := _bake(sp[0], to_car * Transform3D(Basis(), Vector3(rear_x, 0.56, 0)) * (sp[1] as Transform3D))
			for i in sp_mesh.get_surface_count():
				shell_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sp_mesh.surface_get_arrays(i))
				var si := shell_mesh.get_surface_count() - 1
				shell_mesh.surface_set_material(si, sp_mesh.surface_get_material(i))
				shell_mesh.surface_set_name(si, "spoiler")
	var shell_mi := MeshInstance3D.new()
	shell_mi.name = "Shell"
	shell_mi.mesh = shell_mesh
	body.add_child(shell_mi)
	# ---- a simple cabin so the inside isn't empty (seats, dash, floor)
	driver_eye = Vector3(-0.4, 0.86, 0.2)
	var mb := MB.new()
	mb.box("carpet", Transform3D(Basis(), Vector3(0, 0.2, 0.1)), Vector3(1.3, 0.02, 1.6))
	mb.box("interior", Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(0, 0.58, -0.62)), Vector3(1.4, 0.16, 0.4))
	for sx in [-0.4, 0.4]:
		mb.box("leather", Transform3D(Basis(), Vector3(float(sx), 0.3, 0.3)), Vector3(0.46, 0.1, 0.48))
		mb.box("leather", Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(float(sx), 0.6, 0.58)), Vector3(0.46, 0.6, 0.1))
		mb.box("accent", Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(float(sx), 0.6, 0.525)), Vector3(0.2, 0.46, 0.01))
	mb.box("interior", Transform3D(Basis(), Vector3(0, 0.33, 0.05)), Vector3(0.22, 0.24, 1.0))
	var cab := MeshInstance3D.new()
	cab.mesh = mb.build(mats)
	body.add_child(cab)
	# ---- steering wheel (the same one as the 350Z, moved for this cabin)
	_build_steering_wheel()
	var col: Node3D = steering_wheel.get_parent()
	col.position = Vector3(driver_eye.x, 0.66, driver_eye.z - 0.42)
	col.rotation = Vector3(-0.3, 0, 0)
	dash_label = Label3D.new()
	dash_label.font_size = 48
	dash_label.pixel_size = 0.0007
	dash_label.modulate = Color(1.0, 0.6, 0.2)
	dash_label.outline_size = 0
	dash_label.shaded = false
	dash_label.position = Vector3(driver_eye.x, 0.72, driver_eye.z - 0.62)
	dash_label.rotation = Vector3(-0.35, 0, 0)
	body.add_child(dash_label)
	# ---- headlights at the model's headlights
	for side in [1.0, -1.0]:
		var sl := SpotLight3D.new()
		sl.position = to_car * Vector3(1.5, 0.3, 0.45 * side)
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
	_build_rims(int(def.get("rims", 1)))

# the model's own materials, made to work with the game: paint skins, glowing
# lights, see-through glass, and drawn from both sides (no interior faces)
func _setup_materials(m: ArrayMesh) -> void:
	for i in m.get_surface_count():
		var src = m.surface_get_material(i)
		var mat: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		var n := String(mat.resource_name)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		match n:
			"Car":
				mat.albedo_color = paint_color
				mat.metallic = 0.45
				mat.roughness = 0.32
				mat.clearcoat_enabled = true
				mat.clearcoat = 1.0
				mat.clearcoat_roughness = 0.06
				mats["paint"] = mat
			"Glass":
				mat.albedo_color = Color(0.02, 0.025, 0.03, 0.55)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.metallic = 0.4
				mat.roughness = 0.04
			"headlights", "headlights2":
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.95, 0.85)
				mat.emission_energy_multiplier = 0.4
				if n == "headlights":
					mats["projector"] = mat
			"rear lights":
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.1, 0.05)
				mat.emission_energy_multiplier = 0.35
				tail_mat = mat
			"Chrome", "Car_Det2", "Car_Det3":
				mat.metallic = 0.9
				mat.roughness = 0.2
			_:
				mat.roughness = 0.5
		m.surface_set_material(i, mat)

# wheels in the same places and with the same nodes as the 350Z's, so steering,
# spin, suspension travel and wheel damage all work the same
func _build_rims(ri: int) -> void:
	var part = _part(CC96_DIR + "Rims/Rims%d_R.fbx" % ri)
	if part == null:
		return
	var rim_mesh: ArrayMesh = part[0]
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
		mount.basis = Basis(Vector3.UP, PI if left else 0.0) * Basis(Vector3.FORWARD, PI / 2)
		pivot.add_child(mount)
		var spin := Node3D.new()
		mount.add_child(spin)
		var mi := MeshInstance3D.new()
		mi.mesh = rim_mesh
		# the file's axle runs along Z with the face towards +Z: turn it onto
		# the spin node's Y axis (outer face +Y, like the 350Z's wheels)
		mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3.ZERO).scaled_local(Vector3.ONE * CC96_WHEEL_K) * (part[1] as Transform3D)
		spin.add_child(mi)
		wheels.append({"pivot": pivot, "spin": spin, "left": left, "front": front})

# ---- damage: the full crumple frame, loose parts and breaking glass of
# car_damage.gd (car_model.gd's set_damage_enabled), with this model's own
# parts. The shell's surfaces are named after the file's materials.
var damage_k := 1.35   # lighter, softer car than the 350Z: crumples deeper, loses parts sooner

func damage_classify(key: String, c: Vector3, n: Vector3) -> String:
	var ax: float = abs(c.x)
	match key:
		"Glass":
			if abs(n.x) > 0.55:
				return "win_left" if c.x < 0.0 else "win_right"
			return "win_front" if c.z < 0.4 else "win_rear"
		"headlights":
			return "headlight_left" if c.x < 0.0 else "headlight_right"
		"rear lights":
			return "taillight_left" if c.x < 0.0 else "taillight_right"
		"spoiler":
			return "wing"
		"Hood", "Hood2", "Chrome":
			return "bonnet"
		"exhaust":
			return "bumper_rear"
	# painted body and trim, by where they are on the car
	if c.z < -1.88 and c.y < 0.5:
		return "bumper_front"
	if c.z > 1.98 and c.y < 0.55:
		return "bumper_rear"
	if c.z > -2.0 and c.z < -0.95 and ax > 0.55 and abs(n.x) > 0.4 and c.y > 0.18 and c.y < 0.66:
		return "fender_left" if c.x < 0.0 else "fender_right"
	if c.z > -0.95 and c.z < 0.75 and c.y > 0.15 and c.y < 0.66 and ax > 0.6 and abs(n.x) > 0.3:
		return "door_left" if c.x < 0.0 else "door_right"
	return "body"

# hinge point, hinge axis, opening sign, kind (as car_damage.gd PART_DEF)
const CC96_PARTS := {
	"door_left": [Vector3(-0.88, 0.42, -0.92), Vector3.UP, -1.0, "door"],
	"door_right": [Vector3(0.88, 0.42, -0.92), Vector3.UP, 1.0, "door"],
	"bonnet": [Vector3(0.0, 0.66, -0.56), Vector3.RIGHT, 1.0, "bonnet"],
	"bumper_front": [Vector3(0.75, 0.25, -2.05), Vector3.BACK, 1.0, "droop"],
	"bumper_rear": [Vector3(-0.75, 0.3, 2.15), Vector3.BACK, -1.0, "droop"],
	"wing": [Vector3(0.5, 0.75, 1.98), Vector3.BACK, 1.0, "droop"],
	"fender_left": [Vector3(-0.85, 0.4, -0.95), Vector3.UP, 1.0, "fender"],
	"fender_right": [Vector3(0.85, 0.4, -0.95), Vector3.UP, -1.0, "fender"],
	"headlight_left": [Vector3(-0.5, 0.39, -2.07), Vector3.UP, 1.0, "loose"],
	"headlight_right": [Vector3(0.5, 0.39, -2.07), Vector3.UP, 1.0, "loose"],
	"taillight_left": [Vector3(-0.4, 0.36, 2.2), Vector3.UP, 1.0, "loose"],
	"taillight_right": [Vector3(0.4, 0.36, 2.2), Vector3.UP, 1.0, "loose"],
}

func damage_part_defs() -> Dictionary:
	return CC96_PARTS

# a copy of mesh m with transform xf applied to its vertices, normals and tangents
static func _bake(m: ArrayMesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	var nb := xf.basis.inverse().transposed()
	for i in m.get_surface_count():
		var arr := m.surface_get_arrays(i)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in v.size():
			v[k] = xf * v[k]
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for k in n.size():
				n[k] = (nb * n[k]).normalized()
			arr[Mesh.ARRAY_NORMAL] = n
		if arr[Mesh.ARRAY_TANGENT] != null:
			var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for k in range(0, t.size(), 4):
				var tv := (xf.basis * Vector3(t[k], t[k + 1], t[k + 2])).normalized()
				t[k] = tv.x
				t[k + 1] = tv.y
				t[k + 2] = tv.z
			arr[Mesh.ARRAY_TANGENT] = t
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(i, m.surface_get_material(i))
		out.surface_set_name(i, m.surface_get_name(i))
	return out

# load a model file once (FBX parts come in as importer meshes)
static func _part(path: String):
	if _part_cache.has(path):
		return _part_cache[path]
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(path, st) != OK:
		return null
	var scene: Node = doc.generate_scene(st)
	var found = _find_mesh(scene, Transform3D())
	scene.free()
	if found == null:
		return null
	_part_cache[path] = found
	return found

static func _find_mesh(n: Node, xf: Transform3D):
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is ImporterMeshInstance3D and (n as ImporterMeshInstance3D).mesh:
		return [(n as ImporterMeshInstance3D).mesh.get_mesh(), t]
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return [(n as MeshInstance3D).mesh, t]
	for c in n.get_children():
		var r = _find_mesh(c, t)
		if r != null:
			return r
	return null

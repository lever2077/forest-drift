# A VR glove: ONE skinned mesh over a small skeleton (palm, three bones per
# finger, two for the thumb), so the fingers bend smoothly at the knuckles like
# a glove on a real hand instead of separate pieces.
#
# Built with the fingers along -Z and the palm facing -Y. GRIP_XF turns it on
# its side to match how you hold a controller (OpenXR grip pose: palm facing
# inwards, thumb on top, fingers pointing forward).
extends Node3D

var left := false
var skel: Skeleton3D
var finger_bones: Array = []   # [[b0, b1, b2], ...] index finger first
var thumb_bones: Array = []    # [base, tip]
var thumb_rest: Array = []     # rest rotations of the thumb bones
var curl := 0.0
var grip_xf := Transform3D()   # hand model -> controller grip pose

const GLOVE := Color(0.025, 0.025, 0.028)   # black glove
const BAND := GLOVE
const RING := 16               # vertices around each ring of the tubes (smooth, rounded)

var _st: SurfaceTool
var _nv := 0

func build(p_left: bool) -> void:
	left = p_left
	top_level = true
	var s := 1.0 if left else -1.0   # thumb side (+X for the left hand)
	# palm facing inwards: roll the flat hand 90 degrees onto its side, and
	# shift it so the curled fingers wrap round the controller's handle
	var roll := Basis(Vector3(0, 0, 1), PI / 2 * s)
	grip_xf = Transform3D(roll, roll * Vector3(0, 0.032, 0.02))
	# ---- skeleton
	skel = Skeleton3D.new()
	add_child(skel)
	var root := _bone("palm", -1, Transform3D())
	var xs := [0.03, 0.01, -0.01, -0.03]
	var lens := [1.0, 1.1, 1.02, 0.82]
	var seg := [0.042, 0.027, 0.022]
	for i in 4:
		var chain := []
		var parent := root
		var t := Transform3D(Basis(), Vector3(float(xs[i]) * s, 0, 0))
		for k in 3:
			var b := _bone("f%d_%d" % [i, k], parent, t)
			chain.append(b)
			parent = b
			t = Transform3D(Basis(), Vector3(0, 0, -float(seg[k]) * float(lens[i])))
		finger_bones.append(chain)
	var t0 := _bone("thumb0", root, Transform3D(Basis(Vector3.UP, 0.75 * s), Vector3(0.045 * s, -0.006, 0.055)))
	var t1 := _bone("thumb1", t0, Transform3D(Basis(), Vector3(0, 0, -0.04)))
	thumb_bones = [t0, t1]
	thumb_rest = [skel.get_bone_rest(t0).basis.get_rotation_quaternion(), Quaternion()]
	skel.reset_bone_poses()
	# ---- one mesh: palm + cuff tube, five finger tubes, all skinned
	_st = SurfaceTool.new()
	_nv = 0
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# palm and cuff: wide and flat at the knuckles, round at the wrist
	# a full, rounded hand: round wrist cut off flat, a thick palm that swells
	# towards the knuckles, the back of the hand slightly domed
	var palm_rings := [
		[0.17, 0.034, 0.03, GLOVE], [0.14, 0.033, 0.029, GLOVE],
		[0.11, 0.036, 0.026, GLOVE], [0.085, 0.043, 0.026, GLOVE],
		[0.055, 0.048, 0.025, GLOVE], [0.025, 0.05, 0.023, GLOVE],
		[0.004, 0.049, 0.02, GLOVE], [-0.008, 0.043, 0.016, GLOVE],
	]
	var pts := []
	for r in palm_rings:
		pts.append({"c": Vector3(0, 0, r[0]), "rx": r[1], "ry": r[2], "w": [[root, 1.0]], "col": r[3]})
	_tube(pts, Vector3.UP, true, true, 0.05)   # flat wrist end
	# fingers
	for i in 4:
		var chain: Array = finger_bones[i]
		var x: float = float(xs[i]) * s
		var L := []
		for k in 3:
			L.append(float(seg[k]) * float(lens[i]))
		var z1: float = -L[0]
		var z2: float = z1 - L[1]
		var z3: float = z2 - L[2]
		var f := []
		# thick, soft fingers that taper to rounded tips and swell a little at
		# the joints, starting inside the palm so they blend into it
		for e in [[0.02, 0.0118, [[root, 1.0]]], [0.0, 0.0115, [[root, 0.5], [chain[0], 0.5]]],
				[z1 * 0.5, 0.0106, [[chain[0], 1.0]]], [z1, 0.0108, [[chain[0], 0.5], [chain[1], 0.5]]],
				[z1 + (z2 - z1) * 0.5, 0.0099, [[chain[1], 1.0]]], [z2, 0.0100, [[chain[1], 0.5], [chain[2], 0.5]]],
				[z2 + (z3 - z2) * 0.6, 0.0092, [[chain[2], 1.0]]], [z3, 0.0084, [[chain[2], 1.0]]]]:
			f.append({"c": Vector3(x, 0.002, e[0]), "rx": e[1], "ry": e[1] * 0.88, "w": e[2], "col": GLOVE})
		_tube(f, Vector3.UP, true, true)
	# thumb, along its own bones
	var g0 := skel.get_bone_global_rest(t0)
	var g1 := skel.get_bone_global_rest(t1)
	var th := []
	for e in [[g0, 0.03, 0.017, [[root, 1.0]]], [g0, 0.012, 0.015, [[root, 0.6], [t0, 0.4]]],
			[g0, -0.008, 0.0135, [[t0, 1.0]]], [g1, 0.0, 0.0125, [[t0, 0.5], [t1, 0.5]]],
			[g1, -0.017, 0.0115, [[t1, 1.0]]], [g1, -0.031, 0.0102, [[t1, 1.0]]]]:
		var gx: Transform3D = e[0]
		th.append({"c": gx * Vector3(0, 0, e[1]), "rx": e[2], "ry": e[2] * 0.9, "w": e[3], "col": GLOVE})
	_tube(th, Vector3.UP, true, true)
	_st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = _st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45            # soft sheen like a leather glove
	mat.rim_enabled = true          # keeps the black shape readable in shade
	mat.rim = 0.25
	mat.rim_tint = 0.3
	mi.material_override = mat
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skel.create_skin_from_rest_transforms()
	set_curl(0.0)

func _bone(bname: String, parent: int, rest: Transform3D) -> int:
	var b := skel.get_bone_count()
	skel.add_bone(bname)
	if parent >= 0:
		skel.set_bone_parent(b, parent)
	skel.set_bone_rest(b, rest)
	return b

# a closed tube through rings {"c" centre, "rx"/"ry" radii, "w" [[bone, weight]], "col"}
func _tube(rings: Array, up_hint: Vector3, cap0: bool, cap1: bool, cap0_depth := -1.0) -> void:
	var n := rings.size()
	var first := _nv
	for i in n:
		var c: Vector3 = rings[i]["c"]
		var a: Vector3 = rings[max(i - 1, 0)]["c"]
		var b: Vector3 = rings[min(i + 1, n - 1)]["c"]
		var f := (b - a).normalized()
		var r := up_hint.cross(f).normalized()
		var u := f.cross(r)
		for k in RING:
			var ang := TAU * k / RING
			_vert(c + r * cos(ang) * float(rings[i]["rx"]) + u * sin(ang) * float(rings[i]["ry"]), rings[i]["w"], rings[i]["col"])
	for i in n - 1:
		for k in RING:
			var a0 := first + i * RING + k
			var a1 := first + i * RING + (k + 1) % RING
			var b0 := a0 + RING
			var b1 := a1 + RING
			_st.add_index(a0)
			_st.add_index(b0)
			_st.add_index(a1)
			_st.add_index(a1)
			_st.add_index(b0)
			_st.add_index(b1)
	# rounded ends
	for e in [[cap0, 0, -1.0], [cap1, n - 1, 1.0]]:
		if not e[0]:
			continue
		var i: int = e[1]
		var c: Vector3 = rings[i]["c"]
		var other: Vector3 = rings[i - 1 if i > 0 else 1]["c"]
		var out := (c - other).normalized()
		var tip := _nv
		var depth: float = min(float(rings[i]["rx"]), float(rings[i]["ry"])) * 0.9
		if e[2] < 0.0 and cap0_depth >= 0.0:
			depth *= cap0_depth   # a flat end (the cut-off wrist)
		_vert(c + out * depth, rings[i]["w"], rings[i]["col"])
		for k in RING:
			var a0 := first + i * RING + k
			var a1 := first + i * RING + (k + 1) % RING
			if e[2] > 0.0:
				_st.add_index(a0)
				_st.add_index(tip)
				_st.add_index(a1)
			else:
				_st.add_index(a1)
				_st.add_index(tip)
				_st.add_index(a0)

func _vert(p: Vector3, w: Array, col: Color) -> void:
	var bones := PackedInt32Array([0, 0, 0, 0])
	var wts := PackedFloat32Array([0, 0, 0, 0])
	for j in min(w.size(), 4):
		bones[j] = int(w[j][0])
		wts[j] = float(w[j][1])
	_st.set_color(col)
	_st.set_bones(bones)
	_st.set_weights(wts)
	_st.add_vertex(p)
	_nv += 1

# grip 0..1 bends the middle, ring and little fingers and the thumb; index
# (trigger) bends the index finger. -1 = follow grip.
func set_curl(grip: float, index := -1.0) -> void:
	curl = grip
	var s := 1.0 if left else -1.0
	for i in finger_bones.size():
		var c := grip if (i > 0 or index < 0.0) else index
		c = 0.22 + c * 0.78     # a relaxed hand is never dead straight
		var spread: float = [0.09, 0.03, -0.03, -0.1][i] * s * (1.0 - c)   # fingers fan out a little when open
		var chain: Array = finger_bones[i]
		for k in chain.size():
			var q := Quaternion(Vector3.RIGHT, -c * [1.25, 1.45, 1.05][k])
			if k == 0:
				q = Quaternion(Vector3.UP, spread) * q
			skel.set_bone_pose_rotation(chain[k], q)
	skel.set_bone_pose_rotation(thumb_bones[0], Quaternion(Basis.from_euler(Vector3(-grip * 0.35, (0.75 - grip * 0.55) * s, 0))))
	skel.set_bone_pose_rotation(thumb_bones[1], Quaternion(Vector3.RIGHT, -grip * 0.7))

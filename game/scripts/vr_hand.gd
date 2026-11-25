# A VR glove that is ONE smooth surface. The hand shape (palm, wrist, fingers,
# thumb) is described as a soft solid - every part melted into the next, like
# clay - and turned into a single seamless mesh (surface nets). Hidden bones
# inside bend it: each vertex follows the bones near it with smooth weights, so
# fingers curl and stretch without any joints or pieces showing.
#
# Built with the fingers along -Z and the palm facing -Y. grip_xf turns it on
# its side to match how you hold a controller (palm in, thumb up).
extends Node3D

var left := false
var skel: Skeleton3D
var finger_bones: Array = []   # [[b0, b1, b2], ...] index finger first
var thumb_bones: Array = []    # [base, tip]
var curl := 0.0
var grip_xf := Transform3D()   # hand model -> controller grip pose

const GLOVE := Color(0.025, 0.025, 0.028)
const XS := [0.034, 0.0115, -0.0115, -0.033]          # finger roots across the knuckles
const SPREAD := [0.13, 0.045, -0.045, -0.15]          # fingers fan out a little
const LENS := [1.0, 1.1, 1.02, 0.82]
const SEG := [0.043, 0.027, 0.022]
const RAD := [0.0098, 0.009, 0.0081]
const CELL := 0.0042                                  # mesh detail (metres)

static var _mesh_cache: ArrayMesh = null              # built once (right hand), mirrored for the left
static var _mesh_cache_l: ArrayMesh = null

func build(p_left: bool) -> void:
	left = p_left
	top_level = true
	var s := 1.0 if left else -1.0
	var roll := Basis(Vector3(0, 0, 1), PI / 2 * s)
	grip_xf = Transform3D(roll, roll * Vector3(0, 0.032, 0.02))
	# ---- skeleton (same layout for both hands, x mirrored)
	skel = Skeleton3D.new()
	add_child(skel)
	var root := _bone("palm", -1, Transform3D())
	for i in 4:
		var chain := []
		var parent := root
		var t := Transform3D(Basis(Vector3.UP, float(SPREAD[i]) * s), Vector3(float(XS[i]) * s, 0, 0))
		for k in 3:
			var b := _bone("f%d_%d" % [i, k], parent, t)
			chain.append(b)
			parent = b
			t = Transform3D(Basis(), Vector3(0, 0, -float(SEG[k]) * float(LENS[i])))
		finger_bones.append(chain)
	var t0 := _bone("thumb0", root, Transform3D(Basis(Vector3.UP, 0.75 * s), Vector3(0.045 * s, -0.006, 0.055)))
	var t1 := _bone("thumb1", t0, Transform3D(Basis(), Vector3(0, 0, -0.04)))
	thumb_bones = [t0, t1]
	skel.reset_bone_poses()
	# ---- the one mesh
	# built once per game launch for the right hand; the left is its mirror image
	if _mesh_cache == null:
		var data := _build_data(-1.0)
		_mesh_cache = _make_mesh(data, false)
		_mesh_cache_l = _make_mesh(data, true)
	var mesh: ArrayMesh = _mesh_cache_l if left else _mesh_cache
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GLOVE
	mat.roughness = 0.45
	mat.rim_enabled = true
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

# ---------------------------------------------------------------- shape
# segments of the hand in the rest pose: [a, b, radius, bone]
var _segs: Array = []
var _thumb_segs: Array = []
var _finger_segs: Array = []   # per finger: [[a, b, r, bone], ...]

func _make_segments(s: float) -> void:
	_finger_segs.clear()
	_thumb_segs.clear()
	for i in 4:
		var fl := []
		var basis := Basis(Vector3.UP, float(SPREAD[i]) * s)
		var p := Vector3(float(XS[i]) * s, 0.0, 0.0)
		var dir := basis * Vector3(0, 0, -1)
		for k in 3:
			var L: float = float(SEG[k]) * float(LENS[i])
			var q := p + dir * (L - (0.006 if k == 2 else 0.0))
			fl.append([p, q, float(RAD[k]), (finger_bones[i] as Array)[k]])
			p = p + dir * L
		_finger_segs.append(fl)
	var g0 := Transform3D(Basis(Vector3.UP, 0.75 * s), Vector3(0.045 * s, -0.006, 0.055))
	var g1 := g0 * Transform3D(Basis(), Vector3(0, 0, -0.04))
	_thumb_segs = [[g0 * Vector3(0, 0, 0.012), g0.origin, 0.0145, thumb_bones[0]],
		[g0.origin, g1.origin, 0.0128, thumb_bones[0]],
		[g1.origin, g1 * Vector3(0, 0, -0.026), 0.0112, thumb_bones[1]]]

static func _cap(p: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length() - r

static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)

static func _rbox(p: Vector3, c: Vector3, he: Vector3, r: float) -> float:
	var q := (p - c).abs() - he
	return Vector3(max(q.x, 0.0), max(q.y, 0.0), max(q.z, 0.0)).length() + min(max(q.x, max(q.y, q.z)), 0.0) - r

# signed distance to the hand surface (negative inside)
func _sdf(p: Vector3) -> float:
	# far from the hand: a rough distance is enough (only the sign matters there)
	var rough := _cap(p, Vector3(0, 0, 0.2), Vector3(0, 0, -0.11), 0.075)
	if rough > 0.012:
		return rough
	# palm: a thick rounded slab, domed a little on the back of the hand
	var palm := _rbox(p, Vector3(0, 0.001, 0.046), Vector3(0.036, 0.008, 0.042), 0.009)
	var wrist := _cap(p, Vector3(0, 0, 0.09), Vector3(0, 0, 0.21), 0.03)
	var base := _smin(palm, wrist, 0.022)
	# each finger melts into the palm; neighbouring fingers stay apart
	var d := base
	for fl in _finger_segs:
		var f := 1e9
		for sg in fl:
			f = _smin(f, _cap(p, sg[0], sg[1], sg[2]), 0.003)
		d = min(d, _smin(base, f, 0.012))
	var th := 1e9
	for sg in _thumb_segs:
		th = _smin(th, _cap(p, sg[0], sg[1], sg[2]), 0.004)
	d = min(d, _smin(base, th, 0.016))
	return max(d, p.z - 0.17)   # the wrist is cut off flat

# ---------------------------------------------------------------- mesh
func _build_data(s: float) -> Dictionary:
	_make_segments(s)
	var lo := Vector3(-0.1, -0.045, -0.15)
	var hi := Vector3(0.1, 0.045, 0.185)
	var nx := int((hi.x - lo.x) / CELL) + 1
	var ny := int((hi.y - lo.y) / CELL) + 1
	var nz := int((hi.z - lo.z) / CELL) + 1
	var f := PackedFloat32Array()
	f.resize(nx * ny * nz)
	for k in nz:
		for j in ny:
			for i in nx:
				f[(k * ny + j) * nx + i] = _sdf(lo + Vector3(i, j, k) * CELL)
	# one vertex per cell that the surface passes through
	var cidx := PackedInt32Array()
	cidx.resize((nx - 1) * (ny - 1) * (nz - 1))
	cidx.fill(-1)
	var verts := PackedVector3Array()
	var corners := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	for k in nz - 1:
		for j in ny - 1:
			for i in nx - 1:
				var v := []
				var neg := 0
				for c in corners:
					var val := f[((k + c.z) * ny + j + c.y) * nx + i + c.x]
					v.append(val)
					if val < 0.0:
						neg += 1
				if neg == 0 or neg == 8:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in edges:
					var a: float = v[e[0]]
					var b: float = v[e[1]]
					if (a < 0.0) != (b < 0.0):
						var t := a / (a - b)
						acc += Vector3(corners[e[0]]).lerp(Vector3(corners[e[1]]), t)
						cnt += 1
				cidx[(k * (ny - 1) + j) * (nx - 1) + i] = verts.size()
				verts.append(lo + (Vector3(i, j, k) + acc / cnt) * CELL)
	# one quad per grid edge the surface crosses, joining the four cells around it
	var idx := PackedInt32Array()
	var axes := [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]
	for k in range(1, nz - 1):
		for j in range(1, ny - 1):
			for i in range(1, nx - 1):
				var f0 := f[(k * ny + j) * nx + i]
				for ax in 3:
					var e: Vector3i = axes[ax]
					var f1 := f[((k + e.z) * ny + j + e.y) * nx + i + e.x]
					if (f0 < 0.0) == (f1 < 0.0):
						continue
					var u: Vector3i = axes[(ax + 1) % 3]
					var w: Vector3i = axes[(ax + 2) % 3]
					var cells := [Vector3i(i, j, k) - u - w, Vector3i(i, j, k) - w, Vector3i(i, j, k), Vector3i(i, j, k) - u]
					var q := []
					for c in cells:
						var ci: int = cidx[(c.z * (ny - 1) + c.y) * (nx - 1) + c.x]
						q.append(ci)
					if q.has(-1):
						continue
					# face outwards (from inside to outside along the edge)
					var out := Vector3(e) * (1.0 if f0 < 0.0 else -1.0)
					var n := (verts[q[1]] - verts[q[0]]).cross(verts[q[2]] - verts[q[0]])
					if n.dot(out) > 0.0:
						q.reverse()
					idx.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
	# smooth skin weights from the distance to each bone's part of the hand
	var bone_segs := []   # [a, b, bone]
	var root_x := [0.03, 0.01, -0.01, -0.03, 0.0]
	for rx in root_x:
		bone_segs.append([Vector3(float(rx) * s, 0, 0.008), Vector3(float(rx) * 0.6 * s, 0, 0.2), 0])
	for fl in _finger_segs:
		for sg in fl:
			bone_segs.append([sg[0], sg[1], sg[3]])
	for sg in _thumb_segs:
		bone_segs.append([sg[0], sg[1], sg[3]])
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	bones.resize(verts.size() * 4)
	wts.resize(verts.size() * 4)
	for vi in verts.size():
		var p: Vector3 = verts[vi]
		var best := {}   # bone -> weight
		for bs in bone_segs:
			var dd: float = _cap(p, bs[0], bs[1], 0.0)
			var w := 1.0 / pow(dd + 0.003, 4.0)
			var b: int = bs[2]
			best[b] = max(float(best.get(b, 0.0)), w)
		var keys := best.keys()
		keys.sort_custom(func(a, b): return best[a] > best[b])
		var tot := 0.0
		for n in min(4, keys.size()):
			tot += float(best[keys[n]])
		for n in 4:
			if n < keys.size():
				bones[vi * 4 + n] = int(keys[n])
				wts[vi * 4 + n] = float(best[keys[n]]) / tot
			else:
				bones[vi * 4 + n] = 0
				wts[vi * 4 + n] = 0.0
	return {"verts": verts, "idx": idx, "bones": bones, "wts": wts}

# the skinned mesh from the data; `mirror` flips it left-right for the other hand
static func _make_mesh(data: Dictionary, mirror: bool) -> ArrayMesh:
	var verts: PackedVector3Array = data["verts"]
	var idx: PackedInt32Array = data["idx"]
	var bones: PackedInt32Array = data["bones"]
	var wts: PackedFloat32Array = data["wts"]
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vi in verts.size():
		st.set_bones(bones.slice(vi * 4, vi * 4 + 4))
		st.set_weights(wts.slice(vi * 4, vi * 4 + 4))
		var v: Vector3 = verts[vi]
		st.add_vertex(Vector3(-v.x, v.y, v.z) if mirror else v)
	for t in range(0, idx.size(), 3):
		if mirror:   # mirroring turns the triangles inside out: swap two corners back
			st.add_index(idx[t])
			st.add_index(idx[t + 2])
			st.add_index(idx[t + 1])
		else:
			st.add_index(idx[t])
			st.add_index(idx[t + 1])
			st.add_index(idx[t + 2])
	st.generate_normals()
	return st.commit()

# grip 0..1 bends the middle, ring and little fingers and the thumb; index
# (trigger) bends the index finger. -1 = follow grip.
func set_curl(grip: float, index := -1.0) -> void:
	curl = grip
	var s := 1.0 if left else -1.0
	for i in finger_bones.size():
		var c := grip if (i > 0 or index < 0.0) else index
		c = 0.2 + c * 0.8     # a relaxed hand is never dead straight
		var chain: Array = finger_bones[i]
		for k in chain.size():
			var q := Quaternion(Vector3.RIGHT, -c * [1.2, 1.45, 1.05][k])
			if k == 0:
				q = Quaternion(Vector3.UP, float(SPREAD[i]) * s * (1.0 - c * 0.7)) * q
			skel.set_bone_pose_rotation(chain[k], q)
	skel.set_bone_pose_rotation(thumb_bones[0], Quaternion(Basis.from_euler(Vector3(-grip * 0.35, (0.75 - grip * 0.55) * s, 0))))
	skel.set_bone_pose_rotation(thumb_bones[1], Quaternion(Vector3.RIGHT, -grip * 0.7))

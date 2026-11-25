# VR hand: the gloved hand model from Godot XR Tools (CC0, see
# res://models/hands/CREDITS.txt) - one skinned mesh over a full hand skeleton -
# driven by XR Tools' own hand animations: "Grip 5" is the relaxed open hand,
# "Grip" the closed fist. Grip closes the middle, ring and little fingers and
# the thumb; the trigger closes the index finger (same split XR Tools uses).
#
# The model is made for the controller's "aim" pose; grip_xf puts it there.
extends Node3D

var left := false
var skel: Skeleton3D
var curl := 0.0
var grip_xf := Transform3D()   # hand model -> controller (aim pose)
var fist_local := Vector3.ZERO # middle of the closed fist, in model space (for grabbing)
var _poses := {}               # bone index -> [open rotation, closed rotation, group]

const DIR := "res://models/hands/"
const GLOVE := Color(0.025, 0.025, 0.028)

func build(p_left: bool) -> void:
	left = p_left
	top_level = true
	var sfx := "L" if left else "R"
	# XR Tools' hand scenes sit the model here relative to the aim pose
	grip_xf = Transform3D(Basis(), Vector3(-0.03 if left else 0.03, -0.05, 0.15))
	# ---- model (glTF loaded at runtime)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(DIR + "Hand_Glove_%s.gltf" % sfx, state) != OK:
		push_warning("VR hand model missing: " + DIR + "Hand_Glove_%s.gltf" % sfx)
		return
	var model: Node3D = doc.generate_scene(state)
	add_child(model)
	skel = _find_skeleton(model)
	if skel == null:
		return
	# black glove
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GLOVE
	mat.roughness = 0.45
	mat.rim_enabled = true
	mat.rim = 0.25
	mat.rim_tint = 0.3
	for mi in _meshes(model):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# ---- the two animation poses, read straight from XR Tools' animations
	var side := "left" if left else "right"
	var open_a: Animation = load(DIR + "anims/%s/Grip 5.res" % side)
	var closed_a: Animation = load(DIR + "anims/%s/Grip.res" % side)
	var open_r := _pose_of(open_a)
	var closed_r := _pose_of(closed_a)
	for bname in closed_r.keys():
		var bi := skel.find_bone(bname)
		if bi < 0:
			continue
		var group := 0                               # 0 = stays put (wrist, palm)
		if bname.begins_with("Index"):
			group = 2                                # trigger
		elif bname.begins_with("Middle") or bname.begins_with("Ring") or bname.begins_with("Little") or bname.begins_with("Thumb"):
			group = 1                                # grip
		var o: Quaternion = open_r.get(bname, skel.get_bone_rest(bi).basis.get_rotation_quaternion())
		_poses[bi] = [o, closed_r[bname], group]
	# where the fist closes (between the palm and the middle finger's base)
	var palm := skel.find_bone("Palm_" + sfx)
	var mid := skel.find_bone("Middle_Proximal_" + sfx)
	if palm >= 0 and mid >= 0:
		var to_model := model.transform * skel.transform
		fist_local = to_model * skel.get_bone_global_rest(palm).origin.lerp(skel.get_bone_global_rest(mid).origin, 0.7)
	set_curl(0.0)

# bone name -> rotation at the start of each rotation track
static func _pose_of(a: Animation) -> Dictionary:
	var out := {}
	if a == null:
		return out
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var path := String(a.track_get_path(t))
		var bone := path.get_slice(":", 1)
		if bone != "":
			out[bone] = a.rotation_track_interpolate(t, 0.0)
	return out

static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null

static func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

# grip 0..1 closes the middle, ring and little fingers and the thumb; index
# (trigger) closes the index finger. -1 = follow grip.
func set_curl(grip: float, index := -1.0) -> void:
	curl = grip
	if skel == null:
		return
	var trig := grip if index < 0.0 else index
	for bi in _poses.keys():
		var p: Array = _poses[bi]
		var w := 0.0
		if p[2] == 1:
			w = grip
		elif p[2] == 2:
			w = trig
		skel.set_bone_pose_rotation(bi, (p[0] as Quaternion).slerp(p[1], clampf(w, 0.0, 1.0)))

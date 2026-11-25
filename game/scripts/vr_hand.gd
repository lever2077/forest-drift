# A gloved VR hand built from simple shapes. Fingers point along -Z with the
# palm facing -Y; set_curl() bends every finger joint (grip) and the index
# finger on its own (trigger). The thumb sits on the inside of each hand.
extends Node3D

var left := false
var fingers: Array = []     # [[joint, joint, joint], ...] index first
var thumb: Array = []       # [base, tip]
var curl := 0.0

func build(p_left: bool) -> void:
	left = p_left
	top_level = true
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.09, 0.09, 0.1)
	glove.roughness = 0.75
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(1.0, 0.5, 0.12)
	trim.roughness = 0.5
	var s := 1.0 if left else -1.0   # +X side is the thumb side for the left hand
	# palm: knuckles at z = 0, wrist at z = +0.095
	var palm := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.085, 0.03, 0.095)
	palm.mesh = pm
	palm.material_override = glove
	palm.position = Vector3(0, 0, 0.0475)
	add_child(palm)
	# cuff with an orange band
	var cuff := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.036
	cm.bottom_radius = 0.04
	cm.height = 0.06
	cuff.mesh = cm
	cuff.material_override = glove
	cuff.rotation.x = PI / 2
	cuff.position = Vector3(0, 0, 0.12)
	cuff.scale = Vector3(1.15, 1.0, 0.7)
	add_child(cuff)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.041
	bm.bottom_radius = 0.041
	bm.height = 0.012
	band.mesh = bm
	band.material_override = trim
	band.rotation.x = PI / 2
	band.position = Vector3(0, 0, 0.1)
	band.scale = Vector3(1.15, 1.0, 0.7)
	add_child(band)
	# four fingers, index next to the thumb
	var xs := [0.03, 0.01, -0.01, -0.03]
	var lens := [1.0, 1.1, 1.02, 0.82]
	for i in 4:
		var chain := []
		var parent: Node3D = self
		var pos := Vector3(float(xs[i]) * s, 0, 0)
		for k in 3:
			var seg_len: float = [0.042, 0.027, 0.022][k] * float(lens[i])
			var j := Node3D.new()
			j.position = pos
			parent.add_child(j)
			j.add_child(_capsule(0.0092 - k * 0.0008, seg_len, glove))
			chain.append(j)
			parent = j
			pos = Vector3(0, 0, -seg_len)
		fingers.append(chain)
	# thumb: from the inside of the palm, angled forward and in
	var tb := Node3D.new()
	tb.position = Vector3(0.045 * s, -0.006, 0.055)
	tb.rotation = Vector3(0, 0.75 * s, 0)
	add_child(tb)
	tb.add_child(_capsule(0.011, 0.04, glove))
	var tt := Node3D.new()
	tt.position = Vector3(0, 0, -0.04)
	tb.add_child(tt)
	tt.add_child(_capsule(0.0095, 0.032, glove))
	thumb = [tb, tt]
	set_curl(0.0)

func _capsule(r: float, length: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = length + r * 2.0
	c.radial_segments = 8
	c.rings = 2
	mi.mesh = c
	mi.material_override = m
	mi.rotation.x = PI / 2          # capsule runs along -Z from the joint
	mi.position = Vector3(0, 0, -length * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

# grip 0..1 bends the middle, ring and little fingers and the thumb; index
# (trigger) bends the index finger. -1 = follow grip.
func set_curl(grip: float, index := -1.0) -> void:
	curl = grip
	var s := 1.0 if left else -1.0
	for i in fingers.size():
		var c := grip if (i > 0 or index < 0.0) else index
		var chain: Array = fingers[i]
		for k in chain.size():
			(chain[k] as Node3D).rotation.x = -c * [1.25, 1.45, 1.05][k]
	(thumb[0] as Node3D).rotation = Vector3(-grip * 0.35, (0.75 - grip * 0.55) * s, 0)
	(thumb[1] as Node3D).rotation.x = -grip * 0.7

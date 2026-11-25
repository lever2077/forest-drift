# A flat screen floating in the VR world. 2D UI (the normal menu / HUD, a
# CanvasLayer) is drawn into its SubViewport and shown on a quad; controller
# lasers that hit the quad are turned into mouse events for that UI, so every
# button, slider, tab and dropdown works exactly like on the desktop.
extends Node3D

var vp: SubViewport
var quad: MeshInstance3D
var cursor: MeshInstance3D
var size_m := Vector2.ONE       # quad size in metres
var px := Vector2i(1280, 720)   # UI resolution
var mat: StandardMaterial3D
var _down := false
var _last := Vector2(-1, -1)

func setup(p_px: Vector2i, width_m: float, transparent: bool, interactive := true, on_top := false) -> void:
	px = p_px
	size_m = Vector2(width_m, width_m * float(px.y) / float(px.x))
	vp = SubViewport.new()
	vp.size = px
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.gui_disable_input = not interactive
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size_m
	quad.mesh = qm
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = vp.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.set("disable_fog", true)
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if on_top:   # drawn over everything (the HUD over the car's pillars and dash)
		mat.no_depth_test = true
		mat.render_priority = 10
	quad.material_override = mat
	add_child(quad)
	cursor = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.008
	sm.height = 0.016
	cursor.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.0, 0.6, 0.2)
	cm.no_depth_test = true
	cursor.material_override = cm
	cursor.visible = false
	add_child(cursor)

# put a CanvasLayer / Control into the panel
func add_ui(n: Node) -> void:
	vp.add_child(n)

# where a ray hits the panel: {"pos": UI pixel, "dist": metres} or {}
func hit(origin: Vector3, dir: Vector3) -> Dictionary:
	if not visible:
		return {}
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir)
	if absf(d.z) < 1e-5:
		return {}
	var t := -o.z / d.z
	if t <= 0.0:
		return {}
	var p := o + d * t
	var uv := Vector2(p.x / size_m.x + 0.5, 0.5 - p.y / size_m.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return {}
	return {"pos": uv * Vector2(px), "dist": t * dir.length(), "local": p}

# move the UI's mouse to `pos` and press / release the left button
func point(h: Dictionary, pressed: bool) -> void:
	var pos: Vector2 = h["pos"]
	cursor.visible = true
	cursor.position = h["local"] + Vector3(0, 0, 0.004)
	if pos.distance_to(_last) > 0.5:
		var mm := InputEventMouseMotion.new()
		mm.position = pos
		mm.global_position = pos
		mm.relative = pos - _last if _last.x >= 0.0 else Vector2.ZERO
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _down else 0
		vp.push_input(mm, true)
		_last = pos
	if pressed != _down:
		_down = pressed
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = pos
		mb.global_position = pos
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		vp.push_input(mb, true)

# thumbstick up/down scrolls lists
func scroll(amount: float) -> void:
	if _last.x < 0.0 or absf(amount) < 0.01:
		return
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_WHEEL_UP if amount > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
	mb.factor = absf(amount)
	mb.position = _last
	mb.global_position = _last
	mb.pressed = true
	vp.push_input(mb, true)
	var up := mb.duplicate()
	up.pressed = false
	vp.push_input(up, true)

# the laser left the panel: let go of anything held, hide the cursor
func leave() -> void:
	cursor.visible = false
	if _down and _last.x >= 0.0:
		point({"pos": _last, "local": cursor.position}, false)
	_last = Vector2(-1, -1)

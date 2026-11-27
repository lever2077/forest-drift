# Biome effects: particles drifting around the camera.
#   "leaves" (Autumn forest): orange, red and gold leaves tumbling down
#   "petals" (Cherry blossom): pink petals fluttering down
#   "ash"    (Volcanic): grey ash floating about, with glowing embers rising
# Settings > Graphics > Biome effects scales how many there are, from none up
# to the normal amount (set_level 0..1).
extends Node3D

var kind := ""
var systems: Array[GPUParticles3D] = []
var level := 1.0

func setup(biome: Dictionary, p_level: float) -> void:
	kind = String(biome.get("fx", ""))
	match kind:
		"leaves":
			systems.append(_make(500, 9.0, _leaf_tex(), Vector2(0.3, 0.3), -0.9, 1.6,
				[Color(0.95, 0.45, 0.08), Color(0.8, 0.2, 0.05), Color(0.95, 0.7, 0.15), Color(0.6, 0.3, 0.08)], 0.0))
		"petals":
			systems.append(_make(900, 9.0, _petal_tex(), Vector2(0.13, 0.1), -0.55, 1.2,
				[Color(1.0, 0.72, 0.85), Color(1.0, 0.82, 0.9), Color(0.95, 0.6, 0.78)], 0.0))
		"ash":
			systems.append(_make(1400, 10.0, _dot_tex(), Vector2(0.05, 0.05), -0.12, 0.5,
				[Color(0.45, 0.44, 0.43), Color(0.3, 0.3, 0.3), Color(0.6, 0.58, 0.56)], 0.0))
			var embers := _make(220, 4.0, _dot_tex(), Vector2(0.06, 0.06), 0.35, 0.6,
				[Color(1.0, 0.5, 0.1), Color(1.0, 0.3, 0.05)], 3.0)
			systems.append(embers)
	set_level(p_level)

func set_level(v: float) -> void:
	level = clampf(v, 0.0, 1.0)
	for s in systems:
		s.amount_ratio = max(level, 0.001)
		s.emitting = level > 0.001

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position

# one particle system in a box around the camera: fall speed (negative = down,
# positive = rising embers), how much the wind tosses them around, a few colours
# picked at random, and glow (emission) for embers
func _make(amount: int, life: float, tex: Texture2D, size: Vector2, fall: float, toss: float, colors: Array, glow: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life   # already full when the map appears
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 7, 30)
	pm.direction = Vector3(0.6, -1.0 if fall < 0.0 else 1.0, 0.25).normalized()
	pm.spread = 35.0
	pm.initial_velocity_min = abs(fall) * 0.6
	pm.initial_velocity_max = abs(fall) * 1.3
	pm.gravity = Vector3(0.35 * toss, fall * 0.4, 0.15 * toss)
	pm.damping_min = 0.2
	pm.damping_max = 0.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = toss
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_noise_speed = Vector3(0.4, 0.1, 0.3)
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -160.0
	pm.angular_velocity_max = 160.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.remove_point(1)
	g.set_color(0, colors[0])
	for i in range(1, colors.size()):
		g.add_point(float(i) / (colors.size() - 1), colors[i])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	# fade in and out at the ends of their life
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.1, Color(1, 1, 1, 1))
	fade.add_point(0.85, Color(1, 1, 1, 1))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.roughness = 0.9
	if glow > 0.0:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = glow
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p

# ---- small textures drawn in code
func _img_tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _leaf_tex() -> ImageTexture:
	var S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var u := (x + 0.5) / S * 2.0 - 1.0
			var v := (y + 0.5) / S * 2.0 - 1.0
			# pointed oval leaf with a darker midrib and a little stem
			var w: float = 0.55 * (1.0 - v * v)
			var a: float = 1.0 if abs(u) < w and abs(v) < 0.92 else 0.0
			if abs(u) < 0.05 and v > 0.7:
				a = 1.0
			var shade: float = 0.75 if abs(u) < 0.06 else 1.0 - 0.25 * abs(u)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return _img_tex(img)

func _petal_tex() -> ImageTexture:
	var S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var u := (x + 0.5) / S * 2.0 - 1.0
			var v := (y + 0.5) / S * 2.0 - 1.0
			# rounded petal with a notch at the tip
			var r := Vector2(u, v * 1.25).length()
			var a := clampf((1.0 - r) * 6.0, 0.0, 1.0)
			if v < -0.55 and abs(u) < 0.15:
				a = 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return _img_tex(img)

func _dot_tex() -> ImageTexture:
	var S := 16
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x - S * 0.5 + 0.5, y - S * 0.5 + 0.5).length() / (S * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	return _img_tex(img)

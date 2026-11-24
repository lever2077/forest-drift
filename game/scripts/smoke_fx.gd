# Smoke effects: tyre smoke when drifting, steam and dark smoke from a damaged
# engine. Billowing lit cloud puffs (generated noise texture) that swirl with
# turbulence, swell, linger in the air and take the sun's light.
extends RefCounted

static var _cloud: ImageTexture

# a soft, lumpy cloud puff: fractal noise inside a round falloff
static func cloud_texture() -> ImageTexture:
	if _cloud:
		return _cloud
	var S := 128
	var img := Image.create(S, S, true, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.seed = 17
	nz.frequency = 0.045
	nz.fractal_octaves = 4
	for y in S:
		for x in S:
			var u := (x + 0.5) / S * 2.0 - 1.0
			var v := (y + 0.5) / S * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var n := nz.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - r) * 1.6 - (1.0 - n) * 0.9, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			# a touch darker at the edges, so the puffs read as round volumes
			var b := 0.78 + 0.22 * clampf(1.0 - r, 0.0, 1.0) + (n - 0.5) * 0.15
			img.set_pixel(x, y, Color(b, b, b, a))
	img.generate_mipmaps()
	_cloud = ImageTexture.create_from_image(img)
	return _cloud

static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 10.0
	for p in points:
		c.add_point(p)
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

static func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for e in cols:
		g.add_point(e[0], e[1])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

static func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX   # lit by the sun and sky
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = cloud_texture()
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.proximity_fade_enabled = true       # soft where puffs meet the road / car
	m.proximity_fade_distance = 0.8
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.4    # no giant puff smeared over the camera
	m.distance_fade_max_distance = 2.2
	return m

# tyre smoke from one rear wheel's contact patch
static func tyre_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	# fewer, slightly more solid puffs: big see-through quads piled on top of
	# each other are what costs frame rate
	p.amount = 110
	p.lifetime = 3.4
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.14, 0.04, 0.22)
	pm.direction = Vector3(0, 0.3, 1)
	pm.spread = 65.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, 0.22, 0)        # warm smoke drifts up slowly
	pm.damping_min = 0.9
	pm.damping_max = 1.8
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 3.5
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.1
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -22.0
	pm.angular_velocity_max = 22.0
	pm.scale_min = 0.9
	pm.scale_max = 1.5
	pm.scale_curve = _curve([Vector2(0, 0.4), Vector2(0.25, 1.6), Vector2(1, 3.4)])
	pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.05, Color(0.96, 0.96, 0.97, 0.72)],
		[0.45, Color(0.92, 0.92, 0.94, 0.4)], [1.0, Color(0.9, 0.9, 0.92, 0.0)]])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	q.material = _material()
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-50, -10, -50), Vector3(100, 40, 100))
	return p

# engine smoke: white steam from the radiator, or dark smoke from a wrecked engine
static func engine_smoke(dark: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60 if dark else 40
	p.lifetime = 4.0 if dark else 2.2
	p.local_coords = false
	p.emitting = false
	p.position = Vector3(0, 0.78, -1.35)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.45, 0.04, 0.3)
	pm.direction = Vector3(0, 1, 0.15)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.7 if dark else 1.2
	pm.initial_velocity_max = 1.6 if dark else 2.6
	pm.gravity = Vector3(0, 0.5 if dark else 0.9, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.8
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -18.0
	pm.angular_velocity_max = 18.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	if dark:
		pm.scale_curve = _curve([Vector2(0, 0.4), Vector2(0.3, 1.5), Vector2(1, 3.2)])
		pm.color_ramp = _ramp([[0.0, Color(0.25, 0.24, 0.23, 0.0)], [0.06, Color(0.16, 0.15, 0.15, 0.8)],
			[0.5, Color(0.22, 0.22, 0.22, 0.45)], [1.0, Color(0.35, 0.35, 0.36, 0.0)]])
	else:
		pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.3, 1.3), Vector2(1, 3.0)])
		pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(0.97, 0.97, 0.98, 0.55)],
			[1.0, Color(0.95, 0.95, 0.97, 0.0)]])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.material = _material()
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 50, 80))
	return p

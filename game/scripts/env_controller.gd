# Time of day + weather. Drives the sun/moon, sky, clouds, fog, road wetness,
# snow on the ground and rain/snow particles. Weather changes blend smoothly,
# and both time and weather can cycle automatically.
extends Node3D

signal time_changed(hour: float)
signal weather_changed(index: int)

const Gfx = preload("res://scripts/gfx.gd")
const WEATHERS := ["Clear", "Hazy", "Cloudy", "Foggy", "Rain", "Snow"]
# cover, dark, fog, vfog, sun, wet, snow_ground, rain, snowfall
const PRESETS := [
	[0.12, 0.0, 0.0014, 0.0012, 1.0, 0.0, 0.0, 0.0, 0.0],   # Clear
	[0.6, 0.05, 0.0032, 0.0045, 1.0, 0.0, 0.0, 0.0, 0.0],   # Hazy (original look)
	[0.95, 0.4, 0.0028, 0.0025, 0.38, 0.0, 0.0, 0.0, 0.0],  # Cloudy
	[0.7, 0.25, 0.013, 0.02, 0.45, 0.15, 0.0, 0.0, 0.0],    # Foggy
	[0.95, 0.32, 0.0035, 0.0028, 0.32, 1.0, 0.0, 1.0, 0.0], # Rain (overcast but clear to see through)
	[0.95, 0.3, 0.0065, 0.008, 0.35, 0.0, 1.0, 0.0, 1.0],   # Snow
]

var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var psm: ProceduralSkyMaterial
var track
var vr := false

var time_h := 17.5
var cycle_time := false
var day_minutes := 10.0          # real minutes for a full 24 h
var weather := 1
var cycle_weather := false
var weather_minutes := 3.0
var weather_timer := 0.0
var cur := []
var dark := false                # true when headlights are needed

var rain: GPUParticles3D
var snowfall: GPUParticles3D

func setup(p_env: Environment, p_sun: DirectionalLight3D, p_psm: ProceduralSkyMaterial, p_track, p_vr: bool) -> void:
	env = p_env
	sun = p_sun
	psm = p_psm
	track = p_track
	vr = p_vr
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.shadow_enabled = false
	moon.light_energy = 0.0
	add_child(moon)
	cur = (PRESETS[weather] as Array).duplicate()
	_build_precip()
	_apply()

func set_time(h: float) -> void:
	time_h = fposmod(h, 24.0)
	_apply()

func set_weather(i: int, instant := false) -> void:
	weather = clampi(i, 0, WEATHERS.size() - 1)
	weather_timer = 0.0
	if instant:
		cur = (PRESETS[weather] as Array).duplicate()
	weather_changed.emit(weather)

func _process(delta: float) -> void:
	if cycle_time:
		time_h = fposmod(time_h + delta * 24.0 / (day_minutes * 60.0), 24.0)
		time_changed.emit(time_h)
	if cycle_weather:
		weather_timer += delta
		if weather_timer > weather_minutes * 60.0:
			set_weather((weather + 1) % WEATHERS.size())
	# blend towards the target weather over a few seconds
	var tgt: Array = PRESETS[weather]
	var k := 1.0 - exp(-delta * 0.6)
	for i in cur.size():
		cur[i] = lerpf(cur[i], tgt[i], k)
	_apply()
	# precipitation follows the active camera
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := cam.global_position
		rain.global_position = p + Vector3(0, 10, 0)
		snowfall.global_position = p + Vector3(0, 8, 0)

static func _sm(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _apply() -> void:
	var cover: float = cur[0]
	var dk: float = cur[1]
	var elev := sin((time_h - 6.0) / 12.0 * PI) * 62.0      # sun elevation in degrees
	var az := deg_to_rad(-140.0) + (time_h - 17.5) / 12.0 * PI
	var day := _sm(-6.0, 10.0, elev)          # 0 night .. 1 day (includes twilight)
	var lit := _sm(-1.0, 12.0, elev)          # direct sunlight strength
	var golden := 1.0 - _sm(4.0, 35.0, elev)  # warm low sun
	# sun
	sun.rotation = Vector3(-deg_to_rad(clampf(elev, 2.0, 89.0)), az, 0.0)
	sun.light_energy = 1.8 * lit * cur[4]
	# a low sun grazes the ground: push the shadow lookup off the surface a bit
	# more so the ground doesn't shadow itself in bands (worst at dawn / dusk)
	sun.shadow_normal_bias = lerpf(2.0, 4.0, golden)   # 2.0 = Godot default (midday unchanged)
	sun.shadow_bias = lerpf(0.1, 0.25, golden)
	sun.visible = elev > -1.0
	sun.light_color = Color(1.0, 0.97, 0.93).lerp(Color(1.0, 0.6, 0.32), golden * 0.85)
	# moon for night time
	var night := _sm(2.0, -10.0, elev)
	moon.rotation = Vector3(deg_to_rad(-50.0), az + PI, 0.0)
	moon.light_energy = 0.3 * night * (1.0 - cover * 0.5)
	moon.visible = night > 0.01
	# sky colours
	var day_top := Color(0.28, 0.45, 0.72)
	var day_hor := Color(0.76, 0.81, 0.86)
	var set_top := Color(0.27, 0.32, 0.52)
	var set_hor := Color(0.98, 0.6, 0.34)
	var n_top := Color(0.004, 0.007, 0.018)
	var n_hor := Color(0.025, 0.035, 0.06)
	var top := n_top.lerp(set_top.lerp(day_top, 1.0 - golden), day)
	var hor := n_hor.lerp(set_hor.lerp(day_hor, 1.0 - golden), day)
	var grey := Color(0.52, 0.54, 0.57) * lerpf(0.06, 1.0, day)
	top = top.lerp(grey * 0.85, clampf(dk + cover * 0.25, 0.0, 1.0))
	hor = hor.lerp(grey, dk)
	psm.sky_top_color = top
	psm.sky_horizon_color = hor
	psm.ground_horizon_color = hor * 0.9
	psm.ground_bottom_color = hor * 0.25
	var cloud_col := Color(1.0, 0.95, 0.9).lerp(Color(0.55, 0.55, 0.58), dk)
	cloud_col = cloud_col.lerp(Color(1.0, 0.7, 0.5), golden * day * 0.5) * lerpf(0.05, 1.0, day)
	cloud_col.a = cover
	psm.sky_cover_modulate = cloud_col
	psm.sun_curve = 0.08
	# light, fog, exposure
	env.ambient_light_energy = lerpf(0.22, 0.95, day) * lerpf(1.0, 0.8, dk)
	env.fog_density = cur[2]
	env.fog_light_color = hor.lerp(Color(0.72, 0.74, 0.77) * lerpf(0.05, 1.0, day), 0.35)
	env.fog_sun_scatter = 0.35 * lit
	env.volumetric_fog_density = cur[3]
	env.volumetric_fog_albedo = Color(0.9, 0.9, 0.92)
	env.tonemap_exposure = lerpf(1.7, 1.0, day)
	env.glow_intensity = lerpf(0.8, 0.5, day)
	# ground + road
	if track:
		track.set_wet(cur[5])
		track.set_snow(cur[6])
	# precipitation
	var r: float = cur[7]
	var s: float = cur[8]
	rain.emitting = r > 0.03
	rain.amount_ratio = clampf(r, 0.05, 1.0)
	snowfall.emitting = s > 0.03
	snowfall.amount_ratio = clampf(s, 0.05, 1.0)
	dark = elev < 5.0 or (dk > 0.5 and elev < 14.0)
	Gfx.update_light(sun, moon, env, hor.lerp(top, 0.5))   # baked lighting follows the time of day

func clock_text() -> String:
	var h := int(time_h)
	var m := int((time_h - h) * 60.0)
	return "%02d:%02d" % [h, m]

func _soft_dot() -> ImageTexture:
	var S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x - S / 2.0 + 0.5, y - S / 2.0 + 0.5).length() / (S / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _build_precip() -> void:
	# rain: fast falling streaks around the camera
	rain = GPUParticles3D.new()
	rain.amount = 3000 if vr else 5000
	rain.lifetime = 1.0
	rain.local_coords = false
	rain.emitting = false
	rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 2, 28)
	pm.direction = Vector3(0.05, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 25.0
	pm.gravity = Vector3(0, -2, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.008, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.84, 0.9, 0.13)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	# drops right in front of the lens fade out instead of becoming big white sticks
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.0
	m.distance_fade_max_distance = 5.0
	q.material = m
	rain.draw_pass_1 = q
	add_child(rain)
	# snow: slow, drifting flakes
	snowfall = GPUParticles3D.new()
	snowfall.amount = 3500 if vr else 6000
	snowfall.lifetime = 7.0
	snowfall.local_coords = false
	snowfall.emitting = false
	snowfall.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(30, 3, 30)
	sm.direction = Vector3(0, -1, 0)
	sm.spread = 20.0
	sm.initial_velocity_min = 1.2
	sm.initial_velocity_max = 2.2
	sm.gravity = Vector3(0, -0.3, 0)
	sm.turbulence_enabled = true
	sm.turbulence_noise_strength = 1.5
	sm.turbulence_influence_min = 0.05
	sm.turbulence_influence_max = 0.12
	sm.scale_min = 0.6
	sm.scale_max = 1.3
	snowfall.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.07, 0.07)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_texture = _soft_dot()
	smat.albedo_color = Color(1, 1, 1, 0.9)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sq.material = smat
	snowfall.draw_pass_1 = sq
	add_child(snowfall)

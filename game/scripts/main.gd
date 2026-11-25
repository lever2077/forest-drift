# Forest Drift - entry point. Builds the world, the car, input, desktop + VR.
extends Node3D

const Track = preload("res://scripts/track.gd")
const Forest = preload("res://scripts/forest.gd")
const Car = preload("res://scripts/car.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const Hud = preload("res://scripts/hud.gd")
const EngineAudio = preload("res://scripts/engine_audio.gd")
const EnvController = preload("res://scripts/env_controller.gd")
const EndlessTrack = preload("res://scripts/endless_track.gd")
const Mountains = preload("res://scripts/mountains.gd")
const HillTrack = preload("res://scripts/hill_track.gd")
const CircuitTrack = preload("res://scripts/circuit_track.gd")
const Grass = preload("res://scripts/grass.gd")
const Profile = preload("res://scripts/profile.gd")
const VrPanel = preload("res://scripts/vr_panel.gd")
# map index -> name (index order is what's saved; the menu shows them in MENU_ORDER)
const MAPS := ["Greenwood Circuit", "Endless Road", "Switchback Ridge", "Compass Raceway"]
const MAP_INFO := [
	"2.5 km forest loop with laps and three jump crests",
	"a never-ending country road through the forest: gentle bends and rolling hills",
	"3.7 km mountain pass: stacked hairpins up an open grassy hillside",
	"a twisting race circuit: esses, hairpins and a long start/finish straight",
]
const MENU_ORDER := [1, 0, 2, 3]
static var map_choice := -1
static var auto_start := false     # set when the menu reloads the world to drive straight away
static var biome_name := ""         # cosmetic biome picked on the start menu (saved)
const Biome = preload("res://scripts/biome.gd")

# the biome a map is actually built in: the stadium only exists on the race tracks
static func biome_for(map: int, name: String) -> String:
	if name == "Stadium" and map == 1:
		return "Forest"
	return name if name in Biome.LIST else "Forest"

func set_biome(name: String) -> void:
	biome_name = name
	save_settings()

var track
var forest
var car
var cam
var hud
var env: Environment
var sun: DirectionalLight3D
var vr := false
var xr_origin: XROrigin3D
var xr_left: XRController3D
var xr_right: XRController3D
var headlights := false
var shot_dir := ""
var sky_mat: ProceduralSkyMaterial
var envc
var was_dark := false
var grass
var grass_quality := 2      # 0 off, 1 low, 2 high (Settings panel, saved)
var car_damage := false     # body panels dent on impacts (Settings panel, saved)

var car_effects := true     # damage can break the engine / wheels / axles (Settings, saved)

func set_car_damage(on: bool) -> void:
	car_damage = on
	if car:
		car.model.set_damage_enabled(on, car)
	save_settings()

func set_car_effects(on: bool) -> void:
	car_effects = on
	if car:
		car.set_mech_effects(on)
	save_settings()

# Effects sub-settings: what the damage can break (saved)
var dmg_engine := true
var dmg_wheels := true
var wheels_fall := true

func set_mech_option(key: String, on: bool) -> void:
	match key:
		"engine": dmg_engine = on
		"wheels": dmg_wheels = on
		"fall": wheels_fall = on
	if car:
		car.set_mech_options(dmg_engine, dmg_wheels, wheels_fall)
	save_settings()

# Settings > Display: which readouts the HUD shows (saved)
var display := {"fps": true, "ping": true, "engine": true, "tyres": true, "minimap": true}

func set_display(key: String, on: bool) -> void:
	display[key] = on
	if hud and hud.has_method("apply_display"):
		hud.apply_display()
	save_settings()

# Settings > Audio: volume per bus, 0..1 linear (saved). Every sound player is
# routed to one of these buses; they all feed into Master.
const VOLUME_BUSES := ["Master", "Engine", "Tyres", "Effects", "Music"]
var volumes := {"Master": 0.8, "Engine": 1.0, "Tyres": 1.0, "Effects": 1.0, "Music": 0.7}

func _setup_audio() -> void:
	# buses live in the AudioServer, so they survive scene reloads: create them once
	for b in VOLUME_BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for b in VOLUME_BUSES:
			volumes[b] = clampf(float(cf.get_value("audio", b, volumes[b])), 0.0, 1.0)
	for b in VOLUME_BUSES:
		_apply_volume(b)

func _apply_volume(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	var v: float = volumes[bus]
	AudioServer.set_bus_volume_db(i, linear_to_db(max(v, 0.0001)))
	if bus != "Master":   # Master's mute is used for "window in the background"
		AudioServer.set_bus_mute(i, v <= 0.001)

func set_volume(bus: String, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	_apply_volume(bus)
	save_settings()

func set_grass(q: int) -> void:
	grass_quality = q
	if grass:
		grass.set_quality(q)
	save_settings()

# Settings > Graphics > Baked lighting: 0 off, 1 low, 2 high (saved).
# The world is generated when a map loads, so editor lightmaps can't be used;
# instead Godot's SDFGI bakes the scene into a signed-distance field around the
# camera and bounces the sun and sky light off the ground, trees and road
# (green light under the canopy, darker contact areas, light spilling off the
# road). High also adds screen-space indirect light for the fine detail.
var gi_quality := 0

func set_gi(q: int) -> void:
	gi_quality = clampi(q, 0, 2)
	_apply_gi()
	save_settings()

func _apply_gi() -> void:
	if env == null:
		return
	var q := 0 if vr else gi_quality
	env.sdfgi_enabled = q > 0
	env.ssil_enabled = q == 2
	if q > 0:
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		env.sdfgi_cascades = 4 if q == 1 else 6
		env.sdfgi_min_cell_size = 0.4 if q == 1 else 0.2
		env.sdfgi_energy = 1.0
		env.sdfgi_bounce_feedback = 0.5
		env.ssil_radius = 4.0
		env.ssil_intensity = 0.8
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_32 if q == 1 else RenderingServer.ENV_SDFGI_RAY_COUNT_64)
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES if q == 1 else RenderingServer.ENV_SDFGI_CONVERGE_IN_15_FRAMES)
		RenderingServer.gi_set_use_half_resolution(q == 1)

# moving things must not be baked into the lighting (they'd leave a ghost of
# themselves behind), so the car and its loose parts only receive it
func _mark_gi_dynamic(n: Node) -> void:
	if n is GeometryInstance3D:
		n.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for c in n.get_children():
		_mark_gi_dynamic(c)

func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D and car and is_instance_valid(car) and car.is_ancestor_of(n):
		n.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_dir = a.substr(7)
	_setup_input()
	_setup_audio()
	Profile.load_profile()
	var xr :=XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and shot_dir == "":
		vr = true
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if "--vrsim" in OS.get_cmdline_user_args():
		vr = true   # dev aid: the VR menu / HUD on the desktop window, no headset
	_setup_environment()
	# map (picked on the start menu, remembered)
	var cfm := ConfigFile.new()
	var have_cfg := cfm.load(SETTINGS_PATH) == OK
	gi_quality = int(cfm.get_value("world", "gi", 0)) if have_cfg else 0
	for a in OS.get_cmdline_user_args():   # dev aid: --gi=0..2
		if a.begins_with("--gi="):
			gi_quality = int(a.substr(5))
	_apply_gi()
	get_tree().node_added.connect(_on_node_added)
	if map_choice < 0:
		map_choice = cfm.get_value("world", "map", 0) if have_cfg else 0
	if "--endless" in OS.get_cmdline_user_args():
		map_choice = 1
	if "--loop" in OS.get_cmdline_user_args():
		map_choice = 0
	if "--hill" in OS.get_cmdline_user_args():
		map_choice = 2
	if "--circuit" in OS.get_cmdline_user_args():
		map_choice = 3
	map_choice = clampi(map_choice, 0, MAPS.size() - 1)
	if biome_name == "":
		biome_name = cfm.get_value("world", "biome", "Forest") if have_cfg else "Forest"
	for a in OS.get_cmdline_user_args():   # dev aid: --biome=Savannah (spaces as _)
		if a.begins_with("--biome="):
			biome_name = a.substr(8).replace("_", " ")
	var args := OS.get_cmdline_user_args()
	var test_mode := shot_dir != "" or "--drivetest" in args or "--bottest" in args or "--edgetest" in args or "--vrgrabtest" in args
	# start screen: a fresh launch (or Esc while driving) shows the blurred forest
	# and the map list; picking a map rebuilds the scene straight into that map
	if not test_mode and not auto_start:
		_build_start_screen(args)
		return
	auto_start = false
	started = true
	track = [Track, EndlessTrack, HillTrack, CircuitTrack][map_choice].new()
	track.name = "Track"
	track.biome = Biome.get_biome(biome_for(map_choice, biome_name))
	add_child(track)
	track.build()
	envc = EnvController.new()
	envc.name = "Environment"
	add_child(envc)
	envc.setup(env, sun, sky_mat, track, vr)
	_load_settings()
	var mountains := Mountains.new()
	mountains.name = "Mountains"
	add_child(mountains)
	mountains.build(env, envc, track.biome)
	forest = Forest.new()
	forest.name = "Forest"
	add_child(forest)
	forest.set_biome(track.biome)
	forest.build(track, 0.7 if vr else 1.0, not track.endless)
	if track.endless:
		track.set_forest(forest)
	grass = Grass.new()
	grass.name = "Grass"
	add_child(grass)
	grass.setup(track, 0.6 if vr else 1.0, grass_quality)
	car = Car.new()
	car.name = "Car"
	var car_id := Profile.equipped_car
	for a in args:   # dev aid: --car=car_cc96_2
		if a.begins_with("--car="):
			car_id = a.substr(6)
	car.car_def = Profile.CARS.get(car_id, Profile.CARS[Profile.STOCK_CAR])   # Inventory > Cars
	add_child(car)
	car.setup(track, forest, self)
	car.model.position.z = 0.05   # put the CG between the axles
	car.model.set_paint(Profile.skin_color(Profile.equipped_skin))   # skin from the Inventory
	_mark_gi_dynamic(car)
	car.set_mech_effects(car_effects)
	car.set_mech_options(dmg_engine, dmg_wheels, wheels_fall)
	if not test_mode:   # dev test runs don't pay into the real profile
		car.points_earned.connect(func(_s, _m, pts): Profile.add_points(pts))
	if car_damage:
		car.model.set_damage_enabled(true, car)
	var audio := EngineAudio.new()
	car.add_child(audio)
	audio.setup(car)
	if vr:
		_setup_vr()
		car.assist = 0.35
		# the normal HUD (speed, score, points, lap, minimap) on a see-through
		# screen floating above the dashboard
		vr_hud_panel = VrPanel.new()
		vr_hud_panel.name = "VRHud"
		car.model.body.add_child(vr_hud_panel)
		vr_hud_panel.setup(Vector2i(900, 506), 1.3, true, false, true)
		vr_hud_panel.position = xr_eye + Vector3(0.0, 0.2, -1.2)
		vr_hud_panel.rotation.x = deg_to_rad(6.0)
		hud = Hud.new()
		hud.vr_mode = true
		vr_hud_panel.add_ui(hud)
		hud.setup(car, track)
		hud.build_settings(envc, self)
		for a in args:   # dev aid (with --vrsim): --menushot= also pictures the VR cockpit after a map loads
			if a.begins_with("--menushot="):
				get_tree().create_timer(4.0).timeout.connect(func():
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(a.substr(11).replace(".png", "_drive.png"))
					get_tree().quit())
	else:
		cam = CameraRig.new()
		add_child(cam)
		cam.setup(car)
		cam.current = true
		hud = Hud.new()
		add_child(hud)
		hud.setup(car, track)
		hud.build_settings(envc, self)
		if "--settings" in args:
			hud.toggle_settings()
		if "--controls" in args:
			hud.toggle_controls()
	print("World built in %d ms (%d road samples, %.0f m lap)" % [Time.get_ticks_msec() - t0, track.pts.size(), track.total_len])
	if shot_dir != "" and "--crashtest" in args:
		_crash_test()
	elif shot_dir != "":
		_run_screenshots()
	if "--drivetest" in args:
		_drive_test()
	if "--bottest" in args:
		_bot_test()
	if "--edgetest" in args:
		_edge_test()
	if "--fliptest" in args:
		_flip_test()
	if "--menutest" in args:
		_menu_test_step()

# dev aid: --crashtest drives the car into a tree at --speed= km/h (default 72)
# with damage on, prints what broke, then takes the usual screenshots
func _crash_test() -> void:
	car.model.set_damage_enabled(true, car)
	await get_tree().create_timer(1.0).timeout
	var kmh := 72.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--speed="):
			kmh = float(a.substr(8))
	# a tree 15-45 m from the car with clear ground in front of it
	var cp: Vector3 = car.global_position
	var best := Vector3.ZERO
	var bd := 1e9
	for k in forest.hash.keys():
		for t in forest.hash[k]:
			var tv: Vector3 = t
			var d := Vector2(tv.x - cp.x, tv.y - cp.z).length()
			if d > 15.0 and d < 45.0 and d < bd:
				bd = d
				best = tv
	var tree := Vector3(best.x, 0, best.y)
	var dir := (tree - Vector3(cp.x, 0, cp.z)).normalized()
	var start := tree - dir * 9.0
	start.y = track.ground_h(start.x, start.z) + 0.05
	car.global_position = start
	car.yaw = atan2(-dir.x, -dir.z)
	if "--side" in OS.get_cmdline_user_args():
		car.yaw += PI / 2.0     # slide into it sideways (right side first)
	car.yaw_rate = 0.0
	car.vel = dir * kmh / 3.6
	await get_tree().create_timer(0.9).timeout
	print("  speed just after the hit: %.0f km/h" % (car.speed * 3.6))
	await get_tree().create_timer(1.6).timeout
	var pm := []
	if car.model.damage:
		for n in car.model.damage.parts.keys():
			var p: Dictionary = car.model.damage.parts[n]
			pm.append("%s=%s" % [n, ["on", "loose", "OFF"][p["mode"]]])
		for n in car.model.damage.windows.keys():
			var w: Dictionary = car.model.damage.windows[n]
			pm.append("%s=%s" % [n, "SHATTERED" if w["shattered"] else ("cracked" if w["health"] < 1.0 else "ok")])
	var fmax := 0.0
	if car.model.damage:
		var dm = car.model.damage
		for i in dm.rest.size():
			fmax = max(fmax, (dm.pos[i] - dm.rest[i]).length())
	print("CRASH %.0f km/h: frame moved up to %.2f m, dents %d, engine %.2f temp %.2f wheels %s axles %s" % [kmh, fmax, car.model.dents.size(), car.engine_dmg, car.engine_temp, str(car.wheel_dmg), str(car.axle_broken)])
	print("  parts: " + ", ".join(pm))
	if "--repair" in OS.get_cmdline_user_args():
		car.restart()
		await get_tree().create_timer(0.5).timeout
		var fm := 0.0
		var dm2 = car.model.damage
		for i in dm2.rest.size():
			fm = max(fm, (dm2.pos[i] - dm2.rest[i]).length())
		var st := []
		for n in dm2.parts.keys():
			st.append("%s=%s" % [n, ["on", "loose", "OFF"][dm2.parts[n]["mode"]]])
		for n in dm2.windows.keys():
			st.append("%s=%s" % [n, "SHATTERED" if dm2.windows[n]["shattered"] else ("cracked" if dm2.windows[n]["health"] < 1.0 else "ok")])
		print("REPAIRED: frame %.2f m, dents %d, engine %.2f, wheels %s, %s" % [fm, car.model.dents.size(), car.engine_dmg, str(car.wheel_dmg), ", ".join(st)])
	_run_screenshots()

# ---------------------------------------------------------------- start screen
var menu_cam: Camera3D

func _build_start_screen(args: Array) -> void:
	envc = EnvController.new()
	envc.name = "Environment"
	add_child(envc)
	envc.setup(env, sun, sky_mat, null, vr)
	_load_settings()
	var mountains := Mountains.new()
	mountains.name = "Mountains"
	add_child(mountains)
	mountains.build(env, envc)
	_build_menu_forest()
	hud = Hud.new()
	if vr:
		# standing in the forest with the menu on a big screen in front of you;
		# point a controller at it and pull the trigger to click
		_make_xr_rig(self, Vector3(0, 1.6, 0), true)
		vr_menu_panel = VrPanel.new()
		vr_menu_panel.name = "VRMenu"
		add_child(vr_menu_panel)
		vr_menu_panel.setup(Vector2i(1000, 880), 1.5, true)
		vr_menu_panel.position = Vector3(0, 1.5, -1.15)
		hud.vr_mode = true
		vr_menu_panel.add_ui(hud)
		hud.setup_menu_screen(false)
	else:
		menu_cam = Camera3D.new()
		menu_cam.fov = 62.0
		menu_cam.far = 2500.0
		menu_cam.position = Vector3(0, 1.8, 0)
		add_child(menu_cam)
		menu_cam.current = true
		add_child(hud)
		hud.setup_menu_screen()
	hud.build_settings(envc, self)
	var entries := []
	for i in MENU_ORDER:
		entries.append({"index": i, "name": MAPS[i], "info": MAP_INFO[i], "endless": i == 1})
	hud.build_menu(entries, map_choice)
	hud.build_biome_picker(Biome.LIST, Biome.INFO, biome_name, self)
	hud.map_picked.connect(_pick_map)
	for a in args:   # dev aid: --openpanel=cache|inventory|settings opens that panel
		if a.begins_with("--openpanel="):
			match a.substr(12):
				"cache": hud._toggle_shop_panel(hud.cache_panel)
				"opencache":
					hud._toggle_shop_panel(hud.cache_panel)
					hud.cache_result = Profile.open_cache("basic")
					hud._fill_shop_panel(hud.cache_panel)
				"inventory": hud._toggle_shop_panel(hud.inventory_panel)
				"settings": hud.toggle_settings()
				"graphics":
					hud.toggle_settings()
					hud.settings_tabs.current_tab = 1
				"audio":
					hud.toggle_settings()
					hud.settings_tabs.current_tab = hud.settings_tabs.get_tab_count() - 1
	for a in args:   # dev aid (with --vrsim): --vrclick=Caches aims a laser at that button and clicks it
		if a.begins_with("--vrclick=") and vr_menu_panel:
			vr_scripted = true   # the real controllers would fight the scripted laser
			await get_tree().create_timer(1.5).timeout
			for label in a.substr(10).split(","):
				var btn: Button = _find_button(hud, label.replace("_", " "))
				if btn == null:
					print("VRCLICK no button '%s'" % label)
					continue
				var c: Vector2 = btn.get_global_rect().get_center()
				var uv := c / Vector2(vr_menu_panel.px)
				var local := Vector3((uv.x - 0.5) * vr_menu_panel.size_m.x, (0.5 - uv.y) * vr_menu_panel.size_m.y, 0)
				var target: Vector3 = vr_menu_panel.global_transform * local
				var o: Vector3 = xr_right.global_position + Vector3(0.2, -0.3, 0)
				var h: Dictionary = vr_menu_panel.hit(o, (target - o).normalized())
				print("VRCLICK '%s' at %s -> hit %s" % [label, str(c), str(h.get("pos", "MISS"))])
				btn.button_down.connect(func(): print("VRCLICK   button_down"))
				btn.pressed.connect(func(): print("VRCLICK   pressed"))
				btn.mouse_entered.connect(func(): print("VRCLICK   hover"))
				if not h.is_empty():
					vr_menu_panel.point(h, false)
					await get_tree().process_frame
					vr_menu_panel.point(h, true)
					await get_tree().process_frame
					vr_menu_panel.point(h, false)
				await get_tree().create_timer(0.6).timeout
	for a in args:   # dev aid: --menushot=file.png saves a picture of the start screen
		if a.begins_with("--menushot="):
			await get_tree().create_timer(3.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.substr(11))
			get_tree().quit()
	if "--menutest" in args:
		_menu_test_step()

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text.begins_with(text):
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null

# a small patch of forest around the camera for the blurred backdrop
func _build_menu_forest() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	pm.subdivide_width = 0
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.2, 0.08)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	forest = Forest.new()
	forest.name = "Forest"
	add_child(forest)
	forest.build(null, 1.0, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var trees := []
	var bushes := []
	for i in 900:
		var a := rng.randf() * TAU
		var r := 9.0 + pow(rng.randf(), 0.8) * 230.0
		var s := rng.randf_range(0.8, 1.25)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.92, 1.1), s))
		trees.append([Transform3D(b, Vector3(cos(a) * r, -0.1, sin(a) * r)), rng.randi() % forest.VARIANTS])
	for i in 160:
		var a := rng.randf() * TAU
		var r := 5.0 + rng.randf() * 60.0
		var bs := rng.randf_range(0.7, 1.5)
		bushes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(bs, bs * 0.8, bs)), Vector3(cos(a) * r, -0.1, sin(a) * r)))
	# split into cells so the detail levels work like on the maps
	var cells := {}
	for t in trees:
		var o: Vector3 = (t[0] as Transform3D).origin
		var k := Vector2i(int(floor(o.x / 48.0)), int(floor(o.z / 48.0)))
		if not cells.has(k):
			cells[k] = [[], []]
		cells[k][0].append(t)
	for b in bushes:
		var o: Vector3 = (b as Transform3D).origin
		var k := Vector2i(int(floor(o.x / 48.0)), int(floor(o.z / 48.0)))
		if not cells.has(k):
			cells[k] = [[], []]
		cells[k][1].append(b)
	for k in cells.keys():
		var kv: Vector2i = k
		forest.add_tree_block(cells[k][0], cells[k][1], Vector3((kv.x + 0.5) * 48.0, 0, (kv.y + 0.5) * 48.0), forest)

# Esc while driving: back to the start screen to pick a map
func _back_to_menu() -> void:
	auto_start = false
	save_settings()
	_safe_reload()

# dev aid: --menutest drives the menu automatically (pick endless with changed
# settings, come back, pick again...) to catch crashes when switching maps
static var menu_test_n := 0
func _menu_test_step() -> void:
	await get_tree().create_timer(2.0).timeout
	menu_test_n += 1
	print("MENUTEST step %d (map %s, in menu: %s)" % [menu_test_n, MAPS[map_choice], car == null])
	var steps := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--steps="):
			steps = int(a.substr(8))
	if menu_test_n > steps:
		print("MENUTEST done")
		get_tree().quit()
		return
	if car == null:
		_pick_map([1, 0, 2, 3][(menu_test_n / 2) % 4])
	else:
		if "--crash" in OS.get_cmdline_user_args():
			# wreck the car (parts flying, glass shattering) and leave mid-crash
			car.model.set_damage_enabled(true, car)
			var cp: Vector3 = car.global_position
			var fw := Vector3(-sin(car.yaw), 0, -cos(car.yaw))
			var best := Vector3(cp.x + fw.x * 9.0, 0, cp.z + fw.z * 9.0)
			var bd := 1e9
			for k in forest.hash.keys():
				for t in forest.hash[k]:
					var tv: Vector3 = t
					var d := Vector2(tv.x - cp.x, tv.y - cp.z).length()
					if d > 12.0 and d < bd:
						bd = d
						best = Vector3(tv.x, 0, tv.y)
			var dir := (best - Vector3(cp.x, 0, cp.z)).normalized()
			var st := best - dir * 7.0
			st.y = track.ground_h(st.x, st.z) + 0.05
			car.global_position = st
			car.yaw = atan2(-dir.x, -dir.z)
			car.vel = dir * 110.0 / 3.6 + Vector3(0, 3, 0)
			await get_tree().create_timer(0.15 + 0.2 * (menu_test_n % 4)).timeout
		_back_to_menu()

# dev aid: --fliptest drops the car on its side / roof (still, sliding, spinning,
# rolling over) and logs whether it settles on the ground and stays put
func _flip_test() -> void:
	set_process(false)
	var cases := [
		["side, still", 0.0, PI / 2, 0.0, 0.0, 0.0],
		["roof, still", 0.0, PI, 0.0, 0.0, 0.0],
		["side, sliding 60", 0.0, -PI / 2, 60.0, 0.0, 0.0],
		["roof, sliding+spin", 0.0, PI, 50.0, 2.5, 0.0],
		["rollover at 80", 0.0, 0.0, 80.0, 0.0, 7.0],
		["roof drop from 3 m", 0.0, PI, 0.0, 0.0, 0.0],
	]
	# mid-air tumble: with nothing touching, angular momentum must stay the same
	# (a real spinning body), however the car turns over
	car.reset_on_track()
	await get_tree().create_timer(0.3).timeout
	car.global_position.y += 40.0
	car.pitch_rate = 1.5
	car.roll_rate = 3.0
	car.yaw_rate = 1.0
	car.grounded = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var L0: Vector3 = car.rb_basis * ((car.rb_basis.transposed() * car.rb_w) * Vector3(car.I_PITCH, car.IZ, car.I_ROLL))
	var Lmax := 0.0
	for k in 120:   # 1 s of free flight
		await get_tree().physics_frame
		var Lk: Vector3 = car.rb_basis * ((car.rb_basis.transposed() * car.rb_w) * Vector3(car.I_PITCH, car.IZ, car.I_ROLL))
		Lmax = max(Lmax, (Lk - L0).length())
	print("AIR tumble: rigid=%s, angular momentum %.0f, drifted at most %.2f%% over 1 s" % [car.rigid, L0.length(), Lmax / L0.length() * 100.0])
	for c in cases:
		await get_tree().create_timer(0.5).timeout
		car.reset_on_track()
		var fw := Vector3(-sin(car.yaw), 0, -cos(car.yaw))
		car.pitch = c[1]
		car.roll = c[2]
		car.pitch_rate = 0.0
		car.roll_rate = c[5]
		car.vy = 0.0
		car.vel = fw * float(c[3]) / 3.6
		car.yaw_rate = c[4]
		car.global_position.y += 3.0 if String(c[0]).contains("drop") else 1.2
		car.in_throttle = 0.0
		var t := 0.0
		var log_t := 0.0
		var max_gap_late := 0.0
		var yaw0: float = car.yaw
		var yaw_late := 0.0
		var ang_late := 0.0
		var pr0 := Vector2.ZERO
		var q0 := Quaternion.IDENTITY
		var p0 := Vector3.ZERO
		while t < 6.0:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			car.in_throttle = 0.0
			car.in_brake = 0.0
			car.in_steer = 0.0
			# gap between the lowest corner of the body and the ground
			var b: Basis = car._body_basis()
			var low := 1e9
			for cp in car.HULL_PTS:
				var wp: Vector3 = car.global_position + b * (cp as Vector3)
				low = min(low, wp.y - track.ground_h(wp.x, wp.z))
			for wl in car.WHEEL_LOCAL:
				var wp2: Vector3 = car.global_position + b * ((wl as Vector3) + Vector3(0, -car.c0[0], 0))
				low = min(low, wp2.y - track.ground_h(wp2.x, wp2.z))
			if t > 3.0:
				# true rotation (angle between orientations) and distance moved since 3 s
				if pr0 == Vector2.ZERO:
					pr0 = Vector2.ONE
					q0 = b.get_rotation_quaternion()
					p0 = car.global_position
				max_gap_late = max(max_gap_late, low)
				ang_late = max(ang_late, q0.angle_to(b.get_rotation_quaternion()))
				yaw_late = max(yaw_late, (car.global_position - p0).length())
			log_t += dt
			if log_t >= 0.5 and "--verbose" in OS.get_cmdline_user_args():
				log_t = 0.0
				print("   t=%.1f gap=%.2f pitch=%.0f roll=%.0f yawrate=%.2f v=%.1f vy=%.2f grounded=%s" % [t, low, rad_to_deg(car.pitch), rad_to_deg(car.roll), car.yaw_rate, car.speed * 3.6, car.vy, car.grounded])
		print("FLIP %-20s after 3 s: max gap %.2f m, moved %.2f m, rotated %.1f deg, speed %.1f km/h, up.y=%.2f" % [c[0], max_gap_late, yaw_late, rad_to_deg(ang_late), car.speed * 3.6, car._body_basis().y.y])
	get_tree().quit()

# drives off the road edge and back on at a given speed and logs body motion
func _edge_test() -> void:
	set_process(false)
	var spd := 15.0 / 3.6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--speed="):
			spd = float(a.substr(8)) / 3.6
	var max_lift := 0.0
	var max_pitch := 0.0
	var max_roll := 0.0
	var air := 0.0
	var settle := 0.0
	while settle < 1.0:
		await get_tree().physics_frame
		settle += get_physics_process_delta_time()
	var t0: Vector3 = track.tans[car.track_idx]
	var side := Vector3(-t0.z, 0, t0.x).normalized()
	# leave the road at 30 deg, then come back on: off one edge, back, other edge, back
	var dirs := [side * 0.5 + t0 * 0.87, -side * 0.5 + t0 * 0.87, -side * 0.5 + t0 * 0.87, side * 0.5 + t0 * 0.87]
	for k in dirs.size():
		var dv: Vector3 = (dirs[k] as Vector3).normalized()
		car.yaw = atan2(-dv.x, -dv.z)
		car.yaw_rate = 0.0
		car.vel = dv * spd
		var t := 0.0
		var going_out := k % 2 == 0
		while t < 6.0:
			var dd: float = track.road_dist(car.global_position.x, car.global_position.z)
			if (going_out and dd > track.HALF_W + 4.0) or (not going_out and dd < 1.5):
				break
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			t += dt
			if car.grounded:
				car.vel = dv * spd
			car.in_throttle = 0.0
			var p: Vector3 = car.global_position
			var lift: float = p.y - track.ground_h(p.x, p.z)
			max_lift = max(max_lift, lift)
			max_pitch = max(max_pitch, abs(car.pitch))
			max_roll = max(max_roll, abs(car.roll))
			if not car.grounded:
				air += dt
	print("EDGE %.0f km/h: max_lift=%.3f m  max_pitch=%.1f deg  max_roll=%.1f deg  airborne=%.3f s" % [spd * 3.6, max_lift, rad_to_deg(max_pitch), rad_to_deg(max_roll), air])
	get_tree().quit()

# simple autopilot: aims the travel direction at a point down the road with
# plain proportional steering - a stand-in for a casual player
func _bot_test() -> void:
	set_process(false)
	var n: int = track.pts.size()
	var t := 0.0
	var off := 0.0
	var crashes := 0
	var last_speed := 0.0
	var slip_sum := 0.0
	var slip_n := 0
	var dist := 0.0
	var chk := 0.0
	var stuck := 0.0
	var resets := 0
	var logt := 0.0
	var airs := []
	car.points_earned.connect(func(s, m, pts):
		print("  POINTS lap score %d x%.2f = %d" % [s, m, pts]))
	car.air_landed.connect(func(at, _p):
		airs.append(at)
		if "--verbose" in OS.get_cmdline_user_args():
			print("  JUMP %.2fs idx=%d v=%.0f road_d=%.1f pitch=%.0f roll=%.0f" % [at, car.track_idx, car.speed * 3.6,
				track.road_dist(car.global_position.x, car.global_position.z), rad_to_deg(car.pitch), rad_to_deg(car.roll)]))
	# --fps: short timed run with vsync off, prints the average frame rate
	var fps_mode := "--fps" in OS.get_cmdline_user_args()
	var t_end := 25.0 if fps_mode else 120.0
	var f0 := 0
	var w0 := 0
	if fps_mode:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		if "--smoke" in OS.get_cmdline_user_args():
			car.force_smoke = true     # worst case: full tyre smoke the whole lap
		# --off=hud,audio,cam,env,mountains : switch systems off to find what's slow
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--off="):
				for nm in a.substr(6).split(","):
					var nodes := {"hud": hud, "cam": cam, "env": envc, "mountains": get_node_or_null("Mountains"),
						"audio": car.get_children().filter(func(c): return c is EngineAudio).front() if true else null}
					if nodes.has(nm) and nodes[nm]:
						nodes[nm].set_process(false)
						print("  (off: %s)" % nm)
	var perf_n := 0
	var perf_proc := 0.0
	var perf_phys := 0.0
	var perf_stream := 0.0
	var perf_car := 0.0
	while t < t_end:
		if fps_mode and f0 == 0 and t > 5.0:
			f0 = Engine.get_frames_drawn()
			w0 = Time.get_ticks_msec()
		if fps_mode and f0 > 0:
			perf_n += 1
			perf_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			perf_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			perf_stream += prof_stream_ms
			perf_car += car.prof_ms
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		n = track.pts.size()
		var look := 6 + int(car.speed * 0.5)
		var tgt: Vector3 = track.pts[(car.track_idx + look) % n]
		var p: Vector3 = car.global_position
		var want := Vector2(tgt.x - p.x, tgt.z - p.z).normalized()
		var hv := Vector2(car.vel.x, car.vel.z)
		var path := hv.normalized() if hv.length() > 3.0 else Vector2(-sin(car.yaw), -cos(car.yaw))
		var err := path.angle_to(want)   # + = target is clockwise (right) on screen coords
		car.in_steer = clampf(err * 2.5, -1.0, 1.0)
		car.in_throttle = 0.8
		car.in_brake = 0.0
		car.in_handbrake = 0.0
		car.in_analog = false
		dist += car.speed * dt
		if not car.on_road:
			off += dt
		if abs(car.body_slip) > 0.18:
			slip_sum += abs(car.body_slip)
			slip_n += 1
		if not car.on_road:
			stuck += dt
		else:
			stuck = 0.0
		if stuck > 3.0:
			car.reset_on_track()
			resets += 1
			stuck = 0.0
		logt += dt
		if logt > 4.0 and "--verbose" in OS.get_cmdline_user_args():
			logt = 0.0
			print("  t=%.0f idx=%d v=%.0f slip=%.0f road=%s steer_in=%.2f" % [t, car.track_idx, car.speed * 3.6, rad_to_deg(car.body_slip), car.on_road, car.in_steer])
		chk += dt
		if chk >= 0.25:
			if last_speed > 8.0 and car.speed < last_speed * 0.6:
				crashes += 1
			last_speed = car.speed
			chk = 0.0
	if fps_mode:
		var secs := (Time.get_ticks_msec() - w0) / 1000.0
		var inst := 0
		for c in grass.get_children():
			if c is MultiMeshInstance3D:
				inst += c.multimesh.visible_instance_count
		print("FPS %s grass=%d: %.0f fps avg over %.0f s, %d grass tufts drawn at the end" % [MAPS[map_choice], grass_quality, (Engine.get_frames_drawn() - f0) / max(secs, 0.1), secs, inst])
		var pn: float = max(perf_n, 1)
		print("  per physics tick: process %.2f ms, physics %.2f ms (car %.2f ms, road streaming %.2f ms)" % [perf_proc / pn, perf_phys / pn, perf_car / pn, perf_stream / pn])
		var tri_info := []
		for v in forest.VARIANTS:
			tri_info.append("%d/%d" % [forest.hi_meshes[v].get_faces().size() / 3, forest.lo_meshes[v].get_faces().size() / 3])
		print("  tree triangles hi/lo per variant: %s" % ", ".join(tri_info))
		print("  render: %d draw calls, %.1fk triangles, %d objects; nodes %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	if "--terraincheck" in OS.get_cmdline_user_args() and track.endless:
		# sample points on the road surface of every built stretch and look for any
		# terrain triangle above them (a terrain sheet lying over the road)
		var bins := {}
		var lo_i := 1 << 30
		var hi_i := 0
		for c in track.chunks.keys():
			lo_i = min(lo_i, int(c) * track.CHUNK_N)
			hi_i = max(hi_i, (int(c) + 1) * track.CHUNK_N)
			var node: Node3D = track.chunks[c]
			for mi in node.get_children():
				if mi is MeshInstance3D and mi.mesh and mi.mesh.get_surface_count() == 1 and mi.mesh.surface_get_material(0) == track.terrain_mat:
					var arr: Array = mi.mesh.surface_get_arrays(0)
					var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					for k in range(0, ix.size(), 3):
						var tri := [vv[ix[k]], vv[ix[k + 1]], vv[ix[k + 2]]]
						var mnx: float = min(tri[0].x, min(tri[1].x, tri[2].x))
						var mxx: float = max(tri[0].x, max(tri[1].x, tri[2].x))
						var mnz: float = min(tri[0].z, min(tri[1].z, tri[2].z))
						var mxz: float = max(tri[0].z, max(tri[1].z, tri[2].z))
						for bx in range(int(floor(mnx / 16.0)), int(floor(mxx / 16.0)) + 1):
							for bz in range(int(floor(mnz / 16.0)), int(floor(mxz / 16.0)) + 1):
								var key := Vector2i(bx, bz)
								if not bins.has(key):
									bins[key] = []
								bins[key].append(tri)
		var bad := 0
		var total := 0
		for j in range(lo_i, min(hi_i, track.pts.size() - 1), 2):
			var p: Vector3 = track.pts[j]
			var tj: Vector3 = track.tans[j]
			var l := Vector3(-tj.z, 0, tj.x)
			for o in [-3.5, 0.0, 3.5]:
				var q: Vector3 = p + l * o
				total += 1
				var key := Vector2i(int(floor(q.x / 16.0)), int(floor(q.z / 16.0)))
				for tri in bins.get(key, []):
					var a: Vector3 = tri[0]
					var b: Vector3 = tri[1]
					var cc: Vector3 = tri[2]
					var den := (b.z - cc.z) * (a.x - cc.x) + (cc.x - b.x) * (a.z - cc.z)
					if abs(den) < 1e-6:
						continue
					var w1 := ((b.z - cc.z) * (q.x - cc.x) + (cc.x - b.x) * (q.z - cc.z)) / den
					var w2 := ((cc.z - a.z) * (q.x - cc.x) + (a.x - cc.x) * (q.z - cc.z)) / den
					var w3 := 1.0 - w1 - w2
					if w1 >= 0.0 and w2 >= 0.0 and w3 >= 0.0:
						var h := w1 * a.y + w2 * b.y + w3 * cc.y
						if h > p.y + 0.02:
							bad += 1
							break
		print("TERRAIN CHECK: %d of %d road surface points have terrain over them" % [bad, total])
	if car.model.damage_enabled:
		print("DAMAGE: %d dents, total depth %.2f m" % [car.model.dents.size(), car.model.damage_amount()])
	print("BOT %s: dist=%.0f m  avg=%.0f km/h  offroad=%.0f%%  crashes=%d resets=%d  score=%d  laps=%d  drift_time=%.0f%%  avg_drift_angle=%.0f deg  jumps=%d longest_air=%.2fs" % [
		MAPS[map_choice], dist, dist / t * 3.6, off / t * 100.0, crashes, resets, car.total_score + int(car.drift_points), car.laps,
		slip_n * get_physics_process_delta_time() / t * 100.0, rad_to_deg(slip_sum / max(slip_n, 1)), airs.size(), (airs.max() if airs.size() > 0 else 0.0)])
	get_tree().quit()

var started := false
var prof_stream_ms := 0.0     # time spent streaming the endless road this tick (for --fps)

# back to the start line with a fresh lap timer
func _restart() -> void:
	car.restart()
	if track.endless:
		track.update_stream(car.track_idx)

# scripted inputs + telemetry, used to tune the physics
func _drive_test() -> void:
	set_process(false)
	var phases := [
		["launch", 3.5, 1.0, 0.0, 0.0, 0.0],
		["turn-in", 1.0, 1.0, 0.0, 0.8, 0.0],
		["handbrake", 0.5, 0.3, 0.0, 1.0, 1.0],
		["hold drift", 4.0, 0.75, 0.0, 0.3, 0.0],
		["release", 2.0, 0.4, 0.0, 0.0, 0.0],
		["brake", 2.5, 0.0, 1.0, 0.0, 0.0],
	]
	if "--gentle" in OS.get_cmdline_user_args():
		# light steering inputs at speed - should never spin
		phases = [
			["launch", 4.0, 1.0, 0.0, 0.0, 0.0],
			["steer .15", 2.0, 0.7, 0.0, 0.15, 0.0],
			["steer .3", 2.0, 0.7, 0.0, 0.3, 0.0],
			["steer -.3", 2.0, 0.7, 0.0, -0.3, 0.0],
			["full lock", 1.5, 0.7, 0.0, 1.0, 0.0],
			["lift", 1.5, 0.0, 0.0, 1.0, 0.0],
		]
	for ph in phases:
		var t := 0.0
		var dur: float = ph[1]
		car.in_throttle = ph[2]
		car.in_brake = ph[3]
		car.in_steer = -float(ph[4])   # steer left
		car.in_handbrake = ph[5]
		while t < dur:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
			print("%-10s t=%.2f v=%5.1f km/h gear=%d rpm=%4d slip=%5.1f deg yaw=%5.2f spin=%4.1f drift=%d road=%s" % [
				ph[0], t, car.speed * 3.6, car.gear, int(car.rpm), rad_to_deg(car.body_slip), car.yaw_rate, car.spin, int(car.drift_points), car.on_road] + "  " + car.dbg + " hits=" + str(car.hits))
	get_tree().quit()

# ---------------------------------------------------------------- environment
func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky_mat = psm
	psm.sky_top_color = Color(0.34, 0.45, 0.6)
	psm.sky_horizon_color = Color(0.88, 0.82, 0.72)
	psm.sky_curve = 0.12
	psm.ground_bottom_color = Color(0.18, 0.2, 0.17)
	psm.ground_horizon_color = Color(0.8, 0.76, 0.68)
	psm.sun_angle_max = 25.0
	psm.sun_curve = 0.08
	var clouds := NoiseTexture2D.new()
	var cn := FastNoiseLite.new()
	cn.frequency = 0.006
	cn.fractal_octaves = 5
	clouds.noise = cn
	clouds.width = 1024
	clouds.height = 512
	clouds.seamless = true
	var cg := Gradient.new()
	cg.set_color(0, Color(1, 1, 1, 0))
	cg.set_color(1, Color(1, 1, 1, 1))
	cg.add_point(0.45, Color(1, 1, 1, 0))
	clouds.color_ramp = cg
	psm.sky_cover = clouds
	psm.sky_cover_modulate = Color(0.95, 0.9, 0.86, 0.75)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = not vr
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.75, 0.76)
	env.fog_density = 0.0032
	env.fog_aerial_perspective = 0.5
	env.fog_sun_scatter = 0.35
	env.fog_sky_affect = 0.35
	env.volumetric_fog_enabled = not vr
	env.volumetric_fog_density = 0.0045
	env.volumetric_fog_albedo = Color(0.9, 0.88, 0.84)
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_ambient_inject = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-140.0), 0)
	sun.light_color = Color(1.0, 0.87, 0.7)
	sun.light_energy = 1.7
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 160.0 if not vr else 90.0
	sun.shadow_blur = 1.2
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)

# ---------------------------------------------------------------- input
func _add_key(action: String, keys: Array) -> void:
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)

func _add_joy_btn(action: String, btn: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	InputMap.action_add_event(action, e)

func _add_joy_axis(action: String, axis: int, dir: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = dir
	InputMap.action_add_event(action, e)

func _setup_input() -> void:
	var defs := {
		"throttle": [KEY_W, KEY_UP], "brake": [KEY_S, KEY_DOWN],
		"steer_left": [KEY_A, KEY_LEFT], "steer_right": [KEY_D, KEY_RIGHT],
		"handbrake": [KEY_SPACE], "reset": [KEY_R], "restart": [KEY_BACKSPACE], "camera": [KEY_C], "lights": [KEY_H],
		"shift_up": [KEY_E], "shift_down": [KEY_Q], "auto_gear": [KEY_M], "help": [KEY_F1], "settings": [KEY_F2],
		"fullscreen": [KEY_F11], "start": [KEY_ENTER, KEY_KP_ENTER, KEY_1, KEY_KP_1], "menu": [KEY_ESCAPE],
	}
	for a in defs.keys():
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.12)
		_add_key(a, defs[a])
	_add_joy_axis("throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_joy_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_btn("handbrake", JOY_BUTTON_A)
	_add_joy_btn("reset", JOY_BUTTON_Y)
	_add_joy_btn("camera", JOY_BUTTON_B)
	_add_joy_btn("shift_up", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_btn("shift_down", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_btn("restart", JOY_BUTTON_BACK)
	_add_joy_btn("start", JOY_BUTTON_START)

func _unhandled_input(event: InputEvent) -> void:
	if hud and event.is_action_pressed("settings"):
		hud.toggle_settings()
		return
	if hud and event.is_action_pressed("help"):
		hud.toggle_controls()
		return
	if hud and hud.menu_open():
		if event.is_action_pressed("start"):
			hud.start()
		return
	if car == null:
		if hud and event.is_action_pressed("menu"):
			hud.close_menu_panels()   # Esc on the start screen: back from a panel to the menu
		return
	if event.is_action_pressed("menu") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START):
		_back_to_menu()
	elif event.is_action_pressed("reset"):
		car.reset_on_track()
	elif event.is_action_pressed("restart"):
		_restart()
	elif event.is_action_pressed("camera") and cam:
		cam.cycle()
	elif event.is_action_pressed("lights"):
		headlights = not headlights
		car.model.set_headlights(headlights)
	elif event.is_action_pressed("shift_up"):
		car.shift(true)
	elif event.is_action_pressed("shift_down"):
		car.shift(false)
	elif event.is_action_pressed("auto_gear"):
		car.auto_gear = true
	elif event.is_action_pressed("help") and hud:
		hud.toggle_help()
	elif event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

# ---------------------------------------------------------------- settings (weather / time)
const SETTINGS_PATH := "user://settings.cfg"

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		envc.time_h = cf.get_value("world", "time", 17.5)
		envc.cycle_time = cf.get_value("world", "cycle_time", false)
		envc.day_minutes = cf.get_value("world", "day_minutes", 10.0)
		envc.set_weather(cf.get_value("world", "weather", 1), true)
		envc.cycle_weather = cf.get_value("world", "cycle_weather", false)
		envc.weather_minutes = cf.get_value("world", "weather_minutes", 3.0)
		grass_quality = int(cf.get_value("world", "grass", 2))
		car_damage = bool(cf.get_value("world", "car_damage", false))
		car_effects = bool(cf.get_value("world", "car_effects", true))
		dmg_engine = bool(cf.get_value("world", "dmg_engine", true))
		dmg_wheels = bool(cf.get_value("world", "dmg_wheels", true))
		wheels_fall = bool(cf.get_value("world", "wheels_fall", true))
		for k in display.keys():
			display[k] = bool(cf.get_value("display", k, true))
	for a in OS.get_cmdline_user_args():   # dev overrides: --weather=4 --time=21 --grass=0..2
		if a.begins_with("--weather="):
			envc.set_weather(int(a.substr(10)), true)
		elif a.begins_with("--time="):
			envc.time_h = float(a.substr(7))
		elif a.begins_with("--grass="):
			grass_quality = int(a.substr(8))
		elif a == "--damage":
			car_damage = true

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("world", "time", envc.time_h)
	cf.set_value("world", "cycle_time", envc.cycle_time)
	cf.set_value("world", "day_minutes", envc.day_minutes)
	cf.set_value("world", "weather", envc.weather)
	cf.set_value("world", "cycle_weather", envc.cycle_weather)
	cf.set_value("world", "weather_minutes", envc.weather_minutes)
	cf.set_value("world", "map", map_choice)
	cf.set_value("world", "biome", biome_name)
	cf.set_value("world", "grass", grass_quality)
	cf.set_value("world", "gi", gi_quality)
	cf.set_value("world", "car_damage", car_damage)
	cf.set_value("world", "car_effects", car_effects)
	cf.set_value("world", "dmg_engine", dmg_engine)
	cf.set_value("world", "dmg_wheels", dmg_wheels)
	cf.set_value("world", "wheels_fall", wheels_fall)
	for k in display.keys():
		cf.set_value("display", k, display[k])
	for b in VOLUME_BUSES:
		cf.set_value("audio", b, volumes[b])
	cf.save(SETTINGS_PATH)

func _notification(what: int) -> void:
	# no sound while the game window is in the background
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, false)
	if what == NOTIFICATION_WM_CLOSE_REQUEST and envc:
		save_settings()   # remembers the clock position when cycling

# start screen: a map was picked - rebuild the scene straight into it
func _pick_map(i: int) -> void:
	map_choice = i
	auto_start = true
	save_settings()
	_safe_reload()

# Leaving a map (or the menu) carefully instead of freeing everything at once
# mid-frame: stop the car and every script, silence all sound, stop particle
# effects, let the renderer finish the frames it's still drawing, free the world
# piece by piece, then load the next scene.
var unloading := false

func _safe_reload() -> void:
	if unloading:
		return                       # Esc pressed twice: one reload is enough
	unloading = true
	if hud and hud.has_method("show_loading"):
		hud.show_loading()
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	for n in _all_nodes(self):
		n.set_process(false)
		n.set_physics_process(false)
		if n is AudioStreamPlayer or n is AudioStreamPlayer3D:
			n.stop()
			n.stream = null
		elif n is GPUParticles3D:
			n.emitting = false
	# the crash sound worker thread must be finished before its node goes
	if car and car.crash_audio:
		var th: Thread = car.crash_audio.thread
		if th and th.is_started():
			th.wait_to_finish()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	# free the world (everything except the loading text), then wait again
	for c in get_children():
		if c != hud:
			c.queue_free()
	car = null
	forest = null
	grass = null
	track = null
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	get_tree().reload_current_scene()

func _all_nodes(root: Node) -> Array:
	var out := []
	for c in root.get_children():
		out.append(c)
		out.append_array(_all_nodes(c))
	return out

func _physics_process(_delta: float) -> void:
	if track and track.endless and car:
		var ts := Time.get_ticks_usec()
		track.update_stream(car.track_idx)
		prof_stream_ms = (Time.get_ticks_usec() - ts) / 1000.0

func _process(_delta: float) -> void:
	if vr_menu_panel:
		_vr_menu_tick(_delta)
		_vr_hands_tick()
		return
	# start screen: slowly look around the forest behind the blur
	if menu_cam:
		menu_cam.rotation.y += _delta * 0.05
		return
	# headlights come on automatically when it gets dark
	if envc and car and envc.dark != was_dark:
		was_dark = envc.dark
		headlights = was_dark
		car.model.set_headlights(headlights)
		if track.has_method("set_night"):
			track.set_night(was_dark)
	if car == null or shot_dir != "":
		return
	if not started:
		car.in_throttle = 0.0
		car.in_brake = 0.0
		car.in_steer = 0.0
		car.in_handbrake = 0.0
		return
	var thr := Input.get_action_strength("throttle")
	var brk := Input.get_action_strength("brake")
	var st := Input.get_axis("steer_left", "steer_right")
	var hb := Input.get_action_strength("handbrake")
	var analog := false
	if Input.get_connected_joypads().size() > 0 and abs(Input.get_joy_axis(0, JOY_AXIS_LEFT_X)) > 0.12:
		analog = true
	if vr and xr_left and xr_right:
		_vr_hands_tick()   # grip on the steering wheel steers (sets car.wheel_hold)
		thr = max(thr, xr_right.get_float("trigger"))
		brk = max(brk, xr_left.get_float("trigger"))
		var stick := xr_left.get_vector2("primary")
		if abs(stick.x) > 0.1:
			st = stick.x
			analog = true
		if xr_right.is_button_pressed("ax_button"):
			hb = 1.0
	car.in_throttle = thr
	car.in_brake = brk
	car.in_steer = st
	car.in_handbrake = hb
	car.in_analog = analog

# ---------------------------------------------------------------- VR
var vr_menu_panel     # the start menu screen (VR only)
var vr_hud_panel      # the driving HUD above the dash (VR only)
var xr_lasers := {}   # controller -> laser mesh (menu only)
var vr_pointer        # the controller that clicks the menu (the last one whose trigger was pulled)

# headset camera + both controllers under `parent`; with `lasers` each controller
# gets a pointer beam for the menu
var xr_cam: XRCamera3D
var xr_eye := Vector3.ZERO      # where the eyes should be, in xr_origin's parent space
var hands := {}                 # controller -> vr_hand.gd
var grabs := {}                 # controller -> {"last", "acc", "w0", "rim"} while holding the wheel
var grip_was := {}              # controller -> grip held last frame (a grab needs a fresh squeeze)
const WHEEL_RATIO := 18.0       # steering ratio: wheel turns 18x the front wheels (matches car_model)
const RIM_R := 0.18             # steering wheel rim radius (car_model)
const VrHand = preload("res://scripts/vr_hand.gd")

# headset camera + both controllers under `parent`, with the eyes at `eye`;
# with `lasers` each controller gets a pointer beam for the menu
func _make_xr_rig(parent: Node3D, eye: Vector3, lasers: bool) -> void:
	xr_eye = eye
	xr_origin = XROrigin3D.new()
	xr_origin.position = eye
	parent.add_child(xr_origin)
	xr_cam = XRCamera3D.new()
	xr_cam.near = 0.03
	xr_cam.far = 2500.0
	xr_origin.add_child(xr_cam)
	xr_cam.current = true
	xr_left = XRController3D.new()
	xr_left.tracker = "left_hand"
	xr_origin.add_child(xr_left)
	xr_right = XRController3D.new()
	xr_right.tracker = "right_hand"
	xr_origin.add_child(xr_right)
	hands.clear()
	grabs.clear()
	for c in [xr_left, xr_right]:
		var xcon: XRController3D = c
		xcon.pose = "aim"   # the hand model is made for the aim pose
		var hand := VrHand.new()
		xcon.add_child(hand)
		hand.build(xcon == xr_left)
		hands[xcon] = hand
		if lasers:
			var beam := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.003, 0.003, 1.0)
			beam.mesh = lm
			var bmat := StandardMaterial3D.new()
			bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bmat.albedo_color = Color(1.0, 0.6, 0.2, 0.7)
			bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			beam.material_override = bmat
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			xcon.add_child(beam)
			xr_lasers[xcon] = beam
	vr_pointer = xr_right
	xr_right.button_pressed.connect(_on_xr_button.bind(false))
	xr_left.button_pressed.connect(_on_xr_button.bind(true))
	# put the eyes in the seat once tracking has started (and again a bit later
	# in case the headset was still waking up)
	get_tree().create_timer(0.6).timeout.connect(_vr_recenter)
	get_tree().create_timer(2.0).timeout.connect(_vr_recenter)

# Recenter: face forward and move the tracking space so the headset is exactly
# at xr_eye. SteamVR reports your real head height above the floor, which used
# to stack on top of the seat height and put you above the car.
func _vr_recenter() -> void:
	if xr_origin == null or not is_instance_valid(xr_origin):
		return
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)
	await get_tree().process_frame
	await get_tree().process_frame
	if xr_origin == null or not is_instance_valid(xr_origin):
		return
	# whatever offset is left (runtimes differ), cancel it out
	xr_origin.position = xr_eye - xr_cam.position

# hands each frame: follow the controllers, or hold the steering wheel rim
func _vr_hands_tick() -> void:
	if hands.is_empty():
		return
	var pivot: Node3D = null
	if car and car.model.steering_wheel:
		pivot = car.model.steering_wheel.get_parent()
	var wheel_now: float = car.model.steering_wheel.rotation.z if car and car.model.steering_wheel else 0.0
	var targets := []
	for c in hands.keys():
		var xcon: XRController3D = c
		var hand = hands[c]
		var grip: float = sim_grip.get(xcon, xcon.get_float("grip"))
		var trig := xcon.get_float("trigger")
		var fresh: bool = grip > 0.6 and not grip_was.get(xcon, false)
		grip_was[xcon] = grip > 0.6
		var free_xf: Transform3D = xcon.global_transform * hand.grip_xf   # where the hand is in your real hand
		if pivot:
			# grab with the fist, not the controller's tip
			var fist: Vector3 = free_xf * (hand.fist_local as Vector3)
			var p: Vector3 = pivot.global_transform.affine_inverse() * fist
			var ang := atan2(p.y, p.x)
			if grabs.has(xcon) and grip < 0.35:
				grabs.erase(xcon)
			elif not grabs.has(xcon) and fresh:
				# close enough to the rim to take hold of it?
				var r := Vector2(p.x, p.y).length()
				if Vector2(r - RIM_R, p.z).length() < 0.14:
					grabs[xcon] = {"last": ang, "acc": 0.0, "w0": wheel_now, "rim": ang - wheel_now}
			if grabs.has(xcon):
				var g: Dictionary = grabs[xcon]
				g["acc"] += wrapf(ang - g["last"], -PI, PI)   # follows the hand past 180 degrees
				g["last"] = ang
				targets.append(g["w0"] + g["acc"])
				# the hand stays on the rim where it grabbed, turning with the wheel
				var a: float = g["rim"] + wheel_now
				var radial := Vector3(cos(a), sin(a), 0)
				var tangent := Vector3(-sin(a), cos(a), 0)
				# fist around the rim: knuckles along the rim, thumb towards the top
				# of the wheel, wrist coming back towards you and slightly outwards
				var hx := -tangent
				var hz := (Vector3(0, 0, 1) + radial * 0.2).normalized()
				var hy := hz.cross(hx)
				# (hx/hy/hz are for a flat palm-down hand; the model is held on its
				# side like a controller, so turn it back by the same quarter roll)
				var s := 1.0 if xcon == xr_left else -1.0
				var hb := Basis(hx, hy, hz) * Basis(Vector3(0, 0, 1), PI / 2 * s).inverse()
				var rim_pt := radial * RIM_R + hz * 0.006
				hand.global_transform = pivot.global_transform * Transform3D(hb, rim_pt - hb * hand.fist_local)
				hand.set_curl(1.0)
				continue
		hand.global_transform = free_xf
		hand.set_curl(grip, trig)
	if car:
		car.wheel_hold = not targets.is_empty()
		if car.wheel_hold:
			var sum := 0.0
			for t in targets:
				sum += t
			var lock: float = car.MAX_STEER * WHEEL_RATIO   # the wheel stops at full lock
			var ang := clampf(sum / targets.size(), -lock, lock)
			car.model.wheel_override = ang
			car.wheel_target = ang / WHEEL_RATIO
		else:
			car.model.wheel_override = NAN

# VR start menu: aim the lasers at the screen, trigger clicks, stick scrolls
var vr_scripted := false

func _vr_menu_tick(delta: float) -> void:
	if vr_menu_panel == null or vr_scripted:
		return
	for c in xr_lasers.keys():
		var xcon: XRController3D = c
		if xcon.get_float("trigger") > 0.6 and xcon != vr_pointer:
			if vr_pointer:
				vr_menu_panel.leave()
			vr_pointer = xcon
	for c in xr_lasers.keys():
		var xcon: XRController3D = c
		var beam: MeshInstance3D = xr_lasers[c]
		var o := xcon.global_position
		var d := -xcon.global_transform.basis.z.normalized()
		var h: Dictionary = vr_menu_panel.hit(o, d)
		var length := 3.0
		if not h.is_empty():
			length = h["dist"]
		beam.scale = Vector3(1, 1, length)
		beam.position = Vector3(0, 0, -length * 0.5)
		beam.visible = xcon == vr_pointer
		if xcon != vr_pointer:
			continue
		if h.is_empty():
			vr_menu_panel.leave()
		else:
			vr_menu_panel.point(h, xcon.get_float("trigger") > 0.6)
			var sy := xcon.get_vector2("primary").y
			if absf(sy) > 0.3:
				vr_scroll_t -= delta
				if vr_scroll_t <= 0.0:
					vr_menu_panel.scroll(signf(sy))
					vr_scroll_t = 0.12
			else:
				vr_scroll_t = 0.0

var vr_scroll_t := 0.0

var sim_grip := {}   # dev aid: controller -> fake grip value (no headset)

func _setup_vr() -> void:
	_make_xr_rig(car.model.body, car.model.driver_eye, false)
	car.model.set_mirrors_active.call_deferred(true)
	if "--vrgrabtest" in OS.get_cmdline_user_args():
		_vr_grab_test()

# dev aid (with --vrsim): both hands take the wheel at 9 and 3 o'clock, turn it
# a quarter turn left, then let go; prints what the car's front wheels did
func _vr_grab_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var pivot: Node3D = car.model.steering_wheel.get_parent()
	var place := func(turn: float):
		for c in [xr_left, xr_right]:
			var a: float = (PI if c == xr_left else 0.0) + turn
			(c as Node3D).global_position = pivot.global_transform * Vector3(cos(a) * RIM_R, sin(a) * RIM_R, 0.02)
	place.call(0.0)
	await get_tree().process_frame
	sim_grip = {xr_left: 1.0, xr_right: 1.0}
	await get_tree().process_frame
	print("GRAB holding=%s grabs=%d" % [car.wheel_hold, grabs.size()])
	for i in 30:
		place.call(PI / 2 * (i + 1) / 30.0)
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	print("GRAB after a quarter turn left: wheel_target %.3f rad, front wheels %.1f deg, steering wheel %.0f deg" % [car.wheel_target, rad_to_deg(car.steer), rad_to_deg(car.model.steering_wheel.rotation.z)])
	# free hands next to the wheel for the picture: left open, right in a fist
	sim_grip = {xr_left: 0.0, xr_right: 0.0}
	await get_tree().process_frame
	for c in [xr_left, xr_right]:
		var side := -1.0 if c == xr_left else 1.0
		(c as Node3D).global_position = pivot.global_transform * Vector3(0.3 * side, 0.02, 0.12)
		(c as Node3D).global_rotation = pivot.global_rotation
	sim_grip = {xr_left: 0.0, xr_right: 0.6}
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--grabshot="):
			get_viewport().get_texture().get_image().save_png(a.substr(11))
	sim_grip = {xr_left: 0.0, xr_right: 0.0}
	await get_tree().create_timer(0.3).timeout
	print("GRAB released: holding=%s" % car.wheel_hold)
	get_tree().quit()
	# floating info panel above the dash
	var info := Label3D.new()
	info.name = "VRInfo"
	info.text = "Grip on the wheel: grab and steer (or L stick)   R trigger: throttle   L trigger: brake   A: handbrake\nB: reset car   X: restart   Y: recenter view   Menu button: back to the menu"
	info.font_size = 32
	info.pixel_size = 0.0012
	info.position = Vector3(-0.37, 1.85, -0.9)
	info.modulate = Color(1, 1, 1, 0.8)
	car.model.body.add_child(info)
	get_tree().create_timer(10.0).timeout.connect(func(): info.visible = false)

func _on_xr_button(name: String, left: bool) -> void:
	if car == null:
		# start menu: Y / stick click / menu recenter the view (the trigger clicks)
		if name in ["by_button", "primary_click", "menu_button"]:
			_vr_recenter()
		return
	if name == "menu_button":
		_back_to_menu()          # menu button: back to the start menu
	elif name == "ax_button" and left:
		_restart()               # X: back to the start line
	elif name == "by_button" and not left:
		car.reset_on_track()     # B: put the car back on the road
	elif (name == "by_button" and left) or name == "primary_click":
		_vr_recenter()   # Y / stick click: recenter

# ---------------------------------------------------------------- screenshots (dev aid)
func _run_screenshots() -> void:
	set_process(false)
	car.model.set_mirrors_active(true)
	for a in OS.get_cmdline_user_args():   # dev aid: --offroad=30 parks the car that far to the side of the road
		if a.begins_with("--offroad="):
			var side := Vector3(cos(car.yaw), 0, -sin(car.yaw))
			var p: Vector3 = car.global_position + side * float(a.substr(10))
			car.global_position = Vector3(p.x, track.ground_h(p.x, p.z) + 0.3, p.z)
			car.vel = Vector3.ZERO
	await get_tree().create_timer(2.5).timeout
	var shots := [
		["chase", 0],
		["side", 1], ["front34", 2], ["rear34", 3], ["top", 4], ["tree", 5], ["road", 6], ["cockpit", 7], ["wheel", 8],
		["overview", 9], ["grass", 10],
	]
	if "--smoketest" in OS.get_cmdline_user_args():
		# dev aid: full tyre smoke and a wrecked, smoking engine before the shots
		car.model.set_damage_enabled(true, car)
		car.force_smoke = true
		car.engine_dmg = 0.85
		car.engine_temp = 1.1
		await get_tree().create_timer(3.5).timeout
	if "--testdents" in OS.get_cmdline_user_args():
		# dev aid: a tree hit on the front-right corner and a guardrail scrape down the right side
		car.model.set_damage_enabled(true, car)
		var tb: Basis = car.global_transform.basis
		var o: Vector3 = car.global_position
		var fw := -tb.z
		var rt := tb.x
		car.model.add_dent(o + fw * 2.0 + rt * 0.75 + Vector3(0, 0.6, 0), -(fw + rt).normalized(), Vector3.UP, 4.0, 0.55, 0.28)
		car.model.add_dent(o + rt * 0.92 + fw * -0.3 + Vector3(0, 0.58, 0), -rt, fw, 1.3, 0.2, 0.1)
	var cam2 := Camera3D.new()
	add_child(cam2)
	for s in shots:
		var n: String = s[0]
		var k: int = s[1]
		var cp: Vector3 = car.global_position
		var b: Basis = car.global_transform.basis
		var fwd := -b.z
		var right := b.x
		cam2.fov = 50.0
		cam.current = false
		cam2.current = true
		match k:
			0:
				cam.current = true
				cam2.current = false
			1:
				cam2.global_position = cp + right * 6.5 + Vector3(0, 0.9, 0)
				cam2.look_at(cp + Vector3(0, 0.6, 0))
			2:
				cam2.global_position = cp + fwd * 5.0 + right * 3.5 + Vector3(0, 1.4, 0)
				cam2.look_at(cp + Vector3(0, 0.55, 0))
			3:
				cam2.global_position = cp - fwd * 5.0 - right * 3.5 + Vector3(0, 1.5, 0)
				cam2.look_at(cp + Vector3(0, 0.6, 0))
			4:
				cam2.global_position = cp + Vector3(0, 9, 0.01)
				cam2.look_at(cp)
			5:
				var tr: Array = forest.trees_near(cp.x, cp.z)
				var best := Vector3(cp.x + 20, 0, cp.z)
				var bd := 1e9
				for t in tr:
					var tv: Vector3 = t
					var d := Vector2(tv.x - cp.x, tv.y - cp.z).length()
					if d < bd and d > 12.0:
						bd = d
						best = Vector3(tv.x, track.terrain_h(tv.x, tv.y), tv.y)
				var dirv := (Vector3(cp.x, best.y, cp.z) - best).normalized()
				cam2.fov = 60.0
				cam2.global_position = best + dirv * 16.0 + Vector3(0, 3.0, 0)
				cam2.look_at(best + Vector3(0, 5.0, 0))
			6:
				cam2.fov = 65.0
				cam2.global_position = cp + fwd * 2.0 + Vector3(0, 3.0, 0)
				cam2.look_at(cp + fwd * 60.0)
			7:
				cam.mode = 2
				cam.current = true
				cam2.current = false
			8:
				cam2.fov = 40.0
				var wp: Vector3 = car.model.wheels[0]["pivot"].global_position
				cam2.global_position = wp + right * 1.4 + fwd * 0.6 + Vector3(0, 0.2, 0)
				cam2.look_at(wp)
			9:
				# high view across the course (hillside: from above the lower tiers)
				cam2.fov = 60.0
				var hill: bool = map_choice == 2
				var oc := Vector3(-40, 0, 95) if hill else cp - fwd * 30.0
				var target := Vector3(110, track.terrain_h(110, -60), -60) if hill else cp + fwd * 120.0
				oc.y = track.terrain_h(oc.x, oc.z) + (14.0 if hill else 38.0)
				if map_choice == 3:
					# Compass Raceway: high above the start straight, looking over the circuit
					oc = Vector3(0, 0, 330)
					oc.y = track.terrain_h(oc.x, oc.z) + 230.0
					target = Vector3(0, 0, -40)
				cam2.global_position = oc
				cam2.look_at(target)
			10:
				# low over the grass beside the road
				cam2.fov = 55.0
				var gp := cp + right * 9.0
				gp.y = track.terrain_h(gp.x, gp.z) + 1.3
				cam2.global_position = gp
				cam2.look_at(gp + right * 6.0 + fwd * 10.0 + Vector3(0, -0.6, 0))
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_dir.path_join(n + ".png"))
		print("saved ", n)
	get_tree().quit()

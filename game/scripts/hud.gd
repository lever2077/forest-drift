# Desktop HUD: speed / gear / tach, drift combo, laps, minimap, help.
extends CanvasLayer

const Profile = preload("res://scripts/profile.gd")
const Updater = preload("res://scripts/updater.gd")

var car
var track
var speed_lbl: Label
var gear_lbl: Label
var tach: ProgressBar
var drift_lbl: Label
var combo_lbl: Label
var score_lbl: Label
var lap_lbl: Label
var msg_lbl: Label
var help_lbl: Label
var perf_lbl: Label
var perf_timer := 0.0
var dmg_lbl: Label
var minimap: Control
var msg_timer := 0.0
var menu: PanelContainer
signal start_pressed

# ---------------------------------------------------------------- controls screen
var controls_panel: PanelContainer

const CONTROLS := {
	"Keyboard": [
		["Throttle", "W  /  Up arrow"],
		["Brake  (hold when stopped = reverse)", "S  /  Down arrow"],
		["Steer", "A  D  /  Left Right arrows"],
		["Handbrake", "Space"],
		["Change camera  (chase / hood / cockpit)", "C"],
		["Reset car onto the road", "R"],
		["Restart from the start line (resets time, repairs damage)", "Backspace"],
		["Back to the map select screen", "Esc"],
		["Headlights", "H"],
		["Manual shift down / up", "Q  /  E"],
		["Back to automatic gears", "M"],
		["Orbit chase camera", "Hold right mouse + drag"],
		["Show / hide this screen", "F1"],
		["Fullscreen", "F11"],
	],
	"Gamepad": [
		["Throttle", "Right trigger"],
		["Brake / reverse", "Left trigger"],
		["Steer", "Left stick"],
		["Handbrake", "A  (Cross)"],
		["Change camera", "B  (Circle)"],
		["Reset car onto the road", "Y  (Triangle)"],
		["Manual shift down / up", "LB  /  RB"],
		["Restart from the start line", "Back / View"],
		["Back to the map select screen", "Start / Menu"],
	],
	"VR": [
		["Throttle", "Right trigger"],
		["Brake / reverse", "Left trigger"],
		["Steer", "Left thumbstick"],
		["Handbrake", "Right grip  or  A"],
		["Reset car onto the road", "B"],
		["Restart from the start line", "X  (left controller)"],
		["Recenter view", "Menu button / stick click"],
	],
	"Drifting tips": [
		["Start a drift", "Turn in, then tap handbrake or stab throttle"],
		["Hold the angle", "Keep some throttle on"],
		["More angle", "Steer further into the turn"],
		["Straighten up", "Countersteer or lift off the throttle"],
		["Scoring", "Slide on the road above 10 degrees"],
		["Combo multiplier", "Rises the longer you hold the drift"],
		["Air time", "Hit crests fast (90+ km/h) - points for every jump"],
		["Lose the combo", "Leaving the road or hitting a tree"],
		["Cache points", "Each lap: lap score x time bonus (faster = more, x0.25 - x3)"],
		["Endless Road points", "Paid out every kilometre the same way"],
	],
}

func build_controls() -> void:
	controls_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.06, 0.92)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1.0, 0.6, 0.2, 0.5)
	sb.set_border_width_all(2)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	controls_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	controls_panel.add_child(v)
	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	v.add_child(title)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(800, 520)
	tabs.add_theme_font_size_override("font_size", 20)
	for tab_name in CONTROLS.keys():
		var grid := GridContainer.new()
		grid.name = tab_name
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 40)
		grid.add_theme_constant_override("v_separation", 8)
		for row in CONTROLS[tab_name]:
			var a := Label.new()
			a.text = row[0]
			a.add_theme_font_size_override("font_size", 19)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(a)
			var b := Label.new()
			b.text = row[1]
			b.add_theme_font_size_override("font_size", 19)
			b.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
			grid.add_child(b)
		var margin := MarginContainer.new()
		margin.name = tab_name
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 16)
		grid.name = "Grid"
		margin.add_child(grid)
		tabs.add_child(margin)
	v.add_child(tabs)
	var close := Button.new()
	close.text = "Close  (F1)"
	close.add_theme_font_size_override("font_size", 20)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_controls)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)
	controls_panel.visible = false
	add_child(controls_panel)
	_layout()

# ---------------------------------------------------------------- settings: weather / time
var settings_panel: PanelContainer
var settings_tabs: TabContainer
var envc
var main_node
var time_slider: HSlider
var clock_lbl: Label
var weather_opt: OptionButton
var cycle_time_chk: CheckBox
var cycle_weather_chk: CheckBox
const DAY_LENGTHS := [2.0, 5.0, 10.0, 20.0, 40.0]
const WEATHER_TIMES := [1.0, 3.0, 5.0, 10.0]

func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	parent.add_child(l)

func _row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	parent.add_child(h)
	return h

func _opt(items: Array, fmt: String, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(fmt % it if fmt != "" else str(it))
	o.select(selected)
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 18)
	return o

const DISPLAY_ITEMS := [
	["fps", "Frame rate  (FPS and frame time)"],
	["ping", "Ping"],
	["engine", "Engine status  (health, temperature)"],
	["tyres", "Tyre / wheel status  (one line per wheel)"],
	["minimap", "Minimap"],
]

const VOLUME_ITEMS := [
	["Master", "Master"],
	["Engine", "Engine"],
	["Tyres", "Tyre squeal"],
	["Effects", "Crashes / impacts"],
	["Music", "Music"],
]

# an indented checkbox row (a sub-setting of the one above it)
func _sub_check(parent: Control, indent: float, text: String, on: bool) -> CheckBox:
	var r := _row(parent)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(indent, 0)
	r.add_child(pad)
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = on
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_font_size_override("font_size", 16)
	r.add_child(cb)
	return cb

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var m := MarginContainer.new()
	m.name = title
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)
	tabs.add_child(m)
	return vb

func build_settings(p_envc, p_main) -> void:
	envc = p_envc
	main_node = p_main
	settings_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.06, 0.92)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1.0, 0.6, 0.2, 0.5)
	sb.set_border_width_all(2)
	for side in ["left", "right"]:
		sb.set("content_margin_" + side, 30)
	for side in ["top", "bottom"]:
		sb.set("content_margin_" + side, 22)
	settings_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	settings_panel.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	v.add_child(title)
	# tabs: World (time + weather), Graphics, Car, Display
	var tabs := TabContainer.new()
	tabs.add_theme_font_size_override("font_size", 19)
	tabs.custom_minimum_size = Vector2(640, 0)
	v.add_child(tabs)
	var t_world := _tab(tabs, "World")
	var t_gfx := _tab(tabs, "Graphics")
	var t_car := _tab(tabs, "Car")
	var t_disp := _tab(tabs, "Display")
	var t_audio := _tab(tabs, "Audio")
	settings_tabs = tabs
	# --- time of day
	_section(t_world, "Time of day")
	var r1 := _row(t_world)
	time_slider = HSlider.new()
	time_slider.min_value = 0.0
	time_slider.max_value = 24.0
	time_slider.step = 0.25
	time_slider.value = envc.time_h
	time_slider.custom_minimum_size = Vector2(420, 30)
	time_slider.focus_mode = Control.FOCUS_NONE
	time_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(time_slider)
	clock_lbl = Label.new()
	clock_lbl.add_theme_font_size_override("font_size", 24)
	clock_lbl.custom_minimum_size = Vector2(80, 0)
	r1.add_child(clock_lbl)
	var r1b := _row(t_world)
	for preset in [["Dawn", 6.0], ["Morning", 9.0], ["Noon", 12.5], ["Sunset", 18.0], ["Night", 22.0]]:
		var b := Button.new()
		b.text = preset[0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		var hr: float = preset[1]
		b.pressed.connect(func(): time_slider.value = hr)
		r1b.add_child(b)
	var r2 := _row(t_world)
	cycle_time_chk = CheckBox.new()
	cycle_time_chk.text = "Cycle day / night"
	cycle_time_chk.button_pressed = envc.cycle_time
	cycle_time_chk.focus_mode = Control.FOCUS_NONE
	cycle_time_chk.add_theme_font_size_override("font_size", 18)
	r2.add_child(cycle_time_chk)
	var dl := Label.new()
	dl.text = "full day takes"
	dl.add_theme_font_size_override("font_size", 18)
	r2.add_child(dl)
	var day_opt := _opt(DAY_LENGTHS, "%d min", max(DAY_LENGTHS.find(envc.day_minutes), 2))
	r2.add_child(day_opt)
	# --- weather
	_section(t_world, "Weather")
	var r3 := _row(t_world)
	weather_opt = _opt(envc.WEATHERS, "", envc.weather)
	weather_opt.custom_minimum_size = Vector2(200, 0)
	r3.add_child(weather_opt)
	var r4 := _row(t_world)
	cycle_weather_chk = CheckBox.new()
	cycle_weather_chk.text = "Cycle weather"
	cycle_weather_chk.button_pressed = envc.cycle_weather
	cycle_weather_chk.focus_mode = Control.FOCUS_NONE
	cycle_weather_chk.add_theme_font_size_override("font_size", 18)
	r4.add_child(cycle_weather_chk)
	var wl := Label.new()
	wl.text = "change every"
	wl.add_theme_font_size_override("font_size", 18)
	r4.add_child(wl)
	var wt_opt := _opt(WEATHER_TIMES, "%d min", max(WEATHER_TIMES.find(envc.weather_minutes), 1))
	r4.add_child(wt_opt)
	# --- graphics
	_section(t_gfx, "Graphics")
	var r5 := _row(t_gfx)
	var gl := Label.new()
	gl.text = "Grass"
	gl.add_theme_font_size_override("font_size", 18)
	r5.add_child(gl)
	var grass_opt := _opt(["Off", "Low", "High"], "", clampi(main_node.grass_quality, 0, 2))
	grass_opt.custom_minimum_size = Vector2(140, 0)
	grass_opt.item_selected.connect(func(i): main_node.set_grass(i))
	r5.add_child(grass_opt)
	# --- car
	_section(t_car, "Car")
	var r6 := _row(t_car)
	var dmg := CheckBox.new()
	dmg.text = "Car damage  (body crumples, parts fall off, glass breaks - Backspace repairs)"
	dmg.button_pressed = main_node.car_damage
	dmg.focus_mode = Control.FOCUS_NONE
	dmg.add_theme_font_size_override("font_size", 18)
	r6.add_child(dmg)
	# sub-setting: whether the damage also breaks the car mechanically
	var r7 := _row(t_car)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(28, 0)
	r7.add_child(pad)
	var fx := CheckBox.new()
	fx.text = "Effects  (engine, wheels, suspension and axles can break and change the handling)"
	fx.button_pressed = main_node.car_effects
	fx.disabled = not main_node.car_damage
	fx.focus_mode = Control.FOCUS_NONE
	fx.add_theme_font_size_override("font_size", 16)
	r7.add_child(fx)
	# Effects > what can break: the engine, the wheels (and whether they come off)
	var eng_chk := _sub_check(t_car, 56, "Engine damage  (overheating, limp mode, engine dies)", main_node.dmg_engine)
	var whl_chk := _sub_check(t_car, 56, "Wheel damage  (bent wheels pull, broken axles, lost steering)", main_node.dmg_wheels)
	var fall_chk := _sub_check(t_car, 84, "Wheels fall off  (a fully broken wheel tears off and rolls away)", main_node.wheels_fall)
	var refresh := func():
		var fx_ok: bool = main_node.car_damage and main_node.car_effects
		fx.disabled = not main_node.car_damage
		eng_chk.disabled = not fx_ok
		whl_chk.disabled = not fx_ok
		fall_chk.disabled = not (fx_ok and main_node.dmg_wheels)
	refresh.call()
	dmg.toggled.connect(func(on):
		main_node.set_car_damage(on)
		refresh.call())
	fx.toggled.connect(func(on):
		main_node.set_car_effects(on)
		refresh.call())
	eng_chk.toggled.connect(func(on): main_node.set_mech_option("engine", on))
	whl_chk.toggled.connect(func(on):
		main_node.set_mech_option("wheels", on)
		refresh.call())
	fall_chk.toggled.connect(func(on): main_node.set_mech_option("fall", on))
	# --- display: what the HUD shows while driving
	_section(t_disp, "On-screen info")
	for item in DISPLAY_ITEMS:
		var key: String = item[0]
		var cb := CheckBox.new()
		cb.text = item[1]
		cb.button_pressed = bool(main_node.display.get(key, true))
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 18)
		cb.toggled.connect(func(on): main_node.set_display(key, on))
		t_disp.add_child(cb)
	var note := Label.new()
	note.text = "Engine and tyre status appear when Car damage and Effects are on."
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.75, 0.78, 0.75))
	t_disp.add_child(note)
	# --- audio: one slider per sound bus
	_section(t_audio, "Volume")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	t_audio.add_child(grid)
	for item in VOLUME_ITEMS:
		var bus: String = item[0]
		var nl := Label.new()
		nl.text = item[1]
		nl.custom_minimum_size = Vector2(150, 0)
		nl.add_theme_font_size_override("font_size", 18)
		if bus == "Master":
			nl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		grid.add_child(nl)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 1
		sl.value = round(float(main_node.volumes.get(bus, 1.0)) * 100.0)
		sl.custom_minimum_size = Vector2(340, 30)
		sl.focus_mode = Control.FOCUS_NONE
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(sl)
		var pl := Label.new()
		pl.custom_minimum_size = Vector2(60, 0)
		pl.add_theme_font_size_override("font_size", 18)
		pl.text = "%d%%" % int(sl.value)
		grid.add_child(pl)
		sl.value_changed.connect(func(val):
			pl.text = "%d%%" % int(val)
			main_node.set_volume(bus, val / 100.0))
	var anote := Label.new()
	anote.text = "Master scales everything. Music has no tracks yet."
	anote.add_theme_font_size_override("font_size", 15)
	anote.add_theme_color_override("font_color", Color(0.75, 0.78, 0.75))
	t_audio.add_child(anote)
	var close := Button.new()
	close.text = "Close  (F2)"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(toggle_settings)
	v.add_child(close)
	# --- wiring
	time_slider.value_changed.connect(func(h):
		envc.set_time(h)
		clock_lbl.text = envc.clock_text()
		main_node.save_settings())
	cycle_time_chk.toggled.connect(func(on):
		envc.cycle_time = on
		main_node.save_settings())
	day_opt.item_selected.connect(func(i):
		envc.day_minutes = DAY_LENGTHS[i]
		main_node.save_settings())
	weather_opt.item_selected.connect(func(i):
		envc.set_weather(i)
		main_node.save_settings())
	cycle_weather_chk.toggled.connect(func(on):
		envc.cycle_weather = on
		main_node.save_settings())
	wt_opt.item_selected.connect(func(i):
		envc.weather_minutes = WEATHER_TIMES[i]
		main_node.save_settings())
	envc.time_changed.connect(func(h):
		time_slider.set_value_no_signal(h)
		clock_lbl.text = envc.clock_text())
	envc.weather_changed.connect(func(i): weather_opt.select(i))
	clock_lbl.text = envc.clock_text()
	settings_panel.visible = false
	add_child(settings_panel)
	apply_display()
	_layout()

func toggle_settings() -> void:
	if settings_panel:
		settings_panel.visible = not settings_panel.visible
		settings_panel.move_to_front()   # above the start menu, or its tabs can't be clicked
		_layout()

func toggle_controls() -> void:
	if controls_panel:
		controls_panel.visible = not controls_panel.visible
		controls_panel.move_to_front()
		_layout()

# ---------------------------------------------------------------- start menu: pick a map
signal map_picked(index: int)
var menu_entries := []
var menu_current := 0
var menu_status: Label
var menu_busy := false

func build_menu(entries: Array, current: int) -> void:
	menu_entries = entries
	menu_current = current
	menu = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.05, 0.86)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	menu.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	menu.add_child(v)
	var title := Label.new()
	title.text = "FOREST DRIFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	v.add_child(title)
	menu_status = Label.new()
	menu_status.text = "Choose a map   (Enter drives the last one you played,  Esc while driving comes back here)"
	menu_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_status.add_theme_font_size_override("font_size", 18)
	v.add_child(menu_status)
	var first_btn: Button = null
	for e in entries:
		var idx: int = e["index"]
		var b := Button.new()
		var mark := "   (last played)" if idx == current else ""
		b.text = "%s%s\n%s" % [String(e["name"]).to_upper(), mark, e["info"]]
		b.custom_minimum_size = Vector2(600, 74)
		b.add_theme_font_size_override("font_size", 21)
		if idx == current:
			b.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		v.add_child(b)
		if first_btn == null or idx == current:
			first_btn = b
		b.pressed.connect(func(): _pick(idx, e["name"]))
	var row := _row(v)
	menu_vbox = v
	menu_tools_row = row
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var cfg := Button.new()
	cfg.text = "Controls  (F1)"
	cfg.custom_minimum_size = Vector2(290, 44)
	cfg.add_theme_font_size_override("font_size", 19)
	cfg.pressed.connect(toggle_controls)
	row.add_child(cfg)
	var st := Button.new()
	st.text = "Settings  (F2)"
	st.custom_minimum_size = Vector2(290, 44)
	st.add_theme_font_size_override("font_size", 19)
	st.pressed.connect(toggle_settings)
	row.add_child(st)
	# second row: spend points / see what you own
	var row2 := _row(v)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	var cache_btn := Button.new()
	cache_btn.text = "Cache"
	cache_btn.custom_minimum_size = Vector2(290, 44)
	cache_btn.add_theme_font_size_override("font_size", 19)
	cache_btn.pressed.connect(func(): _toggle_shop_panel(cache_panel))
	row2.add_child(cache_btn)
	var inv_btn := Button.new()
	inv_btn.text = "Inventory"
	inv_btn.custom_minimum_size = Vector2(290, 44)
	inv_btn.add_theme_font_size_override("font_size", 19)
	inv_btn.pressed.connect(func(): _toggle_shop_panel(inventory_panel))
	row2.add_child(inv_btn)
	menu_points_lbl = Label.new()
	menu_points_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_points_lbl.add_theme_font_size_override("font_size", 20)
	menu_points_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	v.add_child(menu_points_lbl)
	_refresh_points()
	# update button: checks GitHub on its own when the menu opens
	var row3 := _row(v)
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	update_btn = Button.new()
	update_btn.text = "Check for updates"
	update_btn.custom_minimum_size = Vector2(290, 40)
	update_btn.add_theme_font_size_override("font_size", 18)
	row3.add_child(update_btn)
	update_lbl = Label.new()
	update_lbl.add_theme_font_size_override("font_size", 16)
	update_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	update_lbl.custom_minimum_size = Vector2(300, 0)
	row3.add_child(update_lbl)
	updater = Updater.new()
	add_child(updater)
	updater.status_changed.connect(_on_update_status)
	update_btn.pressed.connect(func():
		if updater.update_available():
			updater.install()
		else:
			Updater.checked = false   # ask GitHub again
			updater.check())
	updater.check()
	add_child(menu)
	cache_panel = _build_shop_panel("CACHE")
	inventory_panel = _build_shop_panel("INVENTORY")
	_layout()
	if first_btn:
		first_btn.grab_focus()

# ---------------------------------------------------------------- start menu: cache + inventory
var cache_panel: PanelContainer
var inventory_panel: PanelContainer
var menu_points_lbl: Label
var updater
var update_btn: Button
var update_lbl: Label

func _on_update_status(text: String, can_install: bool) -> void:
	update_lbl.text = text
	update_btn.disabled = updater.busy
	if updater.update_available():
		update_btn.text = "Update to %s" % Updater.latest_tag
		update_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		if "--autoupdate" in OS.get_cmdline_user_args() and not updater.busy:
			updater.install.call_deferred()   # dev aid: test the whole update flow
	else:
		update_btn.text = "Check for updates"
		update_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	_layout()

func _refresh_points() -> void:
	Profile.load_profile()
	if menu_points_lbl:
		menu_points_lbl.text = "POINTS  %d" % Profile.points

func _build_shop_panel(title_text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.06, 1.0)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1.0, 0.6, 0.2, 0.5)
	sb.set_border_width_all(2)
	for side in ["left", "right"]:
		sb.set("content_margin_" + side, 28)
	for side in ["top", "bottom"]:
		sb.set("content_margin_" + side, 20)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	v.add_child(title)
	var pts := Label.new()
	pts.name = "Points"
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts.add_theme_font_size_override("font_size", 20)
	pts.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	v.add_child(pts)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var close := Button.new()
	close.text = "Close"
	close.add_theme_font_size_override("font_size", 20)
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): _toggle_shop_panel(p))
	v.add_child(close)
	p.visible = false
	add_child(p)
	p.set_meta("list", list)
	p.set_meta("points", pts)
	return p

func _toggle_shop_panel(p: PanelContainer) -> void:
	if p == null:
		return
	var want := not p.visible
	for other in [cache_panel, inventory_panel]:
		if other:
			other.visible = false
	p.visible = want
	p.move_to_front()
	if want:
		_fill_shop_panel(p)
	_layout()

func _empty_note(list: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.75))
	list.add_child(l)

func _item_row(list: VBoxContainer, it: Dictionary, right: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 14)
	list.add_child(r)
	var l := Label.new()
	l.text = String(it.get("name", it.get("id", "?")))
	if it.has("info"):
		l.text += "\n" + String(it["info"])
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 18)
	r.add_child(l)
	var rl := Label.new()
	rl.text = right
	rl.add_theme_font_size_override("font_size", 18)
	rl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	r.add_child(rl)
	return r

func _fill_shop_panel(p: PanelContainer) -> void:
	_refresh_points()
	(p.get_meta("points") as Label).text = "POINTS  %d" % Profile.points
	var list: VBoxContainer = p.get_meta("list")
	for c in list.get_children():
		c.queue_free()
	if p == cache_panel:
		if Profile.CACHE_ITEMS.is_empty():
			_empty_note(list, "Nothing for sale yet - check back later.")
		for it in Profile.CACHE_ITEMS:
			var id: String = it["id"]
			var price := int(it["price"])
			var owned := Profile.item_count(id)
			var r := _item_row(list, it, "%d pts" % price + ("   (owned %d)" % owned if owned > 0 else ""))
			var b := Button.new()
			b.text = "Buy"
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(90, 0)
			b.add_theme_font_size_override("font_size", 18)
			b.disabled = Profile.points < price
			b.pressed.connect(func():
				if Profile.buy(id):
					_fill_shop_panel(p))
			r.add_child(b)
	else:
		if Profile.inventory.is_empty():
			_empty_note(list, "Your inventory is empty. Earn points and spend them in the Cache.")
		for id in Profile.inventory.keys():
			var it := Profile.find_item(id)
			if it.is_empty():
				it = {"id": id, "name": id}
			_item_row(list, it, "x%d" % int(Profile.inventory[id]))

# start menu: the biome every map is dressed in (looks only, driving is the same)
var menu_vbox: VBoxContainer
var menu_tools_row: HBoxContainer
var biome_info: Label

func build_biome_picker(names: Array, infos: Array, current: String, main_node) -> void:
	if menu_vbox == null:
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = "BIOME"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	box.add_child(head)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	biome_info = Label.new()
	biome_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	biome_info.add_theme_font_size_override("font_size", 16)
	biome_info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	box.add_child(biome_info)
	var group := ButtonGroup.new()
	for i in names.size():
		var nm: String = names[i]
		var info: String = infos[i]
		var b := Button.new()
		b.text = nm
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_pressed_color", Color(0.6, 1.0, 0.6))
		row.add_child(b)
		if nm == current:
			b.button_pressed = true
			biome_info.text = _biome_text(nm, info)
		b.pressed.connect(func():
			biome_info.text = _biome_text(nm, info)
			main_node.set_biome(nm))
	menu_vbox.add_child(box)
	menu_vbox.move_child(box, menu_tools_row.get_index())
	_layout()

func _biome_text(nm: String, info: String) -> String:
	var t := info
	if nm == "Stadium":
		t += "   (race tracks only: Endless Road stays in the forest)"
	return t

func _pick(idx: int, name: String) -> void:
	if menu_busy:
		return
	menu_busy = true
	menu_status.text = "Loading %s ..." % name
	await get_tree().process_frame
	await get_tree().process_frame
	map_picked.emit(idx)

# Enter / Start on the menu: drive the highlighted (last played) map
func start() -> void:
	if menu == null or not menu.visible:
		return
	for e in menu_entries:
		if e["index"] == menu_current:
			_pick(menu_current, e["name"])

func _update_damage_readout() -> void:
	if dmg_lbl == null:
		return
	if not car.model.damage_enabled or not car.mech_on or not (_show("engine") or _show("tyres")):
		dmg_lbl.text = ""
		return
	var eng: float = car.engine_dmg
	var lines := []
	if _show("engine"):
		var t := "ENGINE   %d%%" % int(round((1.0 - eng) * 100.0))
		if eng > 0.97:
			t += "  DEAD"
		elif car.engine_temp > 1.0:
			t += "  OVERHEATING (limp)"
		elif car.engine_temp > 0.6:
			t += "  hot"
		lines.append(t)
	# one wheel per line
	var names := ["Front left ", "Front right", "Rear left  ", "Rear right "]
	var worst := eng
	for i in 4:
		var d: float = car.wheel_dmg[i]
		worst = max(worst, d)
		if _show("tyres"):
			var s := "ok" if d < 0.15 else ("bent" if d < 0.7 else "BROKEN")
			if car.wheel_off[i]:
				s = "TORN OFF"
			lines.append("%s   %3d%%   %s" % [names[i], int(round((1.0 - d) * 100.0)), s])
	if car.axle_broken[0] or car.axle_broken[1]:
		lines.append("AXLE BROKEN")
	dmg_lbl.text = "\n".join(lines)
	var c := Color(0.6, 1.0, 0.6) if worst < 0.3 else (Color(1.0, 0.8, 0.3) if worst < 0.7 else Color(1.0, 0.4, 0.3))
	dmg_lbl.add_theme_color_override("font_color", c)

# Display tab: is this readout switched on?
func _show(key: String) -> bool:
	if main_node == null or not ("display" in main_node):
		return true
	return bool(main_node.display.get(key, true))

func apply_display() -> void:
	if minimap and track:
		minimap.visible = not track.endless and _show("minimap")
	perf_timer = 0.0

func menu_open() -> bool:
	return menu != null and menu.visible

class Minimap extends Control:
	var track
	var car
	var pts2: PackedVector2Array
	var bmin: Vector2
	var scale_k := 1.0
	func setup(t, c) -> void:
		track = t
		car = c
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for p in track.pts:
			mn.x = min(mn.x, p.x)
			mn.y = min(mn.y, p.z)
			mx.x = max(mx.x, p.x)
			mx.y = max(mx.y, p.z)
		bmin = mn
		scale_k = (size.x - 20.0) / max(mx.x - mn.x, mx.y - mn.y)
		pts2 = PackedVector2Array()
		for i in range(0, track.pts.size(), 4):
			pts2.append(_map(track.pts[i]))
		pts2.append(pts2[0])
	func _map(p: Vector3) -> Vector2:
		return Vector2(10, 10) + (Vector2(p.x, p.z) - bmin) * scale_k
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
		if pts2.size() > 1:
			draw_polyline(pts2, Color(0.9, 0.9, 0.9, 0.85), 3.0, true)
			draw_circle(_map(track.pts[0]), 4.0, Color(1, 0.6, 0.1))
		if car:
			var cp: Vector2 = _map(car.global_position)
			var f := Vector2(-sin(car.yaw), -cos(car.yaw))
			var r := Vector2(-f.y, f.x)
			draw_colored_polygon(PackedVector2Array([cp + f * 8.0, cp - f * 5.0 + r * 5.0, cp - f * 5.0 - r * 5.0]), Color(1.0, 0.35, 0.1))

func _mk_label(size: int, pos: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.position = pos
	l.horizontal_alignment = align
	add_child(l)
	return l

func setup(p_car, p_track) -> void:
	car = p_car
	track = p_track
	car.drift_banked.connect(_on_banked)
	car.drift_failed.connect(_on_failed)
	car.lap_completed.connect(_on_lap)
	car.points_earned.connect(_on_points)
	car.air_landed.connect(func(t, pts): _flash("AIR  %.1fs   +%d" % [t, pts], Color(0.5, 0.9, 1.0)))
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	speed_lbl = _mk_label(64, Vector2(0, 0), HORIZONTAL_ALIGNMENT_RIGHT)
	gear_lbl = _mk_label(40, Vector2(0, 0), HORIZONTAL_ALIGNMENT_RIGHT)
	tach = ProgressBar.new()
	tach.min_value = 0
	tach.max_value = 7600
	tach.show_percentage = false
	tach.custom_minimum_size = Vector2(300, 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.45, 0.1)
	tach.add_theme_stylebox_override("fill", sb)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	tach.add_theme_stylebox_override("background", bg)
	add_child(tach)
	drift_lbl = _mk_label(48, Vector2(0, 60), HORIZONTAL_ALIGNMENT_CENTER)
	combo_lbl = _mk_label(26, Vector2(0, 118), HORIZONTAL_ALIGNMENT_CENTER)
	score_lbl = _mk_label(26, Vector2(24, 20))
	lap_lbl = _mk_label(22, Vector2(24, 56))
	msg_lbl = _mk_label(38, Vector2(0, 180), HORIZONTAL_ALIGNMENT_CENTER)
	points_lbl = _mk_label(26, Vector2(0, 228), HORIZONTAL_ALIGNMENT_CENTER)
	points_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	points_lbl.visible = false
	help_lbl = _mk_label(18, Vector2(24, 92))
	help_lbl.text = "F1  Controls     F2  Settings"
	# frame rate / frame time / ping readout
	perf_lbl = _mk_label(17, Vector2(24, 120))
	# car damage readout (only with Car damage on)
	dmg_lbl = _mk_label(17, Vector2(24, 146))
	dmg_lbl.size = Vector2(700, 150)
	minimap = Minimap.new()
	minimap.size = Vector2(230, 230)
	add_child(minimap)
	minimap.setup(track, car)
	minimap.visible = not track.endless
	build_controls()
	apply_display()
	_layout()
	get_viewport().size_changed.connect(_layout)

# start screen only: blurred view behind, the map list, controls and settings
# shown while a scene is being unloaded (Esc to the menu / picking a map)
func show_loading() -> void:
	for c in get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.04, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var l := Label.new()
	l.text = "Loading..."
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(l)

func setup_menu_screen() -> void:
	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	// soft blur: average a few samples from a low mip level
	vec2 px = SCREEN_PIXEL_SIZE * 6.0;
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.2).rgb * 0.4;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), 3.6).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), 3.6).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), 3.6).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), 3.6).rgb * 0.15;
	COLOR = vec4(c * 0.85, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	blur.material = m
	add_child(blur)
	build_controls()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	if speed_lbl:
		speed_lbl.position = Vector2(vs.x - 340, vs.y - 150)
		speed_lbl.size = Vector2(300, 70)
		gear_lbl.position = Vector2(vs.x - 340, vs.y - 205)
		gear_lbl.size = Vector2(300, 50)
		tach.position = Vector2(vs.x - 340, vs.y - 70)
		for l in [drift_lbl, combo_lbl, msg_lbl, points_lbl]:
			l.position.x = 0
			l.size = Vector2(vs.x, 60)
		minimap.position = Vector2(vs.x - 254, 24)
	if menu:
		menu.reset_size()
		menu.position = (vs - menu.size) * 0.5
	if controls_panel:
		controls_panel.reset_size()
		controls_panel.position = (vs - controls_panel.size) * 0.5
	for sp in [cache_panel, inventory_panel]:
		if sp:
			sp.reset_size()
			sp.position = (vs - sp.size) * 0.5
	if settings_panel:
		settings_panel.reset_size()
		settings_panel.position = Vector2(24, vs.y - settings_panel.size.y - 24)

func toggle_help() -> void:
	toggle_controls()

func _flash(t: String, c: Color) -> void:
	msg_lbl.text = t
	msg_lbl.add_theme_color_override("font_color", c)
	msg_timer = 2.0

func _on_banked(p: int) -> void:
	_flash("+%d" % p, Color(1.0, 0.75, 0.2))

func _on_failed() -> void:
	_flash("DRIFT LOST", Color(1.0, 0.25, 0.2))

func _on_lap(t: float, best: float) -> void:
	_flash("LAP  %s   BEST %s" % [fmt_time(t), fmt_time(best)], Color(0.6, 1.0, 0.6))

# lap paid out: shown under the lap time message
var points_lbl: Label
var points_timer := 0.0

func _on_points(lap_score: int, mult: float, pts: int) -> void:
	if points_lbl == null:
		return
	var what := "KM" if track.endless else "LAP"
	points_lbl.text = "%s SCORE %d  x%.2f time bonus  =  +%d POINTS" % [what, lap_score, mult, pts]
	points_timer = 4.0

static func fmt_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := fmod(t, 60.0)
	return "%d:%06.3f" % [m, s]

func _process(delta: float) -> void:
	if car == null:
		return
	# FPS readout, refreshed 4 times a second: green 60+, yellow 30-60, red below
	perf_timer -= delta
	if perf_lbl and perf_timer <= 0.0:
		perf_timer = 0.25
		var fps := Engine.get_frames_per_second()
		var parts := []
		if _show("fps"):
			parts.append("FPS %d   |   %.1f ms" % [fps, 1000.0 / max(fps, 1.0)])
		if _show("ping"):
			parts.append("Ping: offline (single-player)")
		perf_lbl.text = "   |   ".join(parts)
		perf_lbl.visible = not parts.is_empty()
		dmg_lbl.position.y = 146.0 if perf_lbl.visible else 120.0
		var col := Color(0.55, 1.0, 0.55) if fps >= 60 else (Color(1.0, 0.85, 0.3) if fps >= 30 else Color(1.0, 0.4, 0.3))
		perf_lbl.add_theme_color_override("font_color", col)
		_update_damage_readout()
	var kmh: float = car.speed * 3.6
	speed_lbl.text = "%d km/h" % int(kmh)
	var g := "R" if car.gear == -1 else str(car.gear)
	gear_lbl.text = ("" if car.auto_gear else "M ") + g
	tach.value = car.rpm
	if car.drift_points > 0.0:
		drift_lbl.text = "%d" % int(car.drift_points)
		combo_lbl.text = "DRIFT  x%d   %d°" % [car.drift_mult, int(rad_to_deg(abs(car.body_slip)))]
	else:
		drift_lbl.text = ""
		combo_lbl.text = ""
	score_lbl.text = "SCORE  %d     BEST COMBO  %d     POINTS  %d" % [car.total_score, car.best_combo, Profile.points]
	points_timer -= delta
	points_lbl.visible = points_timer > 0.0
	if track.endless:
		lap_lbl.text = "ENDLESS ROAD   %.2f km" % (car.odometer / 1000.0)
	else:
		lap_lbl.text = "LAP %d   %s   BEST %s" % [car.laps + 1, fmt_time(car.lap_time), fmt_time(car.best_lap) if car.best_lap > 0 else "--"]
	if envc:
		lap_lbl.text += "      %s  %s" % [envc.clock_text(), envc.WEATHERS[envc.weather]]
	msg_timer -= delta
	# on its roof / side: it stays there until the driver resets it
	if car.flipped_time > 1.5 and msg_timer <= 0.0:
		msg_lbl.text = "UPSIDE DOWN  -  press R to put the car back on the road"
		msg_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
		msg_timer = 0.1
	msg_lbl.visible = msg_timer > 0.0
	# in-car display (visible in cockpit view and VR)
	car.model.dash_label.text = "%d  %s\n%d" % [int(kmh), g, int(car.drift_points) if car.drift_points > 0 else car.total_score]

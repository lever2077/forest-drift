# Desktop HUD: speed / gear / tach, drift combo, laps, minimap, help.
extends CanvasLayer

const Profile = preload("res://scripts/profile.gd")
const Updater = preload("res://scripts/updater.gd")
const Gfx = preload("res://scripts/gfx.gd")
const CrateRoll = preload("res://scripts/crate_roll.gd")
const CarDamage = preload("res://scripts/car_damage.gd")

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
var vr_mode := false   # drawn on a screen in VR (set before setup)
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
		["Repair the car (Endless Road: right where you are; other maps: back to the start line)", "Backspace"],
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
		["Grab the steering wheel and steer", "Grip  (hand on the rim)"],
		["Handbrake", "A"],
		["Reset car onto the road", "B"],
		["Restart from the start line", "X  (left controller)"],
		["Recenter view", "Y  /  stick click"],
		["Back to the menu", "Menu button  (left controller)"],
		["Click on the menu", "Point a controller, pull the trigger"],
		["Scroll a list", "Thumbstick up / down"],
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

# Settings > Codes: type a code, press Redeem (or Enter). Each code works once
# per save (profile.gd CODES / redeem_code).
var code_edit: LineEdit

func _build_codes_tab(t: VBoxContainer) -> void:
	_section(t, "Codes")
	var r := _row(t)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "Enter a code"
	code_edit.custom_minimum_size = Vector2(320, 44)
	code_edit.add_theme_font_size_override("font_size", 20)
	r.add_child(code_edit)
	var b := Button.new()
	b.text = "Redeem"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(130, 44)
	b.add_theme_font_size_override("font_size", 20)
	r.add_child(b)
	var msg := Label.new()
	msg.add_theme_font_size_override("font_size", 18)
	t.add_child(msg)
	var redeem := func(_t = ""):
		var res: Array = Profile.redeem_code(code_edit.text)
		msg.text = res[1]
		msg.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if res[0] else Color(1.0, 0.5, 0.4))
		if res[0]:
			code_edit.text = ""
			_refresh_points()
		code_edit.release_focus()
	b.pressed.connect(redeem)
	code_edit.text_submitted.connect(redeem)

# small grey explanation after a setting
func _note(row: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = Color(1, 1, 1, 0.6)
	row.add_child(l)

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

# checkbox icons with an orange outline (the default dark ones are hard to see):
# empty orange box when off, filled orange box with a dark tick when on
static func _check_icon(checked: bool, disabled: bool) -> ImageTexture:
	var s := 22
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color(1.0, 0.6, 0.2) if not disabled else Color(0.55, 0.42, 0.3)
	var fill := Color(0.08, 0.08, 0.09)
	if checked:
		fill = edge
	for y in s:
		for x in s:
			var border := x < 2 or y < 2 or x >= s - 2 or y >= s - 2
			img.set_pixel(x, y, edge if border else fill)
	if checked:
		# tick: two thick strokes
		var tick := Color(0.08, 0.06, 0.04)
		for i in 50:
			var t := i / 49.0
			var a := Vector2(5, 11).lerp(Vector2(9, 16), t) if t < 0.5 else Vector2(9, 16).lerp(Vector2(17, 6), (t - 0.5) * 2.0)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					img.set_pixel(clampi(int(a.x) + dx, 0, s - 1), clampi(int(a.y) + dy, 0, s - 1), tick)
	return ImageTexture.create_from_image(img)

static func _orange_check_theme() -> Theme:
	var th := Theme.new()
	th.set_icon("unchecked", "CheckBox", _check_icon(false, false))
	th.set_icon("checked", "CheckBox", _check_icon(true, false))
	th.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, true))
	th.set_icon("checked_disabled", "CheckBox", _check_icon(true, true))
	th.set_constant("h_separation", "CheckBox", 10)
	return th

func build_settings(p_envc, p_main) -> void:
	envc = p_envc
	main_node = p_main
	settings_panel = PanelContainer.new()
	settings_panel.theme = _orange_check_theme()
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
	var t_codes := _tab(tabs, "Codes")
	settings_tabs = tabs
	_build_codes_tab(t_codes)
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
	# biome effects: falling leaves / petals / ash, from none up to the normal amount
	var r5e := _row(t_gfx)
	var fl := Label.new()
	fl.text = "Biome effects"
	fl.add_theme_font_size_override("font_size", 18)
	r5e.add_child(fl)
	var fx_slider := HSlider.new()
	fx_slider.min_value = 0.0
	fx_slider.max_value = 1.0
	fx_slider.step = 0.05
	fx_slider.value = main_node.biome_fx
	fx_slider.custom_minimum_size = Vector2(220, 30)
	fx_slider.focus_mode = Control.FOCUS_NONE
	fx_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r5e.add_child(fx_slider)
	var fx_val := Label.new()
	fx_val.text = "%d%%" % int(round(main_node.biome_fx * 100.0))
	fx_val.custom_minimum_size = Vector2(56, 0)
	fx_val.add_theme_font_size_override("font_size", 18)
	r5e.add_child(fx_val)
	fx_slider.value_changed.connect(func(v):
		fx_val.text = "%d%%" % int(round(v * 100.0))
		main_node.set_biome_fx(v))
	_note(r5e, "falling leaves, petals and ash (100% = normal)")
	# detail: Low = smooth flat colours and round ball trees (slow computers)
	var r5d := _row(t_gfx)
	var det_l := Label.new()
	det_l.text = "Detail"
	det_l.add_theme_font_size_override("font_size", 18)
	r5d.add_child(det_l)
	var det_opt := _opt(["High", "Low (smooth)"], "", 1 if Gfx.low else 0)
	det_opt.custom_minimum_size = Vector2(170, 0)
	det_opt.item_selected.connect(func(i): main_node.set_low_detail(i == 1))
	r5d.add_child(det_opt)
	_note(r5d, "Low: smooth textures, round trees, fewer effects - for slow PCs (reloads the map)")
	# baked lighting: light and shadows stored in the world's colours, drawn unshaded
	var r5b := _row(t_gfx)
	var bl := Label.new()
	bl.text = "Baked lighting"
	bl.add_theme_font_size_override("font_size", 18)
	r5b.add_child(bl)
	var bk_opt := _opt(["Off", "On"], "", 1 if Gfx.baked else 0)
	bk_opt.custom_minimum_size = Vector2(170, 0)
	bk_opt.item_selected.connect(func(i): main_node.set_baked(i == 1))
	r5b.add_child(bk_opt)
	_note(r5b, "lighting is baked into the textures - more FPS (reloads the map)")
	# light bounces (SDFGI): the expensive real-time version, off with baked lighting
	var r5c := _row(t_gfx)
	var gl2 := Label.new()
	gl2.text = "Light bounces"
	gl2.add_theme_font_size_override("font_size", 18)
	r5c.add_child(gl2)
	var gi_opt := _opt(["Off", "Low", "High"], "", clampi(main_node.gi_quality, 0, 2))
	gi_opt.custom_minimum_size = Vector2(170, 0)
	gi_opt.item_selected.connect(func(i): main_node.set_gi(i))
	gi_opt.disabled = Gfx.baked
	r5c.add_child(gi_opt)
	_note(r5c, "real-time light bouncing off the ground and trees - costs FPS" + ("  (off with baked lighting)" if Gfx.baked else ""))
	# --- car
	_section(t_car, "Car")
	var r6 := _row(t_car)
	var dmg := CheckBox.new()
	dmg.text = "Car damage  (body crumples, parts fall off, glass breaks - Backspace repairs)"
	dmg.button_pressed = main_node.car_damage
	dmg.focus_mode = Control.FOCUS_NONE
	dmg.add_theme_font_size_override("font_size", 18)
	r6.add_child(dmg)
	# fragility: how easily the car breaks (50% = normal)
	var r6f := _row(t_car)
	var frag_pad := Control.new()
	frag_pad.custom_minimum_size = Vector2(28, 0)
	r6f.add_child(frag_pad)
	var frag_l := Label.new()
	frag_l.text = "Fragility"
	frag_l.add_theme_font_size_override("font_size", 16)
	r6f.add_child(frag_l)
	var frag_slider := HSlider.new()
	frag_slider.min_value = 0.0
	frag_slider.max_value = 1.0
	frag_slider.step = 0.05
	frag_slider.value = main_node.car_fragility
	frag_slider.custom_minimum_size = Vector2(220, 30)
	frag_slider.focus_mode = Control.FOCUS_NONE
	frag_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r6f.add_child(frag_slider)
	var frag_val := Label.new()
	frag_val.custom_minimum_size = Vector2(130, 0)
	frag_val.add_theme_font_size_override("font_size", 16)
	r6f.add_child(frag_val)
	var frag_text := func(v: float) -> String:
		var pct := int(round(v * 100.0))
		if pct == 50:
			return "50%  (normal)"
		return "%d%%  (x%.2f)" % [pct, CarDamage.fragility_mult(v)]
	frag_val.text = frag_text.call(main_node.car_fragility)
	frag_slider.value_changed.connect(func(v):
		frag_val.text = frag_text.call(v)
		main_node.set_car_fragility(v))
	_note(r6f, "lower = tougher, higher = breaks more easily")
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
	_toggle_panel(settings_panel)

func toggle_controls() -> void:
	_toggle_panel(controls_panel)

# On the start screen a panel replaces the menu (one at a time, the menu comes
# back when it closes). While driving, panels just open over the HUD.
func _toggle_panel(p: Control) -> void:
	if p == null:
		return
	var want := not p.visible
	if menu and want:
		close_menu_panels()
	p.visible = want
	p.move_to_front()
	_sync_menu()
	_layout()

func _menu_panels() -> Array:
	return [settings_panel, controls_panel, cache_panel, inventory_panel, mp_panel].filter(func(x): return x != null)

func close_menu_panels() -> void:
	for x in _menu_panels():
		x.visible = false
	_sync_menu()

func _sync_menu() -> void:
	if menu == null or menu_busy:
		return
	var any := false
	for x in _menu_panels():
		any = any or x.visible
	menu.visible = not any
	if not any:
		_refresh_points()

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
	menu_status.text = "MAP"
	menu_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_status.add_theme_font_size_override("font_size", 24)
	menu_status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	v.add_child(menu_status)
	# step 1: the maps. Picking one swaps this list for the biome grid (step 2)
	map_list = VBoxContainer.new()
	map_list.add_theme_constant_override("separation", 10)
	v.add_child(map_list)
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
		map_list.add_child(b)
		if first_btn == null or idx == current:
			first_btn = b
		b.pressed.connect(func(): _show_biome_step(idx, e["name"]))
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
	cache_btn.text = "Caches"
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
	# third row: online play
	var row2b := _row(v)
	row2b.alignment = BoxContainer.ALIGNMENT_CENTER
	var mp_btn := Button.new()
	mp_btn.text = "Multiplayer"
	mp_btn.custom_minimum_size = Vector2(594, 44)
	mp_btn.add_theme_font_size_override("font_size", 19)
	mp_btn.pressed.connect(func(): _toggle_panel(mp_panel))
	row2b.add_child(mp_btn)
	menu_points_lbl = Label.new()
	menu_points_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_points_lbl.add_theme_font_size_override("font_size", 20)
	menu_points_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	var prow := _row(v)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_child(menu_points_lbl)
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
	# key hints along the bottom
	var keys := Label.new()
	keys.text = "Esc - Menu   |   Enter - Previous Map Visited"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_theme_font_size_override("font_size", 16)
	keys.add_theme_color_override("font_color", Color(0.75, 0.78, 0.75))
	v.add_child(keys)
	add_child(menu)
	cache_panel = _build_shop_panel("CACHES")
	inventory_panel = _build_shop_panel("INVENTORY")
	mp_panel = _build_mp_panel()
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

# ---------------------------------------------------------------- multiplayer panel
var mp_panel: PanelContainer

func _build_mp_panel() -> PanelContainer:
	var p := _build_shop_panel("MULTIPLAYER")
	(p.get_meta("points") as Label).visible = false
	var list: VBoxContainer = p.get_meta("list")
	var cfg := ConfigFile.new()
	cfg.load("user://net.cfg")
	Net.my_name = String(cfg.get_value("net", "name", Net.my_name))
	var save := func(k: String, v):
		cfg.set_value("net", k, v)
		cfg.save("user://net.cfg")
	# name
	var r1 := _row(list)
	var nl := Label.new()
	nl.text = "Your name"
	nl.custom_minimum_size = Vector2(120, 0)
	nl.add_theme_font_size_override("font_size", 19)
	r1.add_child(nl)
	var name_edit := LineEdit.new()
	name_edit.text = Net.my_name
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(300, 42)
	name_edit.add_theme_font_size_override("font_size", 19)
	name_edit.text_changed.connect(func(t):
		Net.my_name = t if t.strip_edges() != "" else "Player"
		save.call("name", Net.my_name))
	r1.add_child(name_edit)
	# host
	var r2 := _row(list)
	var host_btn := Button.new()
	host_btn.text = "Host a game"
	host_btn.custom_minimum_size = Vector2(220, 46)
	host_btn.add_theme_font_size_override("font_size", 19)
	host_btn.focus_mode = Control.FOCUS_NONE
	r2.add_child(host_btn)
	_note(r2, "you pick the map, friends join you (port 7777)")
	# join
	var r3 := _row(list)
	var addr := LineEdit.new()
	addr.placeholder_text = "host's address, e.g. 192.168.1.20 or abc.playit.gg:12345"
	addr.text = String(cfg.get_value("net", "address", ""))
	addr.custom_minimum_size = Vector2(440, 46)
	addr.add_theme_font_size_override("font_size", 18)
	r3.add_child(addr)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(120, 46)
	join_btn.add_theme_font_size_override("font_size", 19)
	join_btn.focus_mode = Control.FOCUS_NONE
	r3.add_child(join_btn)
	# status, players, leave
	var st := Label.new()
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(640, 0)
	st.add_theme_font_size_override("font_size", 18)
	st.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	list.add_child(st)
	var pl := Label.new()
	pl.add_theme_font_size_override("font_size", 17)
	list.add_child(pl)
	var leave := Button.new()
	leave.text = "Leave / stop hosting"
	leave.custom_minimum_size = Vector2(240, 42)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.add_theme_font_size_override("font_size", 18)
	leave.focus_mode = Control.FOCUS_NONE
	list.add_child(leave)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(640, 0)
	help.add_theme_font_size_override("font_size", 14)
	help.modulate = Color(1, 1, 1, 0.65)
	help.text = "Same Wi-Fi: friends type the host's local IP (ipconfig > IPv4). Over the internet, for free: " \
		+ "the host runs playit.gg (UDP tunnel to port 7777) and shares its address, or everyone joins the " \
		+ "same Tailscale / Radmin VPN network and uses the host's address there."
	list.add_child(help)
	var refresh := func():
		if not is_instance_valid(st):
			return
		st.text = Net.status
		var names := [Net.my_name + " (you)"]
		for id in Net.players.keys():
			names.append(String(Net.players[id].get("name", "Player")))
		pl.text = "Players: " + ", ".join(names) if Net.is_online() else ""
		leave.disabled = not Net.is_online()
		host_btn.disabled = Net.is_online()
		join_btn.disabled = Net.is_online()
	host_btn.pressed.connect(func():
		Net.host()
		refresh.call())
	var do_join := func(_t = ""):
		save.call("address", addr.text)
		Net.join(addr.text)
		addr.release_focus()
		refresh.call()
	join_btn.pressed.connect(do_join)
	addr.text_submitted.connect(do_join)
	leave.pressed.connect(func():
		Net.leave()
		refresh.call())
	Net.status_changed.connect(func(_t): refresh.call())
	Net.players_changed.connect(func(): refresh.call())
	refresh.call()
	return p

func _toggle_shop_panel(p: PanelContainer) -> void:
	if p == null:
		return
	if p == mp_panel:
		_toggle_panel(p)
		return
	if not p.visible:
		cache_result = ""
		_fill_shop_panel(p)
	_toggle_panel(p)

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
		# what the last cache gave you
		if cache_result != "":
			var res := HBoxContainer.new()
			res.alignment = BoxContainer.ALIGNMENT_CENTER
			res.add_theme_constant_override("separation", 12)
			list.add_child(res)
			res.add_child(_swatch(Profile.skin_color(cache_result), 34, Profile.skin_neon(cache_result)))
			var rl := Label.new()
			rl.text = "You got:  %s%s" % [Profile.item_name(cache_result), "   (duplicate)" if Profile.item_count(cache_result) > 1 else ""]
			rl.add_theme_font_size_override("font_size", 24)
			rl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			res.add_child(rl)
			list.add_child(HSeparator.new())
		if Profile.CACHES.is_empty():
			_empty_note(list, "No caches yet - check back later.")
		for c in Profile.CACHES:
			var cid: String = c["id"]
			var price := int(c["price"])
			# a card: picture | name, price | Open
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 18)
			list.add_child(r)
			var art := CacheArt.new()
			art.custom_minimum_size = Vector2(150, 150)
			if c.has("tint"):
				art.tint = c["tint"]
			art.style = cid
			art.label = String(c["name"]).replace(" Cache", "")
			r.add_child(art)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.alignment = BoxContainer.ALIGNMENT_CENTER
			r.add_child(info)
			var nl := Label.new()
			nl.text = String(c["name"]).to_upper()
			nl.add_theme_font_size_override("font_size", 26)
			nl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
			info.add_child(nl)
			var pl := Label.new()
			pl.text = "%d points" % price
			pl.add_theme_font_size_override("font_size", 20)
			pl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
			info.add_child(pl)
			var b := Button.new()
			b.text = "Open"
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(130, 56)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.add_theme_font_size_override("font_size", 22)
			b.disabled = Profile.points < price
			b.tooltip_text = "" if not b.disabled else "Not enough points"
			b.pressed.connect(func():
				var won := Profile.open_cache(cid)
				if won != "":
					_fill_shop_panel(p)   # points go down straight away
					# the roll: items scroll past and stop on what you won
					var roll := CrateRoll.new()
					add_child(roll)
					roll.setup(cid, won, String(c["name"]), func():
						cache_result = won
						_fill_shop_panel(p)))
			r.add_child(b)
	else:
		# tabs: Skins | Cars
		var tabs := HBoxContainer.new()
		tabs.alignment = BoxContainer.ALIGNMENT_CENTER
		tabs.add_theme_constant_override("separation", 10)
		list.add_child(tabs)
		for ti in 2:
			var tb := Button.new()
			tb.text = ["Skins", "Cars"][ti]
			tb.toggle_mode = true
			tb.button_pressed = inv_tab == ti
			tb.focus_mode = Control.FOCUS_NONE
			tb.custom_minimum_size = Vector2(160, 40)
			tb.add_theme_font_size_override("font_size", 20)
			tb.pressed.connect(func():
				inv_tab = ti
				_fill_shop_panel(p))
			tabs.add_child(tb)
		list.add_child(HSeparator.new())
		if inv_tab == 1:
			# every car (all owned); the equipped one is what you drive next
			for cid in Profile.CARS.keys():
				var id: String = cid
				var cd: Dictionary = Profile.CARS[id]
				var r := _item_row(list, {"name": cd["name"], "info": cd["info"]}, "")
				var b := Button.new()
				var on: bool = Profile.equipped_car == id
				b.text = "Driving" if on else "Drive"
				b.disabled = on
				b.focus_mode = Control.FOCUS_NONE
				b.custom_minimum_size = Vector2(110, 0)
				b.add_theme_font_size_override("font_size", 18)
				b.pressed.connect(func():
					Profile.equip_car(id)
					_fill_shop_panel(p))
				r.add_child(b)
			_empty_note(list, "Your car is used on the next map you drive. Skins paint any car.")
			return
		# sort: A-Z, Rarity (best first) or Crate (Basic, Neon, then the rest)
		var sr := HBoxContainer.new()
		sr.alignment = BoxContainer.ALIGNMENT_END
		sr.add_theme_constant_override("separation", 10)
		list.add_child(sr)
		var sl := Label.new()
		sl.text = "Sort by"
		sl.add_theme_font_size_override("font_size", 18)
		sr.add_child(sl)
		var so := _opt(["A-Z", "Rarity", "Crate"], "", inv_sort)
		so.custom_minimum_size = Vector2(140, 0)
		so.item_selected.connect(func(i):
			inv_sort = i
			_fill_shop_panel(p))
		sr.add_child(so)
		# every owned skin (Grey is always owned), sorted together
		var owned := [Profile.STOCK_SKIN]
		for id in Profile.inventory.keys():
			owned.append(String(id))
		owned.sort_custom(func(a, b): return _inv_less(a, b))
		var ids := owned
		var last_group := ""
		for id in ids:
			var sid: String = id
			if inv_sort == 2:
				var grp := _crate_group(sid)
				if grp != last_group:
					last_group = grp
					var gl := Label.new()
					gl.text = grp
					gl.add_theme_font_size_override("font_size", 20)
					gl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
					list.add_child(gl)
			var r := _item_row(list, {"name": Profile.item_name(sid)}, "" if sid == Profile.STOCK_SKIN else "x%d" % Profile.item_count(sid))
			# the name in its rarity colour (Grey and retired skins stay white)
			var tier := Profile.skin_tier(sid)
			if tier >= 0:
				(r.get_child(0) as Label).add_theme_color_override("font_color", (Profile.RARITY_COLORS[tier] as Color).lightened(0.15))
			if Profile.is_skin(sid):
				r.add_child(_swatch(Profile.skin_color(sid), 30, Profile.skin_neon(sid)))
				r.move_child(r.get_child(r.get_child_count() - 1), 0)
				var b := Button.new()
				var on: bool = Profile.equipped_skin == sid
				b.text = "Equipped" if on else "Equip"
				b.disabled = on
				b.focus_mode = Control.FOCUS_NONE
				b.custom_minimum_size = Vector2(110, 0)
				b.add_theme_font_size_override("font_size", 18)
				b.pressed.connect(func():
					Profile.equip_skin(sid)
					_fill_shop_panel(p))
				r.add_child(b)
		if Profile.inventory.is_empty():
			_empty_note(list, "Open caches to get more skins.")

var cache_result := ""
var inv_tab := 0   # Inventory: 0 skins, 1 cars
static var inv_sort := 1   # Inventory skins: 0 A-Z, 1 rarity, 2 crate (kept across map loads)

# which crate a skin comes from, for the Crate sort's headings
func _crate_group(id: String) -> String:
	if Profile.item_tier("basic", id) >= 0:
		return "Basic Cache"
	if Profile.item_tier("neon", id) >= 0:
		return "Neon Cache"
	return "Other"

func _inv_less(a: String, b: String) -> bool:
	var na := Profile.item_name(a).to_lower()
	var nb := Profile.item_name(b).to_lower()
	match inv_sort:
		1:   # rarity, best first, then A-Z
			var ta := Profile.skin_tier(a)
			var tb := Profile.skin_tier(b)
			if ta != tb:
				return ta > tb
		2:   # crate (Basic, Neon, other), then rarity, then A-Z
			var order := ["Basic Cache", "Neon Cache", "Other"]
			var ga := order.find(_crate_group(a))
			var gb := order.find(_crate_group(b))
			if ga != gb:
				return ga < gb
			var ta2 := Profile.skin_tier(a)
			var tb2 := Profile.skin_tier(b)
			if ta2 != tb2:
				return ta2 > tb2
	return na < nb

# picture of a cache, drawn in code: a rugged storage crate seen from above
# and to one side - shaded faces, metal corner guards with rivets, a carry
# handle, snap latches, ribbed sides and a stencilled name plate.
# style "basic": tinted moulded plastic. style "neon": a black case with
# glowing neon tubes along its edges in the tint colour.
class CacheArt extends Control:
	var tint := Color(1.0, 0.55, 0.12)
	var style := "basic"
	var label := ""

	# crate layout (fractions of the picture): front face L..R x T..B, lid/base
	# seam at S, depth offset D (up and to the right)
	const L := 0.12
	const R := 0.72
	const T := 0.42
	const S := 0.56
	const B := 0.86
	const D := Vector2(0.15, -0.11)

	func _p(x: float, y: float) -> Vector2:
		return Vector2(x * size.x, y * size.y)

	func _bp(x: float, y: float) -> Vector2:   # same point on the back face
		return Vector2((x + D.x) * size.x, (y + D.y) * size.y)

	func _tc(u: float, v: float) -> Vector2:   # on the lid's top: u across, v into the depth
		return Vector2((L + (R - L) * u + D.x * v) * size.x, (T + D.y * v) * size.y)

	# filled polygon shaded from c_top (first two points) to c_bot (the rest)
	func _face(pts: Array, c_top: Color, c_bot: Color, outline := Color(0, 0, 0, 0)) -> void:
		var pv := PackedVector2Array()
		var cv := PackedColorArray()
		for i in pts.size():
			pv.append(pts[i])
			cv.append(c_top if i < 2 else c_bot)
		draw_polygon(pv, cv)
		if outline.a > 0.0:
			var ol := pv.duplicate()
			ol.append(pv[0])
			draw_polyline(ol, outline, 2.0, true)

	func _neon_line(a: Vector2, b: Vector2, c: Color) -> void:
		draw_line(a, b, Color(c.r, c.g, c.b, 0.08), 9.0, true)
		draw_line(a, b, Color(c.r, c.g, c.b, 0.15), 6.0, true)
		draw_line(a, b, Color(c.r, c.g, c.b, 0.4), 3.5, true)
		draw_line(a, b, c.lightened(0.6), 1.6, true)

	func _rivet(p: Vector2, r: float) -> void:
		draw_circle(p, r, Color(0.22, 0.23, 0.25))
		draw_circle(p, r * 0.75, Color(0.62, 0.64, 0.67))
		draw_circle(p + Vector2(-r * 0.25, -r * 0.25), r * 0.3, Color(0.96, 0.97, 0.99))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var neon := style == "neon"
		# ---- light behind, shadow under
		var glow_a := 0.06 if neon else 0.035
		for k in 8:
			draw_circle(_p(0.5, 0.52), w * (0.5 - k * 0.045), Color(tint.r, tint.g, tint.b, glow_a + k * 0.008))
		if neon:
			for k in 12:
				var ang := TAU * k / 12.0 + 0.2
				draw_line(_p(0.5, 0.52), _p(0.5, 0.52) + Vector2(cos(ang), sin(ang)) * w * 0.5, Color(tint.r, tint.g, tint.b, 0.07), 3.0, true)
		draw_set_transform(_p(0.47, 0.9), 0.0, Vector2(1.0, 0.18))
		draw_circle(Vector2.ZERO, w * 0.42, Color(0, 0, 0, 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# ---- colours
		var body := Color(0.075, 0.08, 0.095) if neon else tint
		var hi := body.lightened(0.12 if neon else 0.22)
		var lo := body.darkened(0.35)
		var edge := Color(0.02, 0.02, 0.03)
		var metal_hi := Color(0.86, 0.88, 0.9)
		var metal_lo := Color(0.42, 0.44, 0.47)
		# ---- side face (darker): lid band and base band
		_face([_p(R, T), _bp(R, T), _bp(R, S), _p(R, S)], lo.lightened(0.08), lo, edge)
		_face([_p(R, S), _bp(R, S), _bp(R, B), _p(R, B)], lo.darkened(0.05), lo.darkened(0.25), edge)
		# ---- top of the lid with a raised centre panel
		_face([_p(L, T), _p(R, T), _bp(R, T), _bp(L, T)], hi, hi.lightened(0.08), edge)
		_face([_tc(0.12, 0.2), _tc(0.88, 0.2), _tc(0.88, 0.8), _tc(0.12, 0.8)], hi.lightened(0.06), hi.darkened(0.04), body.darkened(0.25))
		# carry handle: two posts and a grip bar
		for u in [0.32, 0.68]:
			_face([_tc(u - 0.035, 0.42), _tc(u + 0.035, 0.42), _tc(u + 0.035, 0.58), _tc(u - 0.035, 0.58)], lo, lo, edge)
		var g0 := _tc(0.3, 0.5) + Vector2(0, -h * 0.05)
		var g1 := _tc(0.7, 0.5) + Vector2(0, -h * 0.05)
		for u in [0.32, 0.68]:
			draw_line(_tc(u, 0.5), Vector2(lerpf(g0.x, g1.x, (u - 0.3) / 0.4), g0.y), Color(0.13, 0.13, 0.15), h * 0.03, true)
		draw_line(g0, g1, edge, h * 0.055, true)
		draw_line(g0, g1, Color(0.16, 0.16, 0.18), h * 0.04, true)
		draw_line(g0 + Vector2(0, -h * 0.01), g1 + Vector2(0, -h * 0.01), Color(1, 1, 1, 0.18), h * 0.008, true)
		# ---- front: lid band and base
		_face([_p(L, T), _p(R, T), _p(R, S), _p(L, S)], body.lightened(0.08), body, edge)
		_face([_p(L, S), _p(R, S), _p(R, B), _p(L, B)], body.darkened(0.06), body.darkened(0.3), edge)
		draw_line(_p(L, S), _p(R, S), Color(0, 0, 0, 0.6), 3.0, true)
		draw_line(_p(R, S), _bp(R, S), Color(0, 0, 0, 0.6), 3.0, true)
		# moulded ribs on the base, front and side
		for x in [0.24, 0.36, 0.48, 0.6]:
			draw_line(_p(x, S + 0.04), _p(x, B - 0.04), Color(0, 0, 0, 0.35), 3.0, true)
			draw_line(_p(x + 0.008, S + 0.04), _p(x + 0.008, B - 0.04), Color(1, 1, 1, 0.12), 1.5, true)
		for k in 3:
			var t := (k + 1) / 4.0
			draw_line(_p(R, S + 0.04).lerp(_bp(R, S + 0.04), t), _p(R, B - 0.04).lerp(_bp(R, B - 0.04), t), Color(0, 0, 0, 0.4), 2.5, true)
		# ---- metal corner guards with rivets
		var cg := 0.07
		for cx in [L, R]:
			var sx: float = 1.0 if cx == L else -1.0
			for cy in [T, B]:
				var sy: float = 1.0 if cy == T else -1.0
				var p0 := _p(cx, cy)
				var px := _p(cx + sx * cg, cy)
				var py := _p(cx, cy + sy * cg * 1.3)
				_face([p0, px, px + (py - p0) * 0.45, p0 + (px - p0) * 0.45 + (py - p0) * 0.45, py], metal_hi, metal_lo, edge)
				_rivet(p0 + (px - p0) * 0.3 + (py - p0) * 0.3, w * 0.012)
		for cy in [T, B]:
			var q0 := _bp(R, cy)
			var sy2: float = 1.0 if cy == T else -1.0
			var qd := Vector2(0, sy2 * h * cg * 1.3)
			var qs := q0.lerp(_p(R, cy), 0.28)
			_face([q0, qs, qs + qd, q0 + qd], metal_hi.darkened(0.15), metal_lo.darkened(0.1), edge)
		# ---- snap latches across the seam
		for x0 in [0.2, 0.64]:
			_face([_p(x0 - 0.045, S - 0.06), _p(x0 + 0.045, S - 0.06), _p(x0 + 0.045, S + 0.08), _p(x0 - 0.045, S + 0.08)], metal_hi, metal_lo, edge)
			_face([_p(x0 - 0.03, S - 0.035), _p(x0 + 0.03, S - 0.035), _p(x0 + 0.03, S + 0.05), _p(x0 - 0.03, S + 0.05)], Color(0.12, 0.12, 0.13), Color(0.05, 0.05, 0.06))
			var tab := tint if neon else tint.lightened(0.3)
			_face([_p(x0 - 0.022, S + 0.005), _p(x0 + 0.022, S + 0.005), _p(x0 + 0.022, S + 0.035), _p(x0 - 0.022, S + 0.035)], tab, tab.darkened(0.2))
			_rivet(_p(x0, S - 0.045), w * 0.009)
		# ---- name plate with a stencilled name
		var np0 := _p(0.27, S + 0.1)
		var plate := Rect2(np0, _p(0.57, S + 0.2) - np0)
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(0.08, 0.09, 0.1) if neon else Color(0.9, 0.9, 0.86)
		psb.border_color = tint if neon else edge
		psb.set_border_width_all(2)
		psb.set_corner_radius_all(3)
		draw_style_box(psb, plate)
		for rx in [plate.position.x + 5.0, plate.end.x - 5.0]:
			_rivet(Vector2(rx, plate.position.y + plate.size.y * 0.5), w * 0.007)
		var f := ThemeDB.fallback_font
		var txt := label.to_upper() if label != "" else "CACHE"
		var fs := int(h * 0.07)
		while fs > 6 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > plate.size.x - 18.0:
			fs -= 1
		var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var tpos := Vector2(plate.position.x + (plate.size.x - ts.x) * 0.5, plate.position.y + plate.size.y * 0.5 + fs * 0.36)
		if neon:
			for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_string(f, tpos + o * 1.5, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tint.r, tint.g, tint.b, 0.45))
			draw_string(f, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint.lightened(0.6))
		else:
			draw_string(f, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.12, 0.12, 0.13))
		# "?" emblem on the lid front
		var qf := int(h * 0.1)
		var qpos := _p(0.42, S - 0.025)
		var qsz := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, qf)
		draw_circle(qpos + Vector2(0, -qf * 0.3), qf * 0.5, Color(0, 0, 0, 0.35))
		draw_string(f, qpos + Vector2(-qsz.x * 0.5, 0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, qf, tint.lightened(0.45) if neon else Color(1, 1, 1, 0.92))
		# glossy highlights
		draw_line(_p(L + 0.03, T + 0.015), _p(R - 0.03, T + 0.015), Color(1, 1, 1, 0.15 if neon else 0.35), 2.0, true)
		draw_line(_p(L + 0.02, S + 0.05), _p(L + 0.02, B - 0.06), Color(1, 1, 1, 0.16), 3.0, true)
		# ---- neon tubes along every outer edge, and sparkles
		if neon:
			var edges := [[_p(L, T), _p(R, T)], [_p(R, T), _bp(R, T)], [_bp(R, T), _bp(L, T)], [_bp(L, T), _p(L, T)],
				[_p(L, T), _p(L, B)], [_p(R, T), _p(R, B)], [_bp(R, T), _bp(R, B)],
				[_p(L, B), _p(R, B)], [_p(R, B), _bp(R, B)], [_p(L, S), _p(R, S)], [_p(R, S), _bp(R, S)]]
			for e in edges:
				_neon_line(e[0], e[1], tint)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for k in 7:
				var sp := _p(rng.randf_range(0.05, 0.95), rng.randf_range(0.08, 0.35))
				var sz := w * rng.randf_range(0.008, 0.018)
				draw_line(sp - Vector2(sz, 0), sp + Vector2(sz, 0), tint.lightened(0.6), 1.5, true)
				draw_line(sp - Vector2(0, sz), sp + Vector2(0, sz), tint.lightened(0.6), 1.5, true)

# neon skins show their full-brightness glow colour
func _swatch(c: Color, s: float, neon := false) -> ColorRect:
	if neon:
		var m: float = max(c.r, max(c.g, c.b), 0.001)
		if m >= 0.05:   # (Neon Black stays black)
			c = Color(c.r / m, c.g / m, c.b / m)
	var cr := ColorRect.new()
	cr.color = c
	cr.custom_minimum_size = Vector2(s, s)
	cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return cr

# start menu: the biome every map is dressed in (looks only, driving is the same)
var menu_vbox: VBoxContainer
var menu_tools_row: HBoxContainer
var biome_info: Label

func build_biome_picker(names: Array, infos: Array, current: String, main_node) -> void:
	if menu_vbox == null:
		return
	# step 2 of the start screen (hidden until a map is picked): pick the biome
	# and the map starts in it
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.visible = false
	biome_box = box
	# a grid, four to a row (one long row didn't fit 11 biomes)
	var row := GridContainer.new()
	row.columns = 4
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
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
			main_node.set_biome(nm)
			_pick(picked_map, picked_name))
		b.mouse_entered.connect(func(): biome_info.text = _biome_text(nm, info))
	var back := Button.new()
	back.text = "Back to maps"
	back.custom_minimum_size = Vector2(220, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 19)
	back.pressed.connect(back_to_maps)
	box.add_child(back)
	menu_vbox.add_child(box)
	menu_vbox.move_child(box, map_list.get_index() + 1)
	_layout()

func _biome_text(nm: String, info: String) -> String:
	var t := info
	return t

# start screen step 2: after picking a map, choose its biome
var map_list: VBoxContainer
var biome_box: VBoxContainer
var picked_map := -1
var picked_name := ""

func _show_biome_step(idx: int, name: String) -> void:
	if Net.is_client():   # online: the host picks the map, you follow it
		menu_status.text = "ONLINE  -  THE HOST PICKS THE MAP"
		return
	if menu_busy or biome_box == null:
		_pick(idx, name)
		return
	picked_map = idx
	picked_name = name
	map_list.visible = false
	biome_box.visible = true
	menu_status.text = "BIOME  -  %s" % name.to_upper()
	_layout()

func in_biome_step() -> bool:
	return biome_box != null and biome_box.visible

func back_to_maps() -> void:
	if biome_box == null or menu_busy:
		return
	biome_box.visible = false
	map_list.visible = true
	menu_status.text = "MAP"
	_layout()

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
	if in_biome_step():   # Enter on the biome step: drive the picked map in the current biome
		_pick(picked_map, picked_name)
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
	help_lbl.text = "Menu button: back to the menu     Y: recenter" if vr_mode else "F1  Controls     F2  Settings"
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

func setup_menu_screen(with_blur := true) -> void:
	if not with_blur:   # VR: the menu floats in the forest, no backdrop
		build_controls()
		_layout()
		get_viewport().size_changed.connect(_layout)
		return
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
	for sp in [cache_panel, inventory_panel, mp_panel]:
		if sp:
			sp.reset_size()
			sp.position = (vs - sp.size) * 0.5
	if settings_panel:
		settings_panel.reset_size()
		settings_panel.position = Vector2(24, vs.y - settings_panel.size.y - 24)
		if menu:   # start screen: it takes the menu's place in the middle
			settings_panel.position = (vs - settings_panel.size) * 0.5

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
			parts.append(Net.ping_text())
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

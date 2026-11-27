# Crate opening: a strip of items scrolls from right to left under a centre
# line, slows down and stops on the item you won. Each item is framed in its
# rarity colour (C grey, B blue, A orange, S red). The filler items are rolled
# with the cache's real odds, so most of what flies past is common. Ticks as
# each item crosses the line; click (or any key) to skip to the end.
#
# The item is already in the inventory when this starts (Profile.open_cache);
# this is only the show. on_done is called when the player closes it.
extends Control

const Profile = preload("res://scripts/profile.gd")

const RARITY := Profile.RARITY_COLORS
const CARD_W := 150.0
const CARD_H := 170.0
const GAP := 8.0
const COUNT := 60          # cards on the strip
const WIN_AT := 50         # the winner's place on it
const SPIN_TIME := 6.0

var cache_id := ""
var won := ""
var on_done: Callable
var win_tier := 0

var window: Control        # clips the strip
var strip: Control
var marker: ColorRect
var result_box: VBoxContainer
var tween: Tween
var winner_card: Control
var tick: AudioStreamPlayer
var last_idx := -1
var done := false

static var _tick_stream: AudioStreamWAV

func setup(p_cache: String, p_won: String, title: String, p_done: Callable) -> void:
	cache_id = p_cache
	won = p_won
	on_done = p_done
	win_tier = max(Profile.item_tier(cache_id, won), 0)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var tl := Label.new()
	tl.text = title.to_upper()
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 34)
	tl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	col.add_child(tl)
	# the window the strip scrolls through
	var vw: float = get_viewport().get_visible_rect().size.x
	window = Control.new()
	window.clip_contents = true
	window.custom_minimum_size = Vector2(min(1120.0, vw - 60.0), CARD_H + 24.0)
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(window)
	var wbg := ColorRect.new()
	wbg.color = Color(0.06, 0.065, 0.075)
	wbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(wbg)
	strip = Control.new()
	strip.position = Vector2(0, 12)
	window.add_child(strip)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var tiers := Profile.cache_tiers(cache_id)
	for i in COUNT:
		var id: String = won if i == WIN_AT else Profile._roll(tiers)
		var card := _card(id, max(Profile.item_tier(cache_id, id), 0))
		card.position = Vector2(i * (CARD_W + GAP), 0)
		strip.add_child(card)
		if i == WIN_AT:
			winner_card = card
	# centre line
	marker = ColorRect.new()
	marker.color = Color(1.0, 0.82, 0.25)
	marker.size = Vector2(4, CARD_H + 24.0)
	window.add_child(marker)
	# what you got (shown at the end)
	result_box = VBoxContainer.new()
	result_box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_box.add_theme_constant_override("separation", 12)
	result_box.custom_minimum_size = Vector2(0, 110)
	result_box.modulate.a = 0.0
	col.add_child(result_box)
	var rl := Label.new()
	rl.text = "You got:  " + Profile.item_name(won)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_theme_font_size_override("font_size", 30)
	rl.add_theme_color_override("font_color", RARITY[win_tier].lightened(0.25))
	result_box.add_child(rl)
	var cb := Button.new()
	cb.text = "Continue"
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size = Vector2(180, 50)
	cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cb.add_theme_font_size_override("font_size", 22)
	cb.pressed.connect(_close)
	result_box.add_child(cb)
	# tick sound
	tick = AudioStreamPlayer.new()
	tick.stream = _tick()
	tick.bus = "Effects" if AudioServer.get_bus_index("Effects") != -1 else "Master"
	tick.max_polyphony = 4
	tick.volume_db = -6.0
	add_child(tick)
	# centre the column once sizes are known, then spin
	await get_tree().process_frame
	col.position = (get_viewport().get_visible_rect().size - col.size) * 0.5
	marker.position.x = window.size.x * 0.5 - 2.0
	_spin(rng)

func _card(id: String, tier: int) -> Control:
	var rc: Color = RARITY[tier]
	var card := Panel.new()
	card.size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.135, 0.15).lerp(rc, 0.16)
	sb.border_color = rc
	sb.border_width_bottom = 8
	sb.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", sb)
	# the paint colour; neon skins glow
	var neon := Profile.skin_neon(id)
	var c := Profile.skin_color(id)
	var sw := Panel.new()
	sw.size = Vector2(96, 64)
	sw.position = Vector2((CARD_W - 96.0) * 0.5, 24)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssb := StyleBoxFlat.new()
	ssb.set_corner_radius_all(10)
	var m: float = max(c.r, max(c.g, c.b), 0.001)
	if neon and m >= 0.05:
		var glow := Color(c.r / m, c.g / m, c.b / m)
		ssb.bg_color = glow
		ssb.shadow_color = Color(glow.r, glow.g, glow.b, 0.75)
		ssb.shadow_size = 14
	else:
		ssb.bg_color = c
		if neon:   # Neon Black: a faint cold sheen
			ssb.shadow_color = Color(0.55, 0.6, 1.0, 0.35)
			ssb.shadow_size = 8
	sw.add_theme_stylebox_override("panel", ssb)
	card.add_child(sw)
	var nl := Label.new()
	nl.text = Profile.item_name(id)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.position = Vector2(6, 100)
	nl.size = Vector2(CARD_W - 12.0, 56)
	nl.add_theme_font_size_override("font_size", 17)
	nl.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
	card.add_child(nl)
	return card

func _spin(rng: RandomNumberGenerator) -> void:
	var step := CARD_W + GAP
	# stop somewhere inside the winning card, not always dead centre (it feels rigged)
	var land: float = WIN_AT * step + CARD_W * 0.5 + rng.randf_range(-CARD_W * 0.38, CARD_W * 0.38)
	var end_x: float = window.size.x * 0.5 - land
	strip.position.x = window.size.x * 0.5 - CARD_W * 0.5 + step * 2.0   # starts off to the right
	tween = create_tween()
	tween.tween_property(strip, "position:x", end_x, SPIN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_finish)

func _process(_delta: float) -> void:
	if strip == null or done:
		return
	var idx := int(floor((window.size.x * 0.5 - strip.position.x) / (CARD_W + GAP)))
	if idx != last_idx:
		if last_idx != -1:
			tick.pitch_scale = randf_range(0.95, 1.08)
			tick.play()
		last_idx = idx

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		_skip()
		accept_event()

func _unhandled_input(e: InputEvent) -> void:
	if (e is InputEventKey or e is InputEventJoypadButton) and e.is_pressed():
		if done:
			_close()
		else:
			_skip()
		get_viewport().set_input_as_handled()

func _skip() -> void:
	if done:
		return
	if tween and tween.is_running():
		tween.kill()
		var step := CARD_W + GAP
		strip.position.x = window.size.x * 0.5 - (WIN_AT * step + CARD_W * 0.5)
		_finish()

func _finish() -> void:
	if done:
		return
	done = true
	# the winner lights up in its rarity colour, the rest dim
	for c in strip.get_children():
		if c != winner_card:
			(c as Control).modulate = Color(0.45, 0.45, 0.5)
	var sb: StyleBoxFlat = (winner_card.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	sb.bg_color = Color(0.13, 0.135, 0.15).lerp(RARITY[win_tier], 0.4)
	sb.set_border_width_all(4)
	sb.border_width_bottom = 10
	sb.shadow_color = Color(RARITY[win_tier].r, RARITY[win_tier].g, RARITY[win_tier].b, 0.6)
	sb.shadow_size = 18
	winner_card.add_theme_stylebox_override("panel", sb)
	winner_card.pivot_offset = winner_card.size * 0.5
	var t := create_tween().set_parallel()
	t.tween_property(winner_card, "scale", Vector2(1.08, 1.08), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(result_box, "modulate:a", 1.0, 0.3)

func _close() -> void:
	if on_done.is_valid():
		on_done.call()
	queue_free()

# a short wooden click, made once
static func _tick() -> AudioStreamWAV:
	if _tick_stream:
		return _tick_stream
	var rate := 44100
	var n := int(rate * 0.035)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 160.0)
		var s := (sin(TAU * 2300.0 * t) * 0.6 + sin(TAU * 1100.0 * t) * 0.4) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_tick_stream = w
	return w

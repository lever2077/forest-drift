# Crash sounds, synthesised at start-up on a background thread (no sound files).
# Real crunching metal isn't a few pure tones: it's hundreds of tiny impacts as
# the panels fold, each one ringing the car's sheet metal (dense, inharmonic
# resonances), on top of a heavy body thump, with metal tearing and the sound
# bouncing off the trees and road. So each sound is built that way:
#   excitation (impact clusters, a crumple train of small hits, secondary hits)
#   -> a bank of resonant band-pass filters (the panels' modes)
#   + low thump + tearing screech + short outdoor echoes, softly clipped.
# Several variations of each, picked at random with a little pitch change.
extends Node3D

const RATE := 24000

var car
var heavy: Array[AudioStreamWAV] = []
var light: Array[AudioStreamWAV] = []
var glass_s: Array[AudioStreamWAV] = []
var clank_s: Array[AudioStreamWAV] = []
var players: Array[AudioStreamPlayer] = []
var scrape: AudioStreamPlayer
var hiss: AudioStreamPlayer
var next := 0
var rng := RandomNumberGenerator.new()
var thread: Thread
var ready_sounds := false

# recorded sounds (res://sounds, all CC0 - see sounds/CREDITS.md); the
# synthesised ones above are only used if a recording is missing
var rec_big: Array = []
var rec_med: Array = []
var rec_light: Array = []
var rec_crash_light: Array = []   # the light crash recording alone (no clangs)
var rec_rail: Array = []
var rec_slam: Array = []
var rec_wood: Array = []
var rec_wood_light: Array = []
var rec_glass: Array = []
var rec_clank: Array = []
var rec_scrape: AudioStream

func _load_recordings() -> void:
	var dir := "res://sounds/"
	rec_big = _load_all([dir + "crash_big_1.mp3", dir + "crash_big_2.mp3"])
	rec_med = _load_all([dir + "crash_med_1.mp3", dir + "crash_big_2.mp3"])
	rec_light = _load_all([dir + "crash_light_1.mp3"] + _pack(["metal_hit_01", "metal_hit_02", "metal_hit_03", "metal_hit_04", "metal_hit_05"]))
	rec_crash_light = _load_all([dir + "crash_light_1.mp3"])
	rec_rail = _load_all(_pack(["metal_sheet_01", "metal_sheet_02", "metal_sheet_03", "metal_sheet_04", "metal_sheet_05", "metal_sheet_06"]))
	rec_slam = _load_all(_pack(["metal_slam_01", "metal_falling_01", "metal_falling_02"]))
	rec_wood = _load_all(_pack(["wood_breaking_01", "wood_breaking_02"]))
	rec_wood_light = _load_all(_pack(["wood_cracking_01", "wood_cracking_02", "wood_cracking_03", "wood_cracking_04"]))
	rec_glass = _load_all([dir + "glass_breaking.wav"])
	rec_clank = _load_all(_pack(["metal_falling_01", "metal_falling_02", "metal_hit_02", "metal_hit_04", "metal_slam_01"]))
	var sc := _load_file(dir + "scrape_loop.mp3")
	if sc is AudioStreamMP3:
		(sc as AudioStreamMP3).loop = true
		rec_scrape = sc
	print("Recorded crash sounds: %d big, %d medium, %d light, %d rail, %d slam, %d wood, %d glass, %d clank, scrape %s" % [
		rec_big.size(), rec_med.size(), rec_light.size(), rec_rail.size(), rec_slam.size(),
		rec_wood.size() + rec_wood_light.size(), rec_glass.size(), rec_clank.size(), rec_scrape != null])

static func _pack(names: Array) -> Array:
	var out := []
	for n in names:
		out.append("res://sounds/pack/%s.ogg" % n)
	return out

func _load_all(paths: Array) -> Array:
	var out := []
	for p in paths:
		var s := _load_file(p)
		if s:
			out.append(s)
	return out

# straight from the file, so new sounds work without the editor importing them
func _load_file(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var ext := path.get_extension().to_lower()
	if ext == "mp3":
		var m := AudioStreamMP3.new()
		m.data = FileAccess.get_file_as_bytes(path)
		return m if m.data.size() > 0 else null
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	if ext == "wav":
		return _load_wav(path)
	return null

# minimal RIFF reader: 16-bit PCM, mono or stereo
static func _load_wav(path: String) -> AudioStreamWAV:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var pos := 12
	var channels := 1
	var rate := 44100
	var bits := 16
	var pcm := PackedByteArray()
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := b.decode_u32(pos + 4)
		if id == "fmt ":
			channels = b.decode_u16(pos + 10)
			rate = b.decode_u32(pos + 12)
			bits = b.decode_u16(pos + 22)
		elif id == "data":
			pcm = b.slice(pos + 8, pos + 8 + size)
		pos += 8 + size + (size % 2)
	if bits != 16 or pcm.is_empty():
		return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = channels == 2
	w.data = pcm
	return w

func setup(p_car) -> void:
	car = p_car
	_load_recordings()
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		players.append(p)
	for i in 5:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		fx_players.append(p)
	scrape = AudioStreamPlayer.new()
	scrape.volume_db = -60.0
	scrape.bus = "Effects"
	add_child(scrape)
	hiss = AudioStreamPlayer.new()
	hiss.volume_db = -60.0
	hiss.bus = "Effects"
	add_child(hiss)
	thread = Thread.new()
	thread.start(_synth_all)

func _exit_tree() -> void:
	if thread and thread.is_started():
		thread.wait_to_finish()

# ---------------------------------------------------------------- playback
# Two separate pools: the crash itself never gets cut off by the clatter of
# parts falling off (or the glass), which used to take over its players.
var fx_players: Array[AudioStreamPlayer] = []
var loud := {}        # player -> [volume it started at, time it started]

func _play(list: Array, vol: float, pitch: float, pool: Array[AudioStreamPlayer] = []) -> void:
	if list.is_empty():
		return
	if pool.is_empty():
		pool = players
	# a free player if there is one, otherwise the one that's quietest by now
	# (an old, fading sound), so a soft knock never silences a big crash
	var now := Time.get_ticks_msec() / 1000.0
	var best: AudioStreamPlayer = null
	var best_v := 1e9
	for p in pool:
		if not p.playing:
			best = p
			break
		var info: Array = loud.get(p, [0.0, 0.0])
		var left: float = info[0] * exp(-(now - info[1]) * 1.2)
		if left < best_v:
			best_v = left
			best = p
	if best.playing and best_v > vol * 1.5:
		return                      # everything still ringing is much louder: skip this one
	best.stream = list[rng.randi() % list.size()]
	best.volume_db = linear_to_db(clampf(vol, 0.001, 1.0)) + 3.0
	best.pitch_scale = pitch
	best.play()
	loud[best] = [vol, now]

# a collision: vn = closing speed in m/s; kind "tree" / "rail" / "ground"
# Every hit is a proper crash recording (crunch of the body); metal clangs
# and wood splinters are only added on top, quieter.
func crash(vn: float, kind: String) -> void:
	var k := clampf(vn / 16.0, 0.15, 1.0)
	var big: Array = rec_big if not rec_big.is_empty() else heavy
	var med: Array = rec_med if not rec_med.is_empty() else heavy
	var small: Array = rec_crash_light if not rec_crash_light.is_empty() else light
	var sheet: Array = rec_rail if not rec_rail.is_empty() else light
	# the body crunch, sized by the closing speed
	if vn > 13.0:
		_play(big, k, rng.randf_range(0.92, 1.04))
	elif vn > 6.0:
		_play(med, k, rng.randf_range(0.95, 1.08))
	elif vn > 3.0:
		# a lighter crunch: the medium crash pitched up and quieter
		_play(med, k * 0.75, rng.randf_range(1.1, 1.25))
	else:
		_play(small, k, rng.randf_range(0.95, 1.12))
	# layers on top
	match kind:
		"rail":
			_play(sheet, k * 0.55, rng.randf_range(0.9, 1.15), fx_players)
		"ground":
			_play(rec_slam, k * 0.5, rng.randf_range(0.85, 1.05), fx_players)
		"tree":
			_play(rec_wood if vn > 9.0 else rec_wood_light, k * 0.6, rng.randf_range(0.9, 1.1), fx_players)
		_:
			if vn > 13.0:
				_play(rec_slam, k * 0.45, rng.randf_range(0.85, 1.0), fx_players)

func glass(vol := 1.0) -> void:
	_play(rec_glass if not rec_glass.is_empty() else glass_s, vol, rng.randf_range(0.94, 1.06), fx_players)

# a part hitting the ground at world position wp
func clank(wp: Vector3, strength: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var dist: float = cam.global_position.distance_to(wp) if cam else 5.0
	var vol := clampf(strength, 0.05, 1.0) / (1.0 + dist * 0.12)
	if vol > 0.03:
		_play(rec_clank if not rec_clank.is_empty() else clank_s, vol * 0.7, rng.randf_range(0.85, 1.2), fx_players)

func set_loops(scrape_k: float, steam_on: bool, temp: float) -> void:
	if not ready_sounds:
		return
	var sv := clampf(scrape_k, 0.0, 1.0)
	scrape.volume_db = lerpf(scrape.volume_db, linear_to_db(max(sv * 0.9, 0.0005)), 0.25)
	scrape.pitch_scale = 0.85 + sv * 0.4
	var hv: float = (0.25 + clampf(temp - 0.6, 0.0, 0.6)) if steam_on else 0.0
	hiss.volume_db = lerpf(hiss.volume_db, linear_to_db(max(hv, 0.0005)), 0.08)

# ---------------------------------------------------------------- synthesis (worker thread)
func _synth_all() -> void:
	var t0 := Time.get_ticks_msec()
	var r := RandomNumberGenerator.new()
	r.seed = 4321
	var h: Array[AudioStreamWAV] = []
	var l: Array[AudioStreamWAV] = []
	var g: Array[AudioStreamWAV] = []
	var c: Array[AudioStreamWAV] = []
	for i in 3:
		h.append(_wav(_crash(r, 1.5, 1.0)))
	for i in 3:
		l.append(_wav(_crash(r, 0.6, 0.4)))
	for i in 2:
		g.append(_wav(_glass(r)))
	for i in 3:
		c.append(_wav(_clank(r)))
	var sc := _wav(_scrape_loop(r))
	var hs := _wav(_hiss_loop(r))
	print("Crash sounds synthesised in %d ms (background)" % (Time.get_ticks_msec() - t0))
	# dev aid: --dumpsounds=dir writes them out as .wav files to listen to
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dumpsounds="):
			var d := a.substr(13)
			for i in h.size():
				h[i].save_to_wav(d.path_join("crash_heavy_%d.wav" % i))
			for i in l.size():
				l[i].save_to_wav(d.path_join("crash_light_%d.wav" % i))
			for i in g.size():
				g[i].save_to_wav(d.path_join("glass_%d.wav" % i))
			for i in c.size():
				c[i].save_to_wav(d.path_join("clank_%d.wav" % i))
			sc.save_to_wav(d.path_join("scrape_loop.wav"))
	call_deferred("_install", h, l, g, c, sc, hs)

func _install(h, l, g, c, sc: AudioStreamWAV, hs: AudioStreamWAV) -> void:
	heavy = h
	light = l
	glass_s = g
	clank_s = c
	for w in [sc, hs]:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2 - 1200
	scrape.stream = rec_scrape if rec_scrape else sc
	scrape.play()
	hiss.stream = hs
	hiss.play()
	ready_sounds = true

static func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

# resonant band-pass (constant 0 dB peak) run over the whole excitation, added in
static func _resonate(src: PackedFloat32Array, dst: PackedFloat32Array, f: float, q: float, gain: float) -> void:
	var w0 := TAU * f / RATE
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in src.size():
		var x := src[i]
		var y := b0 * (x - x2) - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		dst[i] += y * gain

# a short burst of noise (one small impact) added into the excitation
static func _burst(r: RandomNumberGenerator, e: PackedFloat32Array, t0: float, amp: float, dur: float) -> void:
	var i0 := int(t0 * RATE)
	var n := int(dur * RATE)
	for i in range(i0, mini(e.size(), i0 + n)):
		var k := float(i - i0) / n
		e[i] += r.randf_range(-1.0, 1.0) * amp * (1.0 - k) * (1.0 - k)

# short outdoor echoes (trees, road) + a little diffuse tail
static func _echo(a: PackedFloat32Array, wet: float) -> void:
	var taps := [[0.019, 0.38], [0.037, 0.27], [0.061, 0.2], [0.089, 0.14], [0.131, 0.09], [0.187, 0.06]]
	var src := a.duplicate()
	for t in taps:
		var d := int(t[0] * RATE)
		var gn: float = t[1] * wet
		var lp := 0.0
		for i in range(d, a.size()):
			lp += (src[i - d] - lp) * 0.45      # reflections lose the top end
			a[i] += lp * gn

func _crash(r: RandomNumberGenerator, length: float, size: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var e := PackedFloat32Array()
	e.resize(n)
	# the first slam: a dense cluster of impacts
	for i in int(40 * size + 10):
		_burst(r, e, r.randf() * 0.02, r.randf_range(0.5, 1.0) * size, r.randf_range(0.001, 0.004))
	# the crumple: lots of small hits, thinning out as the car settles
	var t := 0.0
	var rate := 700.0 * size + 150.0
	while t < length * 0.6:
		t += -log(max(r.randf(), 1e-4)) / rate
		rate *= 0.993
		var amp := pow(r.randf(), 3.0) * (1.0 - t / (length * 0.6)) * 0.9
		_burst(r, e, t, amp, r.randf_range(0.0008, 0.003))
	# a few secondary hits (parts slamming, the car rocking back)
	for i in int(3 * size + 1):
		var ts := r.randf_range(0.06, 0.45) * length
		for j in 8:
			_burst(r, e, ts + r.randf() * 0.012, r.randf_range(0.3, 0.8) * size, r.randf_range(0.001, 0.004))
	# the panels' resonances: dense, inharmonic, log-spaced 90 Hz .. 7 kHz
	var out := PackedFloat32Array()
	out.resize(n)
	var modes := 18
	for m in modes:
		var k := float(m) / (modes - 1)
		var f := 90.0 * pow(78.0, k) * r.randf_range(0.88, 1.12) * (1.25 - size * 0.25)
		var q := lerpf(5.0, 38.0, k) * r.randf_range(0.7, 1.3)
		var gain := lerpf(1.6, 0.55, k) * r.randf_range(0.6, 1.2)
		_resonate(e, out, f, q, gain)
	# raw grit on top (the crackle itself)
	for i in n:
		out[i] += e[i] * 0.25
	# the heavy body thump
	var lp := 0.0
	for i in n:
		var tt := float(i) / RATE
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.04
		out[i] += (sin(TAU * (62.0 - 25.0 * min(tt * 4.0, 1.0)) * tt) * 1.3 + lp * 4.0) * exp(-tt * 9.0) * size
	# tearing metal: a wavering screech while it folds
	if size > 0.6:
		var y1 := 0.0
		var y2 := 0.0
		var ph := 0.0
		for i in int(min(length * 0.55, 0.7) * RATE):
			var tt := float(i) / RATE
			ph += TAU * 7.0 / RATE
			var f := 1300.0 + sin(ph) * 380.0 + r.randf_range(-60.0, 60.0)
			var w0 := TAU * f / RATE
			var c := 2.0 * 0.992 * cos(w0)
			var y := r.randf_range(-1.0, 1.0) * 0.012 + c * y1 - 0.984 * y2
			y2 = y1
			y1 = y
			out[i] += y * smoothstep(0.0, 0.05, tt) * exp(-tt * 3.0) * 0.5
	_echo(out, 0.8)
	# normalise and soft-clip for weight
	var peak := 0.0
	for i in n:
		peak = max(peak, abs(out[i]))
	var gn: float = 1.6 / max(peak, 1e-4)
	for i in n:
		out[i] = tanh(out[i] * gn) * 0.92
		if i > n - 1200:
			out[i] *= float(n - i) / 1200.0
	return out

func _glass(r: RandomNumberGenerator) -> PackedFloat32Array:
	var length := 1.6
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# the break: a sharp crack
	var hp := 0.0
	for i in int(0.05 * RATE):
		var x := r.randf_range(-1.0, 1.0)
		hp += (x - hp) * 0.3
		out[i] += (x - hp) * exp(-float(i) / RATE * 70.0) * 1.4
	# hundreds of shards: short bright pings, thick at first then thinning out
	for s in 220:
		var t0 := pow(r.randf(), 2.2) * 1.1
		var f := r.randf_range(2200.0, 9000.0)
		var a := r.randf_range(0.04, 0.22) * (1.0 - t0 / 1.3)
		var dec := r.randf_range(35.0, 110.0)
		var i0 := int(t0 * RATE)
		for i in range(i0, mini(n, i0 + int(0.09 * RATE))):
			var dt := float(i - i0) / RATE
			out[i] += sin(TAU * f * dt) * exp(-dt * dec) * a
	# bits bouncing on the road a moment later
	for s in 25:
		var t0 := r.randf_range(0.25, 1.3)
		var i0 := int(t0 * RATE)
		var f := r.randf_range(3000.0, 7000.0)
		for i in range(i0, mini(n, i0 + int(0.05 * RATE))):
			var dt := float(i - i0) / RATE
			out[i] += sin(TAU * f * dt) * exp(-dt * 90.0) * 0.07
	_echo(out, 0.6)
	for i in n:
		out[i] = tanh(out[i] * 1.3) * 0.85
	return out

func _clank(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.6 * RATE)
	var e := PackedFloat32Array()
	e.resize(n)
	for i in 6:
		_burst(r, e, r.randf() * 0.006, r.randf_range(0.6, 1.0), 0.002)
	if r.randf() < 0.6:   # it bounces once
		var tb := r.randf_range(0.08, 0.2)
		for i in 4:
			_burst(r, e, tb + r.randf() * 0.005, 0.4, 0.002)
	var out := PackedFloat32Array()
	out.resize(n)
	for m in 9:
		var f := r.randf_range(280.0, 3800.0)
		_resonate(e, out, f, r.randf_range(25.0, 70.0), r.randf_range(0.5, 1.2))
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.08
		out[i] += lp * exp(-t * 30.0) * 1.5 + e[i] * 0.2
	_echo(out, 0.5)
	var peak := 0.0
	for v in out:
		peak = max(peak, abs(v))
	for i in n:
		out[i] = tanh(out[i] / max(peak, 1e-4) * 1.3) * 0.85
	return out

# grinding metal: stick-slip impacts (jittery ~60 Hz) through metal resonances
func _scrape_loop(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(1.5 * RATE)
	var e := PackedFloat32Array()
	e.resize(n)
	var t := 0.0
	while t < 1.5:
		t += r.randf_range(0.008, 0.024)
		_burst(r, e, t, r.randf_range(0.2, 1.0), r.randf_range(0.001, 0.003))
	for i in n:
		e[i] += r.randf_range(-1.0, 1.0) * 0.08
	var out := PackedFloat32Array()
	out.resize(n)
	for f in [850.0, 1330.0, 1910.0, 2650.0, 3480.0, 4600.0]:
		_resonate(e, out, f * r.randf_range(0.95, 1.05), r.randf_range(12.0, 30.0), 0.8)
	var peak := 0.0
	for v in out:
		peak = max(peak, abs(v))
	for i in n:
		out[i] = tanh(out[i] / max(peak, 1e-4) * 1.5) * 0.7
	_crossfade_loop(out)
	return out

func _hiss_loop(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.5
		out[i] = (nz - lp) * 0.6
	_crossfade_loop(out)
	return out

# blend the end into the start so the loop has no click (loop ends 1200 early)
static func _crossfade_loop(a: PackedFloat32Array) -> void:
	var m := 1200
	var n := a.size()
	for i in m:
		var k := float(i) / m
		a[i] = a[i] * k + a[n - m + i] * (1.0 - k)

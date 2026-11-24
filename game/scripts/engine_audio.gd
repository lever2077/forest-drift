# Synthesised V6 engine note + tyre squeal using an AudioStreamGenerator.
extends AudioStreamPlayer

var car
var playback: AudioStreamGeneratorPlayback
var rate := 22050.0
var phase := 0.0
var phase2 := 0.0
var sq_phase := 0.0
var lp := 0.0
var noise_lp := 0.0
var cur_rpm := 900.0
var cur_load := 0.0
var cur_sq := 0.0
var rng := RandomNumberGenerator.new()

func setup(p_car) -> void:
	car = p_car
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -6.0
	bus = "Engine"
	play()
	playback = get_stream_playback()
	# tyre squeal on its own player so it has its own volume slider
	tyre_player = AudioStreamPlayer.new()
	var gen2 := AudioStreamGenerator.new()
	gen2.mix_rate = rate
	gen2.buffer_length = 0.12
	tyre_player.stream = gen2
	tyre_player.volume_db = -6.0
	tyre_player.bus = "Tyres"
	add_child(tyre_player)
	tyre_player.play()
	tyre_playback = tyre_player.get_stream_playback()

var tyre_player: AudioStreamPlayer
var tyre_playback: AudioStreamGeneratorPlayback

func _process(_delta: float) -> void:
	if playback == null or car == null:
		return
	var frames := playback.get_frames_available()
	var tyre_frames := tyre_playback.get_frames_available() if tyre_playback else 0
	var target_rpm: float = car.rpm
	var target_load: float = car.in_throttle if car.gear != -1 else car.in_brake
	var target_sq: float = car.rear_slide if car.on_road else 0.0
	for i in frames:
		cur_rpm += (target_rpm - cur_rpm) * 0.002
		cur_load += (target_load - cur_load) * 0.001
		cur_sq += (target_sq - cur_sq) * 0.0015
		# V6 four-stroke: 3 combustion pulses per crank revolution
		var f := cur_rpm / 60.0 * 3.0
		phase = fmod(phase + f / rate, 1.0)
		phase2 = fmod(phase2 + f * 0.5 / rate, 1.0)
		var saw := phase * 2.0 - 1.0
		var pulse := 1.0 if phase < 0.3 else -0.35
		var s := saw * 0.35 + pulse * 0.25 + sin(phase2 * TAU) * 0.35
		var n := rng.randf_range(-1.0, 1.0)
		s += n * (0.08 + 0.25 * cur_load)
		# low-pass: brighter under load / high rpm
		var cutoff := 0.08 + 0.25 * cur_load + cur_rpm / 7500.0 * 0.25
		lp += (s - lp) * cutoff
		var eng := lp * (0.35 + 0.45 * cur_load)
		# tyre squeal: wavering tone + hiss
		sq_phase = fmod(sq_phase + (820.0 + sin(phase2 * 7.0) * 60.0 + n * 40.0) / rate, 1.0)
		noise_lp += (n - noise_lp) * 0.3
		var sq := (sin(sq_phase * TAU) * 0.5 + noise_lp * 0.6) * cur_sq * 0.35
		var out := clampf(eng, -1.0, 1.0)
		playback.push_frame(Vector2(out, out))
		if i < tyre_frames:
			var so := clampf(sq, -1.0, 1.0)
			tyre_playback.push_frame(Vector2(so, so))

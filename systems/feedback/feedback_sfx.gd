class_name FeedbackSfx
extends RefCounted
## Small synthesized sounds for game feedback, so every action has an audible
## answer before real audio exists: chimes, zaps, whooshes, thumps.
## FeedbackSfx.play(node, &"chime") plays one; streams are built once and cached.

const RATE := 22050

static var _cache: Dictionary = {}


static func play(owner: Node, id: StringName, volume_db := -6.0, pitch := 1.0) -> void:
	if owner == null or not owner.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = get_stream(id)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


static func get_stream(id: StringName) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var samples: PackedFloat32Array
	match id:
		&"chime":
			samples = _notes([880.0, 1318.5], 0.08, 0.45)
		&"objective":
			samples = _notes([659.3, 830.6, 987.8, 1318.5], 0.07, 0.6)
		&"hint":
			samples = _notes([740.0, 987.8], 0.06, 0.3, 0.5)
		&"level_up":
			samples = _notes([523.3, 659.3, 784.0, 1046.5, 1318.5], 0.09, 1.1)
		&"pickup":
			samples = _notes([987.8, 1480.0], 0.045, 0.25, 0.7)
		&"gold":
			samples = _notes([1568.0, 2093.0, 2637.0], 0.035, 0.3, 0.5)
		&"clink":
			samples = _notes([2349.0, 3136.0], 0.025, 0.2, 0.6)
		&"spark":
			samples = _zap(0.12, 1800.0, 600.0, 0.6)
		&"zap":
			samples = _zap(0.35, 1200.0, 180.0, 0.9)
		&"whoosh":
			samples = _whoosh(0.32)
		&"whoomp":
			samples = _whoomp(0.6)
		&"hit":
			samples = _thump(0.12, 180.0, 0.5)
		&"crit":
			samples = _thump(0.18, 120.0, 0.8)
		&"hurt":
			samples = _thump(0.22, 90.0, 0.9)
		&"kill":
			samples = _thump(0.3, 70.0, 0.7)
		&"dud":
			samples = _notes([196.0, 164.8], 0.07, 0.2, 0.4)
		_:
			samples = _notes([440.0], 0.0, 0.2)
	var stream := _to_wav(samples)
	_cache[id] = stream
	return stream


## A short run of bell-like notes, each starting `step` seconds after the last.
static func _notes(freqs: Array, step: float, length: float, gain := 0.6) -> PackedFloat32Array:
	var total := int((length + step * freqs.size()) * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	for n in freqs.size():
		var start := int(n * step * RATE)
		var f: float = freqs[n]
		for i in range(start, total):
			var t := float(i - start) / RATE
			var env := exp(-t * 6.0) * minf(t * 400.0, 1.0)
			out[i] += gain * env * (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t) + 0.1 * sin(TAU * f * 3.0 * t)) / freqs.size() * 1.6
	return out


## An electric crackle: a falling square-ish tone chopped by noise.
static func _zap(length: float, f0: float, f1: float, gain: float) -> PackedFloat32Array:
	var total := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in total:
		var k := float(i) / total
		phase += TAU * lerpf(f0, f1, sqrt(k)) / RATE
		var tone := signf(sin(phase)) * 0.5 + sin(phase * 2.03) * 0.3
		var crackle := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.35 else 0.0
		out[i] = gain * (1.0 - k) * (tone * 0.6 + crackle * 0.5)
	return out


## Filtered noise that swells and fades: a shove of air.
static func _whoosh(length: float) -> PackedFloat32Array:
	var total := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var low := 0.0
	for i in total:
		var k := float(i) / total
		var cutoff := lerpf(0.05, 0.25, sin(k * PI))
		low += (rng.randf_range(-1.0, 1.0) - low) * cutoff
		out[i] = low * sin(k * PI) * 1.8
	return out


## A low burst of noise with a falling rumble: fire catching.
static func _whoomp(length: float) -> PackedFloat32Array:
	var total := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var low := 0.0
	for i in total:
		var k := float(i) / total
		var t := float(i) / RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.08
		var env := minf(t * 30.0, 1.0) * exp(-k * 3.5)
		out[i] = env * (low * 2.2 + 0.4 * sin(TAU * lerpf(110.0, 50.0, k) * t))
	return out


## A punchy impact: a quick pitch drop plus a click.
static func _thump(length: float, freq: float, gain: float) -> PackedFloat32Array:
	var total := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var phase := 0.0
	for i in total:
		var k := float(i) / total
		phase += TAU * freq * (1.0 + 2.0 * (1.0 - k) * (1.0 - k)) / RATE
		var click := rng.randf_range(-1.0, 1.0) * maxf(0.0, 1.0 - k * 12.0)
		out[i] = gain * (sin(phase) * exp(-k * 5.0) + click * 0.6)
	return out


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

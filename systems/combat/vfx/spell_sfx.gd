class_name SpellSfx
extends RefCounted
## Procedurally synthesised spell sounds, so spells have a voice before real
## audio exists. Each sound is built once on first use and cached.
##
## Sounds: &"zap" (a bolt leaves the hand), &"crack" (impact), &"hum" (charging
## loop), &"ping" (full charge), &"crackle" (flight loop).

const RATE := 22050

static var _cache: Dictionary = {}


static func get_stream(sound: StringName) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _build(sound)
	return _cache[sound]


## Plays a one-shot (or a loop, which the caller stops) at a world position.
static func play_at(parent: Node, position: Vector3, sound: StringName, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D:
	if parent == null or not parent.is_inside_tree() or sound == &"":
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = get_stream(sound)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.unit_size = 8.0
	player.max_distance = 70.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(player)
	player.global_position = position
	player.play()
	if player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		player.finished.connect(player.queue_free)
	return player


static func _build(sound: StringName) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound)
	var samples: PackedFloat32Array
	var loop := false
	match sound:
		&"zap":
			samples = _zap(rng)
		&"crack":
			samples = _crack(rng)
		&"hum":
			samples = _hum(rng)
			loop = true
		&"ping":
			samples = _ping()
		&"crackle":
			samples = _crackle(rng)
			loop = true
		_:
			samples = PackedFloat32Array([0.0])
	return _to_wav(samples, loop)


## A bright descending chirp over electric buzz and fizz.
static func _zap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.26)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var buzz := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := lerpf(2600.0, 260.0, pow(t / 0.26, 0.45))
		phase += TAU * freq / RATE
		buzz += TAU * 118.0 / RATE
		var env := exp(-t * 16.0) * minf(t * 900.0, 1.0)
		var chirp := sin(phase) * 0.55
		var square := signf(sin(buzz)) * 0.18 * exp(-t * 9.0)
		var fizz := rng.randf_range(-1, 1) * 0.35 * exp(-t * 22.0)
		out[i] = (chirp + square + fizz) * env
	return out


## A sharp snap with a low thump and a crackling tail.
static func _crack(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1, 1)
		# Crude high-pass so the snap reads as a crack, not a hiss.
		var snap := (noise - last) * 0.6 * exp(-t * 55.0)
		last = noise
		phase += TAU * lerpf(110.0, 42.0, minf(t / 0.3, 1.0)) / RATE
		var thump := sin(phase) * 0.75 * exp(-t * 11.0) * minf(t * 400.0, 1.0)
		var click := 0.0
		if rng.randf() < 0.012 * exp(-t * 6.0):
			click = rng.randf_range(-0.7, 0.7)
		out[i] = snap + thump + click
	return out


## A warm, wavering hum that loops cleanly (whole cycles in one second).
static func _hum(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var wobble := 1.0 + 0.25 * sin(TAU * 6.0 * t)
		var tone := sin(TAU * 110.0 * t) * 0.35 + sin(TAU * 220.0 * t) * 0.18 + sin(TAU * 330.0 * t) * 0.08
		var hiss := rng.randf_range(-1, 1) * 0.04
		out[i] = (tone * wobble + hiss) * 0.7
	return out


## A glassy bell for "fully charged".
static func _ping() -> PackedFloat32Array:
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 5.0) * minf(t * 600.0, 1.0)
		var shimmer := 1.0 + 0.003 * sin(TAU * 7.0 * t)
		out[i] = (sin(TAU * 1320.0 * t * shimmer) * 0.5 + sin(TAU * 1980.0 * t) * 0.28 + sin(TAU * 2640.0 * t) * 0.15) * env
	return out


## Sparse electric clicks for a bolt in flight.
static func _crackle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := RATE / 2
	var out := PackedFloat32Array()
	out.resize(n)
	var decay := 0.0
	for i in n:
		if rng.randf() < 0.004:
			decay = rng.randf_range(0.3, 0.8)
		decay *= 0.985
		out[i] = rng.randf_range(-1, 1) * decay * 0.5
	return out


static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.9, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

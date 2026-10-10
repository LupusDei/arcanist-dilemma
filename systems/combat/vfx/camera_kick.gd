class_name CameraKick
extends Node
## Screen shake and hit-stop for the player's own spells. Shake nudges the
## active camera's h/v offsets (and puts them back); hit-stop briefly slows
## time on big hits.

const MAX_OFFSET := 0.22
const DECAY := 3.2

static var _hitstop_until := 0.0

var trauma := 0.0
var _camera: Camera3D
var _noise_t := 0.0


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != _camera:
		_reset()
		_camera = camera
	if _camera == null:
		return
	if trauma <= 0.0:
		return
	trauma = maxf(trauma - DECAY * delta, 0.0)
	_noise_t += delta * 40.0
	var shake := trauma * trauma
	_camera.h_offset = sin(_noise_t * 1.3) * MAX_OFFSET * shake
	_camera.v_offset = cos(_noise_t * 1.7) * MAX_OFFSET * shake
	if trauma <= 0.0:
		_reset()


func _exit_tree() -> void:
	_reset()


func _reset() -> void:
	if _camera and is_instance_valid(_camera):
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


## Freezes time to `scale` for `seconds` of real time. Overlapping calls extend it.
static func hitstop(tree: SceneTree, seconds := 0.06, slow := 0.05) -> void:
	if tree == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var already := _hitstop_until > now
	_hitstop_until = maxf(_hitstop_until, now + seconds)
	if already:
		return
	Engine.time_scale = slow
	_release_later(tree)


static func _release_later(tree: SceneTree) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var timer := tree.create_timer(maxf(_hitstop_until - now, 0.01), true, false, true)
	timer.timeout.connect(func() -> void:
		if Time.get_ticks_msec() / 1000.0 + 0.005 < _hitstop_until:
			_release_later(tree)
		else:
			Engine.time_scale = 1.0)

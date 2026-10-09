extends Node3D
## Slow bob and sway for buildings torn loose by a bleed.

var _base := Vector3.ZERO
var _base_rotation := Vector3.ZERO
var _phase := 0.0


func _ready() -> void:
	_base = position
	_base_rotation = rotation
	_phase = fposmod(position.x * 0.37 + position.z * 0.21, TAU)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 + _phase
	position.y = _base.y + sin(t * 0.7) * 0.35
	rotation.x = _base_rotation.x + sin(t * 0.5) * 0.02
	rotation.z = _base_rotation.z + cos(t * 0.6) * 0.02

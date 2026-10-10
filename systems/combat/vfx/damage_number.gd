class_name DamageNumber
extends Label3D
## A number that pops off whatever the player's spell hit: punches in, drifts
## up and sideways, fades. Crits are bigger, gold and shake; kills say so.

const LIFETIME := 0.9

var _age := 0.0
var _velocity := Vector3.ZERO
var _base_scale := 1.0
var _crit := false


static func spawn(parent: Node, at: Vector3, amount: float, color: Color, crit := false, killed := false) -> DamageNumber:
	if parent == null or not parent.is_inside_tree() or amount < 0.5:
		return null
	var label := DamageNumber.new()
	label.text = "%d%s" % [roundi(amount), "!" if crit else ""]
	if killed:
		label.text += "\nslain"
	label._crit = crit
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 54 if crit else 40
	label.outline_size = 14
	label.outline_modulate = Color(0.05, 0.03, 0.1, 0.9)
	label.modulate = Color(1.0, 0.85, 0.3) if crit else color.lerp(Color.WHITE, 0.45)
	label.render_priority = 10
	label.outline_render_priority = 9
	label.line_spacing = -12
	parent.add_child(label)
	label.global_position = at + Vector3(randf_range(-0.25, 0.25), 0.3, randf_range(-0.25, 0.25))
	label._velocity = Vector3(randf_range(-0.8, 0.8), 2.4, randf_range(-0.8, 0.8))
	label._base_scale = 1.35 if crit else 1.0
	return label


func _process(delta: float) -> void:
	_age += delta
	var t := _age / LIFETIME
	global_position += _velocity * delta
	_velocity.y -= 3.5 * delta
	# Punch in big, settle, then shrink away.
	var punch := 1.0 + 0.9 * maxf(1.0 - _age / 0.12, 0.0)
	scale = Vector3.ONE * _base_scale * punch * (1.0 - smoothstep(0.75, 1.0, t) * 0.5)
	if _crit:
		position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.01 * maxf(1.0 - t * 2.0, 0.0)
	modulate.a = 1.0 - smoothstep(0.6, 1.0, t)
	outline_modulate.a = modulate.a * 0.9
	if _age >= LIFETIME:
		queue_free()

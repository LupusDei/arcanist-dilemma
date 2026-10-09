class_name KnockbackEffect
extends SpellEffect
## Pushes the target away from the impact (or caster). Negative force pulls.

@export var force := 8.0
@export var upward := 2.0
## Push away from the caster instead of from the impact point.
@export var from_caster := false


func apply(target: HealthComponent, context: SpellContext, impact: Vector3) -> void:
	var from := context.origin if from_caster else impact
	var away := target.get_target_position() - from
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = target.get_target_position() - context.origin
		away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3.FORWARD
	target.knock_back(away.normalized() * force * context.force_power + Vector3.UP * upward)


func describe(_context: SpellContext) -> String:
	return "pulls" if force < 0.0 else "knocks back"

class_name StatusEffect
extends SpellEffect
## Applies a status (stun, slow, root, burn, charm, regen, haste).

@export var kind := Status.Kind.STUN
@export var duration := 1.0
## Slow/haste fraction, or damage/healing per second for burn/regen.
@export var magnitude := 0.0
## Scale magnitude by caster power (burn and regen do, slows don't).
@export var scales_with_power := false


func apply(target: HealthComponent, context: SpellContext, _impact: Vector3) -> void:
	var value := magnitude * (context.power * context.scale if scales_with_power else 1.0)
	target.apply_status(kind, duration, value, context.caster)


func describe(_context: SpellContext) -> String:
	return "%s for %.1fs" % [Status.name_of(kind), duration]

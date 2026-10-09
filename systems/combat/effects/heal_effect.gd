class_name HealEffect
extends SpellEffect
## Restores health now, or over time via the REGEN status.

@export var amount := 20.0
## > 0 spreads the healing over this many seconds.
@export var over_seconds := 0.0


func apply(target: HealthComponent, context: SpellContext, _impact: Vector3) -> void:
	var total := amount * context.power * context.scale
	if over_seconds > 0.0:
		target.apply_status(Status.Kind.REGEN, over_seconds, total / over_seconds, context.caster)
	else:
		target.heal(total)


func describe(context: SpellContext) -> String:
	var total := roundi(amount * context.power)
	return "heals %d over %.0fs" % [total, over_seconds] if over_seconds > 0.0 else "heals %d" % total

class_name WardEffect
extends SpellEffect
## Shields the target with a ward that absorbs damage before health.

@export var amount := 30.0
@export var duration := 8.0


func apply(target: HealthComponent, context: SpellContext, _impact: Vector3) -> void:
	target.add_ward(amount * context.power * context.scale, duration)


func describe(context: SpellContext) -> String:
	return "ward absorbing %d for %.0fs" % [roundi(amount * context.power), duration]

class_name Hit
extends RefCounted
## One packet of damage on its way to a HealthComponent.
## Enemies can deal damage with `health.take_damage(Hit.new(10.0, DamageType.Kind.PHYSICAL, self))`.

var amount: float
var damage_type: DamageType.Kind
## The node that caused the hit (the caster or attacker), used for kill credit.
var source: Node
var is_crit := false
## The spell that caused the hit, if any.
var spell: SpellData
## Hits over this fraction of max health interrupt casts. Set to INF to never interrupt.
var interrupt_threshold := 0.1


func _init(p_amount := 0.0, p_type := DamageType.Kind.PHYSICAL, p_source: Node = null) -> void:
	amount = p_amount
	damage_type = p_type
	source = p_source

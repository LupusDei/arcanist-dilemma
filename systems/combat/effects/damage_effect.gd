class_name DamageEffect
extends SpellEffect
## Deals damage of the spell's type, scaled by caster power and crits.

@export var amount := 10.0
## Leave unset to use the spell's damage type.
@export var use_spell_type := true
@export var damage_type := DamageType.Kind.ARCANE
## Extra damage per point of the target's armor (Burn + Metal).
@export var bonus_per_armor := 0.0


func apply(target: HealthComponent, context: SpellContext, _impact: Vector3) -> void:
	var kind: DamageType.Kind = context.spell.damage_type if use_spell_type and context.spell else damage_type
	var total := (amount + bonus_per_armor * target.armor) * context.damage_multiplier(kind)
	var hit := Hit.new(total, kind, context.caster)
	hit.is_crit = context.is_crit
	hit.spell = context.spell
	var taken := target.take_damage(hit)
	if context.caster_node and is_instance_valid(context.caster_node) and taken > 0.0:
		context.caster_node.report_hit(target, taken, context.is_crit, context.spell, context.charge)


func describe(context: SpellContext) -> String:
	var kind: DamageType.Kind = context.spell.damage_type if use_spell_type and context.spell else damage_type
	return "%d %s damage" % [roundi(amount * context.damage_multiplier(kind)), DamageType.name_of(kind).to_lower()]

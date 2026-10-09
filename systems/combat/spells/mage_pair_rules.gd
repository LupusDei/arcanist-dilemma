class_name MagePairRules
extends RefCounted
## Builds a spell for any verb + noun pair that has no authored file in
## data/spells/mage/. The verb decides what the spell does and its damage type;
## the noun decides its shape. Authored pairs always win over these rules.

const NOUN_DELIVERY := {
	&"air": SpellData.Delivery.CONE,
	&"water": SpellData.Delivery.AREA_AT_TARGET,
	&"earth": SpellData.Delivery.AREA_AROUND_CASTER,
	&"metal": SpellData.Delivery.PROJECTILE,
	&"wood": SpellData.Delivery.PROJECTILE,
	&"flesh": SpellData.Delivery.TARGETED,
	&"mind": SpellData.Delivery.TARGETED,
	&"light": SpellData.Delivery.PROJECTILE,
}


static func build(verb: StringName, noun: StringName) -> SpellData:
	var spell := SpellData.new()
	spell.id = StringName("mage_%s_%s" % [verb, noun])
	spell.display_name = "%s %s" % [verb.capitalize(), noun.capitalize()]
	spell.description = "An unnamed pair, shaped by the rules of %s and %s." % [verb, noun]
	spell.path = SpellData.PathTag.MAGE
	spell.verb = verb
	spell.noun = noun
	spell.cost = 12.0
	spell.cast_time = 0.8
	spell.cooldown = 1.0
	spell.cast_range = 18.0
	spell.delivery = NOUN_DELIVERY.get(noun, SpellData.Delivery.PROJECTILE)
	spell.radius = 3.0 if spell.delivery in [SpellData.Delivery.AREA_AT_TARGET, SpellData.Delivery.AREA_AROUND_CASTER] else 0.0
	if spell.delivery == SpellData.Delivery.CONE:
		spell.radius = 6.0
	if noun == &"light":
		spell.projectile_speed = 30.0

	match verb:
		&"burn":
			spell.damage_type = DamageType.Kind.FIRE
			spell.effects = [_damage(14.0), _status(Status.Kind.BURN, 3.0, 4.0, true)]
		&"chill":
			spell.damage_type = DamageType.Kind.COLD
			spell.effects = [_damage(10.0), _status(Status.Kind.SLOW, 3.0, 0.4)]
		&"move":
			spell.damage_type = DamageType.Kind.FORCE
			var push := KnockbackEffect.new()
			push.force = 9.0
			spell.effects = [_damage(8.0), push]
		&"bind":
			spell.damage_type = DamageType.Kind.MIND if noun == &"mind" else DamageType.Kind.ARCANE
			spell.effects = [_damage(4.0), _status(Status.Kind.ROOT, 2.5, 0.0)]
		&"break":
			spell.damage_type = DamageType.Kind.FORCE
			spell.effects = [_damage(22.0)]
			spell.cooldown = 3.0
		&"mend":
			spell.damage_type = DamageType.Kind.ARCANE
			spell.delivery = SpellData.Delivery.SELF
			var heal := HealEffect.new()
			heal.amount = 30.0
			heal.over_seconds = 5.0
			spell.effects = [heal]
		&"reveal":
			spell.damage_type = DamageType.Kind.ARCANE
			spell.effects = [_damage(9.0)]
		&"shape":
			spell.damage_type = DamageType.Kind.ARCANE
			spell.delivery = SpellData.Delivery.SELF
			var ward := WardEffect.new()
			ward.amount = 25.0
			spell.effects = [ward]
	return spell


static func _damage(amount: float) -> DamageEffect:
	var effect := DamageEffect.new()
	effect.amount = amount
	return effect


static func _status(kind: Status.Kind, duration: float, magnitude: float, scales := false) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.kind = kind
	effect.duration = duration
	effect.magnitude = magnitude
	effect.scales_with_power = scales
	return effect

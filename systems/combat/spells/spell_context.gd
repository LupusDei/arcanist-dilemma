class_name SpellContext
extends RefCounted
## Everything an effect needs to know about the cast that produced it.

var spell: SpellData
## The body that cast the spell (kill credit, knockback direction).
var caster: Node3D
var caster_health: HealthComponent
var team := &"player"
## Final multiplier on damage, healing and wards: stats, path scaling, overstrain.
var power := 1.0
## Extra multiplier for force damage (Strength).
var force_power := 1.0
var is_crit := false
var crit_multiplier := 1.5
## Scales this particular delivery: chain falloff, scattered sub-bursts.
var scale := 1.0
## Where the spell came from, for knockback direction.
var origin := Vector3.ZERO


func damage_multiplier(damage_type: DamageType.Kind) -> float:
	var multiplier := power * scale
	if damage_type == DamageType.Kind.FORCE:
		multiplier *= force_power
	if is_crit:
		multiplier *= crit_multiplier
	return multiplier


func with_scale(new_scale: float) -> SpellContext:
	var copy := SpellContext.new()
	copy.spell = spell
	copy.caster = caster
	copy.caster_health = caster_health
	copy.team = team
	copy.power = power
	copy.force_power = force_power
	copy.is_crit = is_crit
	copy.crit_multiplier = crit_multiplier
	copy.scale = new_scale
	copy.origin = origin
	return copy

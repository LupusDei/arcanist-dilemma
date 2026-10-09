class_name SpellData
extends Resource
## One spell, defined entirely in data. Spell files live in res://data/spells/<path>/.
##
## The delivery decides where the spell lands; the effects decide what happens to
## each target it reaches. Path systems (WizardSpellbook, MageCodex,
## SorcererSpellTree) scale a spell's power and cost without changing this file.

enum Delivery {
	PROJECTILE,  ## Flies from the caster toward the aim point.
	TARGETED,  ## Instantly strikes the enemy nearest the aim point (lightning, mind).
	AREA_AT_TARGET,  ## Bursts at the aim point, clamped to range.
	AREA_AROUND_CASTER,  ## A nova centered on the caster.
	CONE,  ## Fans out in front of the caster toward the aim point.
	SELF,  ## Affects only the caster (wards, heals, buffs).
}

enum PathTag { TRICK, WIZARD, MAGE, SORCERER }

@export_group("Identity")
@export var id := &""
@export var display_name := ""
@export_multiline var description := ""
@export var path := PathTag.TRICK
@export var damage_type := DamageType.Kind.ARCANE
@export var icon: Texture2D
## Tints projectiles and bursts. Defaults to the damage type's color when left white.
@export var color := Color.WHITE

@export_group("Casting")
## Arcana or mana spent, or strain gained. 0 for cantrips.
@export var cost := 0.0
## Seconds before the spell resolves. 0 is instant.
@export var cast_time := 0.0
@export var cooldown := 0.0
## Max distance to the aim point or for a projectile's flight.
@export var cast_range := 20.0

@export_group("Delivery")
@export var delivery := Delivery.PROJECTILE
@export var projectile_speed := 18.0
## Projectiles pass through this many targets before stopping.
@export var pierce := 0
## Area radius for AREA_* and CONE. For a projectile, > 0 makes it explode on impact.
@export var radius := 0.0
## Full cone angle in degrees.
@export var cone_angle := 60.0
## Extra targets a hit jumps to (chain lightning).
@export var chain_count := 0
@export var chain_range := 7.0
## Each jump deals this fraction of the previous one.
@export var chain_falloff := 0.8
## Splits into this many smaller bursts around the impact (Scattering Fireball).
@export var scatter_count := 0

@export_group("Effects")
## Applied to each target the spell reaches (or to the caster for SELF).
@export var effects: Array[SpellEffect] = []
## Applied to the caster whenever the spell resolves (self-heal on cast, haste).
@export var caster_effects: Array[SpellEffect] = []

@export_group("Lingering ground")
## > 0 leaves an area where the spell lands for this many seconds (burning ground).
@export var ground_duration := 0.0
@export var ground_radius := 2.0
@export var ground_tick_interval := 0.5
@export var ground_effects: Array[SpellEffect] = []

@export_group("Wizard")
## Highest circle this spell exists in (1 to 7).
@export_range(1, 7) var max_circle := 7
## Set on a variant book's spell (Searing Fireball): the base spell it replaces.
@export var variant_of := &""
## Circle the variant applies from (III or V).
@export_range(1, 7) var variant_circle := 3

@export_group("Mage")
## Verb and noun for a mage pair, such as &"burn" and &"air".
@export var verb := &""
@export var noun := &""

@export_group("Sorcerer")
## Branch in the sorcerer tree: &"storm", &"force" or &"surge".
@export var tree_branch := &""
## Row 0 opens at level 5, then every 3 levels.
@export_range(0, 5) var tree_row := 0
## Every rank in this spell adds 5% to this one.
@export var synergy_id := &""


func get_color() -> Color:
	return DamageType.color_of(damage_type) if color == Color.WHITE else color


## Base damage of the first damage effect, for tooltips.
func get_base_damage() -> float:
	for effect in effects:
		if effect is DamageEffect:
			return effect.amount
	return 0.0


func is_hostile() -> bool:
	return delivery != Delivery.SELF

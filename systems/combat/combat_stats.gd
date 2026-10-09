class_name CombatStats
extends Resource
## The caster numbers spells read. Progression fills these from attributes
## with `from_attributes`, gear and talents add on top.

enum Path { NONE, WIZARD, MAGE, SORCERER }

## Multiplies all spell damage, healing and wards (1.0 = base).
@export var spell_power := 1.0
## Multiplies force damage on top of spell_power (Strength).
@export var force_power := 1.0
@export_range(0.0, 0.5) var crit_chance := 0.05
## Critical hits deal this multiple of normal damage.
@export var crit_multiplier := 1.5
## Bonus cast speed: 0.25 means casts take 1 / 1.25 as long. Capped at 0.75.
@export_range(0.0, 0.75) var cast_speed := 0.0
## Added to the path resource's maximum (Intelligence).
@export var bonus_resource := 0.0
## Multiplies resource regeneration (Wisdom).
@export var resource_regen := 1.0
## Sorcerer strain capacity bonus (Vitality).
@export var bonus_strain_capacity := 0.0
## Wizard prepared spells beyond the 7 on the bar (Intelligence).
@export var bonus_prepared_spells := 0
## Lower chance that a heavy hit interrupts a cast (wizard Wisdom).
@export_range(0.0, 1.0) var interrupt_resistance := 0.0
## Mage chance that a first raw experiment misfires.
@export_range(0.0, 1.0) var misfire_chance := 0.25
## Added to max health (Vitality: +5 per point).
@export var bonus_health := 0.0

const CAST_SPEED_CAP := 0.75
const CRIT_CHANCE_CAP := 0.5


## Builds stats from the five attributes using the mechanics doc's per-point values.
## Every attribute starts at 10, so 10 everywhere gives base numbers.
static func from_attributes(path: Path, strength: int, vitality: int, dexterity: int, intelligence: int, wisdom: int) -> CombatStats:
	var stats := CombatStats.new()
	var str_pts := strength - 10
	var vit_pts := vitality - 10
	var dex_pts := dexterity - 10
	var int_pts := intelligence - 10
	var wis_pts := wisdom - 10

	stats.force_power = 1.0 + 0.01 * str_pts
	stats.bonus_health = 5.0 * vit_pts
	stats.cast_speed = 0.005 * dex_pts
	stats.crit_chance = 0.05 + 0.003 * dex_pts
	stats.bonus_resource = 2.0 * int_pts
	stats.crit_multiplier = 1.5 + 0.01 * int_pts
	stats.resource_regen = 1.0 + 0.01 * wis_pts
	stats.misfire_chance = 0.25

	match path:
		Path.MAGE:
			stats.spell_power = 1.0 + 0.01 * int_pts
			stats.misfire_chance = 0.25 * pow(0.97, wis_pts)
		Path.SORCERER:
			stats.spell_power = 1.0 + 0.01 * vit_pts
			stats.bonus_strain_capacity = floorf(vitality / 2.0)
		Path.WIZARD:
			stats.cast_speed += 0.01 * wis_pts
			stats.interrupt_resistance = 0.01 * wis_pts
			stats.bonus_prepared_spells = floori(intelligence / 25.0)

	stats.cast_speed = clampf(stats.cast_speed, 0.0, CAST_SPEED_CAP)
	stats.crit_chance = clampf(stats.crit_chance, 0.0, CRIT_CHANCE_CAP)
	stats.interrupt_resistance = clampf(stats.interrupt_resistance, 0.0, 0.9)
	stats.misfire_chance = clampf(stats.misfire_chance, 0.0, 1.0)
	return stats

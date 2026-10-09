class_name ItemStats
extends RefCounted
## Applies worn gear to the progression and combat systems.
##
## Combat and progression are looked up by class name and written through
## property names, so the items system compiles on its own and the real
## classes drop in when they are merged.
##
## Gear attributes add to the character's attributes before
## CombatStats.from_attributes runs (so +Int on a ring raises a mage's spell
## power exactly like a spent point). Percent stats add on top.

## CombatStats.Path values.
const PATH_ENUM := {"": 0, "arcanist": 0, "wizard": 1, "mage": 2, "sorcerer": 3}
## Resistance stat -> DamageType.Kind value (PHYSICAL 0, FIRE 1, COLD 2, LIGHTNING 3, FORCE 4, ARCANE 5, MIND 6).
const RESIST_KINDS := {&"resist_fire": 1, &"resist_cold": 2, &"resist_lightning": 3, &"resist_arcane": 5, &"resist_mind": 6}
const HEALTH_PER_VITALITY := 5.0
const CAST_SPEED_CAP := 0.75
const CRIT_CHANCE_CAP := 0.5

static var _combat_stats_script: Script
static var _combat_stats_checked := false


## The character's attributes plus gear attributes.
static func attributes_with_gear(base_attributes: Dictionary, gear: Dictionary) -> Dictionary:
	var out := {}
	for a in ItemDefs.ATTRIBUTES:
		out[a] = int(base_attributes.get(a, 10)) + int(gear.get(a, 0.0))
	return out


## CombatStats built from attributes plus gear, or null while combat is not in
## the project. [param path] is "wizard", "mage", "sorcerer" or "" for none yet.
static func build_combat_stats(path: String, base_attributes: Dictionary, gear: Dictionary) -> Resource:
	var script := combat_stats_script()
	if script == null:
		return null
	var a := attributes_with_gear(base_attributes, gear)
	var stats: Resource = script.from_attributes(PATH_ENUM.get(path, 0), a[&"strength"], a[&"vitality"],
			a[&"dexterity"], a[&"intelligence"], a[&"wisdom"])
	apply_to_combat_stats(stats, gear)
	return stats


## Adds gear's percent and flat stats onto an existing CombatStats.
static func apply_to_combat_stats(stats: Object, gear: Dictionary) -> void:
	if stats == null:
		return
	_add(stats, "spell_power", _pct(gear, &"spell_power"))
	_add(stats, "force_power", _pct(gear, &"force_power"))
	_add(stats, "cast_speed", _pct(gear, &"cast_speed"))
	_add(stats, "crit_chance", _pct(gear, &"crit_chance"))
	_add(stats, "crit_multiplier", _pct(gear, &"crit_damage"))
	_add(stats, "bonus_resource", float(gear.get(&"max_resource", 0.0)))
	_add(stats, "resource_regen", _pct(gear, &"resource_regen"))
	_add(stats, "bonus_health", float(gear.get(&"max_health", 0.0)))
	if stats.get("cast_speed") != null:
		stats.set("cast_speed", clampf(stats.get("cast_speed"), 0.0, CAST_SPEED_CAP))
	if stats.get("crit_chance") != null:
		stats.set("crit_chance", clampf(stats.get("crit_chance"), 0.0, CRIT_CHANCE_CAP))


## Health the gear adds: flat health plus 5 per Vitality on gear (progression's
## max_health() only counts spent Vitality).
static func bonus_health(gear: Dictionary) -> float:
	return float(gear.get(&"max_health", 0.0)) + HEALTH_PER_VITALITY * float(gear.get(&"vitality", 0.0))


## Writes max health, armor, resistances and regen onto a combat HealthComponent.
## [param max_health] is the full maximum including gear (see bonus_health).
## Keeps the current health fraction.
static func apply_to_health(health: Object, gear: Dictionary, max_health: float, base_regen := 0.0) -> void:
	if health == null:
		return
	var old_max = health.get("max_health")
	var old_hp = health.get("health")
	health.set("max_health", max_health)
	if old_hp != null and old_max != null and float(old_max) > 0.0 and not is_equal_approx(float(old_max), max_health):
		health.set("health", clampf(float(old_hp) / float(old_max) * max_health, 1.0, max_health))
		if health.has_signal("health_changed"):
			health.emit_signal("health_changed", health.get("health"), max_health)
	health.set("armor", float(gear.get(&"armor", 0.0)))
	health.set("regen_per_second", base_regen + float(gear.get(&"health_regen", 0.0)))
	if health.get("resistances") != null:
		var res := {}
		for stat in RESIST_KINDS:
			var v := float(gear.get(stat, 0.0)) / 100.0
			if v != 0.0:
				res[RESIST_KINDS[stat]] = v
		health.set("resistances", res)


## Gear "+N to a spell" onto a SpellSource (gear_bonus_ranks). A wizard gets +15%
## power per rank; a sorcerer gets extra ranks.
static func apply_to_spell_source(source: Object, bonuses: Dictionary) -> void:
	if source == null or source.get("gear_bonus_ranks") == null:
		return
	source.set("gear_bonus_ranks", bonuses.duplicate())
	if source.has_signal("changed"):
		source.emit_signal("changed")


static func move_speed_multiplier(gear: Dictionary) -> float:
	return 1.0 + _pct(gear, &"move_speed")


## The CombatStats class when combat is in the project.
static func combat_stats_script() -> Script:
	if not _combat_stats_checked:
		_combat_stats_checked = true
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == &"CombatStats":
				_combat_stats_script = load(entry["path"])
	return _combat_stats_script


static func _pct(gear: Dictionary, stat: StringName) -> float:
	return float(gear.get(stat, 0.0)) / 100.0


static func _add(obj: Object, prop: String, amount: float) -> void:
	if amount == 0.0 or obj.get(prop) == null:
		return
	obj.set(prop, float(obj.get(prop)) + amount)

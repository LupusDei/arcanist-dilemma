class_name UiStats
extends RefCounted
## Attribute names, tooltips and derived-stat previews from the mechanics doc.
## The character sheet uses these to show "what the next point gives" while
## points are still pending. Once res://systems/progression/ reports derived
## stats in stats_changed, the sheet shows those instead (see README).

const ATTRIBUTES: Array[StringName] = [&"strength", &"vitality", &"dexterity", &"intelligence", &"wisdom"]
const BASE_VALUE := 10
const POINTS_PER_LEVEL := 5

const NAMES := {
	&"strength": "Strength",
	&"vitality": "Vitality",
	&"dexterity": "Dexterity",
	&"intelligence": "Intelligence",
	&"wisdom": "Wisdom",
}

const SHORT := {
	&"strength": "Str",
	&"vitality": "Vit",
	&"dexterity": "Dex",
	&"intelligence": "Int",
	&"wisdom": "Wis",
}

## Per point, for every path.
const EVERY_PATH := {
	&"strength": "+1% force damage, +0.5% stagger resistance",
	&"vitality": "+5 health, +0.1 health per second",
	&"dexterity": "+0.5% cast speed, +0.3% critical chance, -0.5% Blink cooldown",
	&"intelligence": "+2 maximum resource, +1% critical damage",
	&"wisdom": "+1% resource regeneration, +0.3% to all resistances",
}

const PATH_BONUS := {
	&"vitality": {&"sorcerer": "+1% spell power, +1 strain capacity per 2 points"},
	&"intelligence": {&"mage": "+1% spell power", &"wizard": "+1 prepared spell per 25 points"},
	&"wisdom": {&"wizard": "+1% cast speed, harder to interrupt", &"mage": "Lower misfire chance on experiments"},
}

## Weights for the "Suggested" button, per path.
const SUGGESTED := {
	&"arcanist": {&"vitality": 2, &"dexterity": 1, &"intelligence": 2},
	&"wizard": {&"vitality": 1, &"dexterity": 1, &"intelligence": 2, &"wisdom": 1},
	&"mage": {&"vitality": 1, &"dexterity": 1, &"intelligence": 3},
	&"sorcerer": {&"vitality": 3, &"dexterity": 2},
}

const CAST_SPEED_CAP := 75.0
const CRIT_CHANCE_CAP := 50.0
const RESIST_CAP := 75.0


static func attribute_tooltip(attr: StringName, path: StringName) -> String:
	var text := "%s\nEach point: %s" % [NAMES[attr], EVERY_PATH[attr]]
	var bonus: Dictionary = PATH_BONUS.get(attr, {})
	if bonus.has(path):
		text += "\n%s: %s" % [String(path).capitalize(), bonus[path]]
	elif not bonus.is_empty():
		var parts: PackedStringArray = []
		for p in bonus:
			parts.append("%s %s" % [String(p).capitalize(), bonus[p]])
		text += "\nPath bonus: " + "; ".join(parts)
	return text


static func _over(attrs: Dictionary, attr: StringName) -> int:
	return int(attrs.get(attr, BASE_VALUE)) - BASE_VALUE


static func max_health(level: int, attrs: Dictionary) -> float:
	return 80.0 + 10.0 * (level - 1) + 5.0 * _over(attrs, &"vitality")


static func resource_kind(path: StringName) -> StringName:
	match path:
		&"wizard":
			return &"arcana"
		&"sorcerer":
			return &"strain"
		_:
			return &"mana"


static func resource_max(path: StringName, attrs: Dictionary) -> float:
	match path:
		&"wizard":
			return 150.0 + 2.0 * _over(attrs, &"intelligence")
		&"sorcerer":
			return 100.0 + floorf(int(attrs.get(&"vitality", BASE_VALUE)) / 2.0)
		_:
			return 100.0 + 2.0 * _over(attrs, &"intelligence")


static func spell_power(path: StringName, attrs: Dictionary) -> float:
	match path:
		&"mage":
			return _over(attrs, &"intelligence")
		&"sorcerer":
			return _over(attrs, &"vitality")
		_:
			return 0.0


static func cast_speed(path: StringName, attrs: Dictionary) -> float:
	var v := 0.5 * _over(attrs, &"dexterity")
	if path == &"wizard":
		v += _over(attrs, &"wisdom")
	return minf(v, CAST_SPEED_CAP)


static func crit_chance(attrs: Dictionary) -> float:
	return minf(5.0 + 0.3 * _over(attrs, &"dexterity"), CRIT_CHANCE_CAP)


static func crit_damage(attrs: Dictionary) -> float:
	return 150.0 + _over(attrs, &"intelligence")


static func resistances(attrs: Dictionary) -> float:
	return minf(0.3 * _over(attrs, &"wisdom"), RESIST_CAP)


static func blink_cooldown(attrs: Dictionary) -> float:
	return 8.0 * (1.0 - 0.005 * _over(attrs, &"dexterity"))


## Rows for the character sheet: [label, value text].
static func derived_rows(level: int, path: StringName, attrs: Dictionary) -> Array:
	var kind := resource_kind(path)
	var rows := [
		["Health", "%d" % max_health(level, attrs)],
		[UiTheme.resource_name(kind) + (" capacity" if kind == &"strain" else ""), "%d" % resource_max(path, attrs)],
	]
	if path == &"wizard":
		rows.append(["Spell power", "Set by circle"])
	else:
		rows.append(["Spell power", "+%d%%" % spell_power(path, attrs)])
	rows.append_array([
		["Force damage", "+%d%%" % _over(attrs, &"strength")],
		["Cast speed", "+%.1f%%" % cast_speed(path, attrs)],
		["Critical chance", "%.1f%%" % crit_chance(attrs)],
		["Critical damage", "%d%%" % crit_damage(attrs)],
		["Resistances", "+%.1f%%" % resistances(attrs)],
		["Regeneration", "+%d%%" % _over(attrs, &"wisdom")],
		["Blink cooldown", "%.2fs" % blink_cooldown(attrs)],
	])
	return rows


## Spreads [param points] along the path's suggested weights.
static func suggest(path: StringName, points: int) -> Dictionary:
	var weights: Dictionary = SUGGESTED.get(path, SUGGESTED[&"arcanist"])
	var order: Array[StringName] = []
	for attr in ATTRIBUTES:
		for i in int(weights.get(attr, 0)):
			order.append(attr)
	var result := {}
	for i in points:
		var attr: StringName = order[i % order.size()]
		result[attr] = int(result.get(attr, 0)) + 1
	return result

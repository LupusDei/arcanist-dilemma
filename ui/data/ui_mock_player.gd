class_name UiMockPlayer
extends Node
## Stand-in for the player's game systems so the UI can be built and tested
## before they land. One node plays three roles, with the same signal names
## the real nodes expose:
## - combat's HealthComponent (health_changed, damaged, healed, died)
## - combat's SpellCaster (spell_cast, cast_started, cast_interrupted,
##   cast_failed, cooldown_started, resource_changed, bar_changed)
## - progression (xp_gained, leveled_up, stats_changed)
## See res://ui/README.md for the contract and how to swap in the real nodes.

# HealthComponent
signal health_changed(current: float, maximum: float)
signal damaged(hit: Variant, amount: float)
signal healed(amount: float)
signal died(killer: Node)
# SpellCaster
signal spell_cast(spell: Resource)
signal cast_started(spell: Resource, cast_time: float)
signal cast_interrupted
signal cast_failed(spell: Resource, reason: String)
signal cooldown_started(spell: Resource, duration: float)
signal resource_changed(current: float, maximum: float)
signal bar_changed
# Progression
signal xp_gained(amount: int, xp: int, xp_to_next: int)
signal leveled_up(level: int)
signal stats_changed(stats: Dictionary)

const BAR_SIZE := 8

## Regenerate health and resource (or let strain fade) over time.
@export var regen_enabled := true

var character_name := "Ilsa"
var level := 12
var path: StringName = &"mage"
var specialization: StringName = &"chronos"
var xp := 900
var attributes := {&"strength": 10, &"vitality": 30, &"dexterity": 25, &"intelligence": 40, &"wisdom": 15}
var unspent_attribute_points := 5
var unspent_spell_points := 1
var talent_tree: Dictionary = UiTalentData.chronos_tree()
var talent_choices: Array = [-1, -1, -1, -1, -1, -1]

var current_health := 0.0
var max_health := 0.0
var current_resource := 0.0
var max_resource := 0.0
var caster_resource: StringName = &"mana"
var action_bar: Array = []

var _cooldowns := {}
var _casting: Resource
var _cast_time := 0.0
var _cast_elapsed := 0.0


func _ready() -> void:
	set_path(path)
	current_health = max_health * 0.85


func _process(delta: float) -> void:
	for spell in _cooldowns.keys():
		_cooldowns[spell] = maxf(0.0, _cooldowns[spell] - delta)
		if _cooldowns[spell] <= 0.0:
			_cooldowns.erase(spell)
	if _casting != null:
		_cast_elapsed += delta
		if _cast_elapsed >= _cast_time:
			_finish_cast()
	if not regen_enabled:
		return
	if current_health < max_health:
		_set_health(minf(max_health, current_health + 2.0 * delta))
	if caster_resource == &"strain":
		if current_resource > 0.0 and _casting == null:
			_set_resource(maxf(0.0, current_resource - 10.0 * delta))
	elif current_resource < max_resource:
		_set_resource(minf(max_resource, current_resource + 6.0 * delta))


# --- SpellCaster-style API ---

func get_cast_progress() -> float:
	if _casting == null or _cast_time <= 0.0:
		return 0.0
	return clampf(_cast_elapsed / _cast_time, 0.0, 1.0)


func get_cooldown_remaining(spell: Resource) -> float:
	return _cooldowns.get(spell, 0.0)


func cast_slot(slot: int) -> bool:
	if slot < 0 or slot >= action_bar.size() or action_bar[slot] == null:
		return false
	var spell: UiMockSpell = action_bar[slot]
	if _casting != null:
		cast_failed.emit(spell, "busy")
		return false
	if get_cooldown_remaining(spell) > 0.0:
		cast_failed.emit(spell, "cooldown")
		return false
	if caster_resource != &"strain" and current_resource < spell.cost:
		cast_failed.emit(spell, "resource")
		return false
	if spell.cast_time > 0.0:
		_casting = spell
		_cast_time = spell.cast_time
		_cast_elapsed = 0.0
		cast_started.emit(spell, spell.cast_time)
	else:
		_casting = spell
		_finish_cast()
	return true


func interrupt() -> void:
	if _casting != null:
		_casting = null
		cast_interrupted.emit()


func _finish_cast() -> void:
	var spell: UiMockSpell = _casting
	_casting = null
	if caster_resource == &"strain":
		_set_resource(current_resource + spell.cost)
	else:
		_set_resource(current_resource - spell.cost)
	spell_cast.emit(spell)
	if spell.cooldown > 0.0:
		_cooldowns[spell] = spell.cooldown
		cooldown_started.emit(spell, spell.cooldown)


# --- HealthComponent-style API ---

func take_damage(amount: float) -> void:
	var dealt := minf(amount, current_health)
	_set_health(current_health - dealt)
	damaged.emit({"amount": dealt, "damage_type": "force"}, dealt)
	if current_health <= 0.0:
		died.emit(null)


func heal(amount: float) -> void:
	var gained := minf(amount, max_health - current_health)
	_set_health(current_health + gained)
	healed.emit(gained)


func _set_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func _set_resource(value: float) -> void:
	var cap := max_resource * 1.5 if caster_resource == &"strain" else max_resource
	current_resource = clampf(value, 0.0, cap)
	resource_changed.emit(current_resource, max_resource)


# --- Progression-style API ---

static func xp_for_level(lvl: int) -> int:
	return 150 + 100 * lvl


func get_stats() -> Dictionary:
	return {
		"name": character_name,
		"level": level,
		"xp": xp,
		"xp_to_next": xp_for_level(level),
		"path": path,
		"specialization": specialization,
		"attributes": attributes.duplicate(),
		"unspent_attribute_points": unspent_attribute_points,
		"unspent_spell_points": unspent_spell_points,
		"talent_tree": talent_tree,
		"talent_choices": talent_choices.duplicate(),
	}


func gain_xp(amount: int) -> void:
	xp += amount
	var levels_gained := 0
	while xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
		levels_gained += 1
		unspent_attribute_points += UiStats.POINTS_PER_LEVEL
		unspent_spell_points += 1
	xp_gained.emit(amount, xp, xp_for_level(level))
	for i in levels_gained:
		leveled_up.emit(level - levels_gained + 1 + i)
	if levels_gained > 0:
		_refresh_maxima()
		_set_health(max_health)
		stats_changed.emit(get_stats())


func level_up() -> void:
	gain_xp(xp_for_level(level) - xp)


## Spends pending attribute points, e.g. {&"intelligence": 3}. Returns false
## if it would spend more than are unspent.
func allocate_attributes(points: Dictionary) -> bool:
	var total := 0
	for attr in points:
		if not attributes.has(StringName(attr)) or int(points[attr]) < 0:
			return false
		total += int(points[attr])
	if total > unspent_attribute_points:
		return false
	for attr in points:
		attributes[StringName(attr)] += int(points[attr])
	unspent_attribute_points -= total
	_refresh_maxima()
	health_changed.emit(current_health, max_health)
	resource_changed.emit(current_resource, max_resource)
	stats_changed.emit(get_stats())
	return true


func choose_talent(row: int, choice: int) -> bool:
	var rows: Array = talent_tree.get("rows", [])
	if row < 0 or row >= rows.size() or level < int(rows[row].level):
		return false
	if choice < 0 or choice >= rows[row].options.size():
		return false
	talent_choices[row] = choice
	stats_changed.emit(get_stats())
	return true


## Switches path for the preview: swaps the resource and the action bar.
func set_path(new_path: StringName) -> void:
	path = new_path
	specialization = {&"wizard": &"archivist", &"mage": &"chronos", &"sorcerer": &"stormborn"}.get(path, &"")
	caster_resource = UiStats.resource_kind(path)
	_refresh_maxima()
	current_resource = 0.0 if caster_resource == &"strain" else max_resource * 0.7
	action_bar = _bar_for(path)
	_cooldowns.clear()
	bar_changed.emit()
	resource_changed.emit(current_resource, max_resource)
	health_changed.emit(current_health, max_health)
	stats_changed.emit(get_stats())


func _refresh_maxima() -> void:
	max_health = UiStats.max_health(level, attributes)
	max_resource = UiStats.resource_max(path, attributes)
	current_health = minf(current_health, max_health)


static func _bar_for(p: StringName) -> Array:
	var bar: Array = []
	match p:
		&"wizard":
			bar = [
				UiMockSpell.make(&"spark", "Spark", Color(0.6, 0.8, 1.0), 0, 0, 0, "Cantrip. A free bolt of sparks."),
				UiMockSpell.make(&"fireball", "Fireball", Color(0.95, 0.42, 0.12), 30, 0, 2.2, "Circle II. A slow bolt that explodes in an area."),
				UiMockSpell.make(&"magic_missile", "Magic Missile", Color(0.7, 0.45, 1.0), 15, 3, 1.5, "Circle II. Three darts that never miss."),
				UiMockSpell.make(&"grand_ward", "Grand Ward", Color(0.95, 0.85, 0.45), 40, 20, 2.5, "Absorbs damage for 10 seconds."),
				UiMockSpell.make(&"frost_lance", "Frost Lance", Color(0.5, 0.8, 1.0), 25, 6, 1.8, "Pierces and slows."),
				UiMockSpell.make(&"rune_trap", "Rune Trap", Color(0.95, 0.6, 0.3), 20, 10, 1.5, "A rune that bursts when stepped on."),
				null, null,
			]
		&"sorcerer":
			bar = [
				UiMockSpell.make(&"spark", "Spark", Color(0.6, 0.8, 1.0), 0, 0, 0, "Cantrip. A free bolt of sparks."),
				UiMockSpell.make(&"chain_lightning", "Chain Lightning", Color(0.65, 0.75, 1.0), 12, 1.5, 0, "Jumps to 2 more targets."),
				UiMockSpell.make(&"spark_bolt", "Spark Bolt", Color(0.8, 0.9, 1.0), 6, 0, 0, "A fast lightning bolt."),
				UiMockSpell.make(&"shove", "Shove", Color(0.8, 0.65, 0.45), 10, 4, 0, "Knocks enemies back."),
				UiMockSpell.make(&"barrier", "Barrier", Color(0.9, 0.85, 0.5), 18, 12, 0, "A ward that absorbs hits."),
				UiMockSpell.make(&"flare", "Flare", Color(1.0, 0.55, 0.2), 14, 6, 0.3, "A burst of raw power around you."),
				UiMockSpell.make(&"static_field", "Static Field", Color(0.55, 0.65, 1.0), 20, 8, 0.4, "Saps a share of nearby enemies' health."),
				null,
			]
		_:
			bar = [
				UiMockSpell.make(&"burn_air", "Burn Air", Color(1.0, 0.5, 0.15), 0, 0, 0, "Cantrip. A jet of flame (was Spark)."),
				UiMockSpell.make(&"move_metal", "Move Metal", Color(0.75, 0.75, 0.82), 10, 5, 0.6, "Pulls a weapon from an enemy's hand."),
				UiMockSpell.make(&"bind_mind", "Bind Mind", Color(0.85, 0.4, 0.85), 20, 12, 1.0, "Charms an enemy for a few seconds."),
				UiMockSpell.make(&"mend_flesh", "Mend Flesh", Color(0.45, 0.9, 0.5), 25, 8, 1.2, "Heals over time."),
				UiMockSpell.make(&"chill_water", "Chill Water", Color(0.5, 0.82, 1.0), 15, 4, 0.8, "An ice wall."),
				UiMockSpell.make(&"slow_mind", "Slow Mind", Color(0.95, 0.85, 0.45), 18, 6, 0.5, "Chronos. Slows an enemy's thoughts and steps."),
				UiMockSpell.make(&"burn_metal", "Burn Metal", Color(0.95, 0.3, 0.2), 22, 5, 1.0, "Heats armor, hurting the most armored hardest."),
				null,
			]
	bar.resize(BAR_SIZE)
	return bar

class_name CharacterProgression
extends RefCounted
## An arcanist's growth: XP and level, the five attributes, the path (level 5),
## specialization (level 10), crossing (level 15), talent rows, and the
## path's spell-growth currency (wizard slots, mage Insight, sorcerer points).
##
## Rules follow the Game Mechanics doc; numbers live in res://data/progression/.
## Earned amounts are always derived from level and quests, and only spending is
## stored, so loading, respec and level changes can never double-count.
##
## This object knows nothing about scenes. The Progression autoload owns the
## player's instance; UI, combat and spells listen to its signals.

## XP was added. [param amount] is what was actually applied (0 at the level cap is not emitted).
signal xp_gained(amount: int, source: String)
## Emitted once per level gained, in order.
signal leveled_up(new_level: int)
## Anything that feeds derived stats changed: level, attributes, path or specialization.
signal stats_changed
signal attribute_points_changed(unspent: int)
## The path's spell-growth currency changed (slots, Insight, spell points, open circle or tree rows).
signal spell_growth_changed
signal path_chosen(path_id: String)
signal specialization_chosen(specialization_id: String)
signal crossing_chosen(path_id: String)
signal talent_chosen(row_level: int, talent_id: String)
signal talents_reset
## A new decision is waiting: &"path", &"specialization", &"talent" or &"crossing".
signal choice_available(kind: StringName)
## State was replaced wholesale (load or new game). Listeners should re-read everything.
signal reloaded

const KEY_QUEST_COUNT := 5

var level := 1
## XP into the current level, not lifetime XP.
var xp := 0
var total_xp := 0
var attributes: Dictionary = {}
## Attribute points from outside leveling (rare quest rewards). Added to the per-level points.
var bonus_attribute_points := 0
var path := ""
var specialization := ""
var crossing := ""
## row level (int) -> talent id
var talents: Dictionary = {}
var key_quests_completed := PackedStringArray()
## Sorcerer control trials completed; each gives one spell point.
var control_trials_completed := PackedStringArray()
var insight_spent := 0
var spell_points_spent := 0
var tomes_of_unlearning := 0
## Nightmare replay raises the cap from 20 to 30.
var replay_unlocked := false


func _init() -> void:
	_reset_state()


# --- Experience -------------------------------------------------------------

func max_level() -> int:
	return ProgressionData.max_level(replay_unlocked)


func is_max_level() -> bool:
	return level >= max_level()


func xp_to_next_level() -> int:
	return 0 if is_max_level() else ProgressionData.xp_to_next(level)


## 0..1 progress through the current level, for an XP bar.
func level_progress() -> float:
	var need := xp_to_next_level()
	return 1.0 if need <= 0 else clampf(float(xp) / need, 0.0, 1.0)


## Adds XP and levels up as many times as it pays for. Returns the XP applied.
func add_xp(amount: int, source := "") -> int:
	if amount <= 0 or is_max_level():
		return 0
	xp += amount
	total_xp += amount
	xp_gained.emit(amount, source)
	var gained := 0
	while not is_max_level() and xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		gained += 1
		leveled_up.emit(level)
		_announce_choices_at(level)
	if is_max_level():
		xp = 0
	if gained > 0:
		attribute_points_changed.emit(unspent_attribute_points())
		spell_growth_changed.emit()
		stats_changed.emit()
	return amount


## XP for killing a monster of [param monster_level] worth [param base_xp] at an even level.
## Monsters far below the player give little, so the game nudges players onward.
func xp_for_kill(monster_level: int, base_xp: int) -> int:
	var rules: Dictionary = ProgressionData.leveling()["monster_xp"]
	var diff := monster_level - level
	var mult := 1.0
	if diff > 0:
		mult = minf(1.0 + diff * float(rules["bonus_per_level_above"]), rules["max_multiplier"])
	elif -diff > int(rules["full_xp_below"]):
		var under := -diff - int(rules["full_xp_below"])
		mult = maxf(1.0 - under * float(rules["penalty_per_level"]), rules["min_multiplier"])
	return maxi(1, roundi(base_xp * mult)) if base_xp > 0 else 0


## Jumps straight to [param target_level] (debug menus, tests, Nightmare start). Keeps choices made.
func set_level(target_level: int) -> void:
	target_level = clampi(target_level, 1, max_level())
	var old := level
	level = target_level
	xp = 0
	for l in range(old + 1, level + 1):
		leveled_up.emit(l)
		_announce_choices_at(l)
	if unspent_attribute_points() < 0:
		_reset_attributes()
	_clamp_spending()
	attribute_points_changed.emit(unspent_attribute_points())
	spell_growth_changed.emit()
	stats_changed.emit()


# --- Attributes -------------------------------------------------------------

func get_attribute(attribute: StringName) -> int:
	return attributes.get(attribute, ProgressionData.base_attribute())


func total_attribute_points() -> int:
	return (level - 1) * int(ProgressionData.leveling()["attribute_points_per_level"]) + bonus_attribute_points


func spent_attribute_points() -> int:
	var spent := 0
	for a in ProgressionData.ATTRIBUTES:
		spent += get_attribute(a) - ProgressionData.base_attribute()
	return spent


func unspent_attribute_points() -> int:
	return total_attribute_points() - spent_attribute_points()


## Spends [param amount] points on one attribute. Returns false if there are not enough points.
func allocate(attribute: StringName, amount := 1) -> bool:
	return allocate_many({attribute: amount})


## Spends several attributes at once, e.g. when the player confirms the level-up screen.
## All or nothing: returns false and changes nothing if any entry is invalid.
func allocate_many(points: Dictionary) -> bool:
	var total := 0
	for a in points:
		if not StringName(a) in ProgressionData.ATTRIBUTES or int(points[a]) < 0:
			return false
		total += int(points[a])
	if total == 0 or total > unspent_attribute_points():
		return false
	for a in points:
		attributes[StringName(a)] = get_attribute(StringName(a)) + int(points[a])
	attribute_points_changed.emit(unspent_attribute_points())
	stats_changed.emit()
	return true


## Spends every unspent point along the specialization's suggested build (the "auto" button).
func auto_assign() -> Dictionary:
	var points := unspent_attribute_points()
	if points <= 0:
		return {}
	var weights := ProgressionData.suggested_weights(path, specialization)
	var weight_sum := 0.0
	for a in ProgressionData.ATTRIBUTES:
		weight_sum += float(weights.get(String(a), 0))
	if weight_sum <= 0.0:
		weights = ProgressionData.paths()["unpathed"]["suggested_weights"]
		weight_sum = ProgressionData.ATTRIBUTES.size()
	var plan := {}
	var remainders: Array = []
	var assigned := 0
	for a in ProgressionData.ATTRIBUTES:
		var share := points * float(weights.get(String(a), 0)) / weight_sum
		plan[a] = floori(share)
		assigned += plan[a]
		remainders.append([share - floori(share), a])
	# Largest remainder, ties broken by attribute order, so results are deterministic.
	remainders.sort_custom(func(x, y): return x[0] > y[0] if not is_equal_approx(x[0], y[0]) else ProgressionData.ATTRIBUTES.find(x[1]) < ProgressionData.ATTRIBUTES.find(y[1]))
	for i in points - assigned:
		plan[remainders[i % remainders.size()][1]] += 1
	for a in plan.keys():
		if plan[a] == 0:
			plan.erase(a)
	allocate_many(plan)
	return plan


func grant_tome_of_unlearning(count := 1) -> void:
	tomes_of_unlearning += count


## Uses a Tome of Unlearning to return every attribute to its base. Returns false without a tome.
func reset_attributes() -> bool:
	if tomes_of_unlearning <= 0:
		return false
	tomes_of_unlearning -= 1
	_reset_attributes()
	attribute_points_changed.emit(unspent_attribute_points())
	stats_changed.emit()
	return true


# --- Derived stats ----------------------------------------------------------
# Progression owns only stats that depend on level. Spell power, crit, cast
# speed and resource size come from CombatStats in res://systems/combat/.

func max_health() -> float:
	var d: Dictionary = ProgressionData.attributes()["derived"]
	return d["base_health"] + d["health_per_level"] * level + d["health_per_vitality"] * get_attribute(&"vitality")


func health_regen() -> float:
	return ProgressionData.attributes()["derived"]["health_regen_per_vitality"] * get_attribute(&"vitality")


## Builds the combat stats for this character through CombatStats.from_attributes,
## or returns null while the combat system is not in the project.
func combat_stats() -> Resource:
	var script := _combat_stats_script()
	if script == null or not script.has_method("from_attributes"):
		return null
	return script.from_attributes(path, get_attribute(&"strength"), get_attribute(&"vitality"),
			get_attribute(&"dexterity"), get_attribute(&"intelligence"), get_attribute(&"wisdom"))


static func _combat_stats_script() -> Script:
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == &"CombatStats":
			return load(entry["path"])
	return null


# --- Path, specialization, crossing -----------------------------------------

func can_choose_path() -> bool:
	return path.is_empty() and level >= int(ProgressionData.leveling()["path_choice_level"])


## Picks wizard, mage or sorcerer. Permanent: it is the game's first dilemma.
func choose_path(path_id: String) -> bool:
	if not can_choose_path() or ProgressionData.get_path_data(path_id).is_empty():
		return false
	path = path_id
	path_chosen.emit(path)
	spell_growth_changed.emit()
	stats_changed.emit()
	return true


func can_choose_specialization() -> bool:
	return not path.is_empty() and specialization.is_empty() \
			and level >= int(ProgressionData.leveling()["specialization_level"])


func choose_specialization(spec_id: String) -> bool:
	if not can_choose_specialization() or ProgressionData.get_specialization(path, spec_id).is_empty():
		return false
	specialization = spec_id
	specialization_chosen.emit(specialization)
	stats_changed.emit()
	if not open_talent_rows().is_empty():
		choice_available.emit(&"talent")
	return true


func can_choose_crossing() -> bool:
	return not path.is_empty() and crossing.is_empty() \
			and level >= int(ProgressionData.leveling()["crossing_level"])


## Borrows one passive feature from another path (the feature itself is defined by spells/combat).
func choose_crossing(path_id: String) -> bool:
	if not can_choose_crossing() or path_id == path or ProgressionData.get_path_data(path_id).is_empty():
		return false
	crossing = path_id
	crossing_chosen.emit(crossing)
	stats_changed.emit()
	return true


# --- Talents ----------------------------------------------------------------

## Talent row levels reached so far (whether filled or not).
func unlocked_talent_rows() -> Array[int]:
	var out: Array[int] = []
	if specialization.is_empty():
		return out
	for l in ProgressionData.talent_row_levels():
		if level >= l:
			out.append(l)
	return out


## Unlocked rows that have options in the data and no pick yet.
func open_talent_rows() -> Array[int]:
	var out: Array[int] = []
	for l in unlocked_talent_rows():
		if not talents.has(l) and not ProgressionData.get_talent_row(path, specialization, l).is_empty():
			out.append(l)
	return out


func choose_talent(row_level: int, talent_id: String) -> bool:
	if not row_level in unlocked_talent_rows() or talents.has(row_level):
		return false
	var row := ProgressionData.get_talent_row(path, specialization, row_level)
	for option in row.get("options", []):
		if option["id"] == talent_id:
			talents[row_level] = talent_id
			talent_chosen.emit(row_level, talent_id)
			stats_changed.emit()
			return true
	return false


func has_talent(talent_id: String) -> bool:
	return talent_id in talents.values()


## Clears one row so it can be picked again (free at any rest spot).
func reset_talent_row(row_level: int) -> void:
	if talents.erase(row_level):
		talents_reset.emit()
		stats_changed.emit()


func reset_talents() -> void:
	if talents.is_empty():
		return
	talents.clear()
	talents_reset.emit()
	stats_changed.emit()


# --- Spell growth -----------------------------------------------------------

func spell_growth() -> Dictionary:
	return ProgressionData.get_path_data(path).get("spell_growth", {})


func key_quest_bonus_count() -> int:
	return mini(key_quests_completed.size(), KEY_QUEST_COUNT)


## Marks a key story quest done. Each gives one bonus step of spell growth. Returns false if already done.
func complete_key_quest(quest_id: String) -> bool:
	if quest_id in key_quests_completed:
		return false
	key_quests_completed.append(quest_id)
	spell_growth_changed.emit()
	return true


func complete_control_trial(trial_id: String) -> bool:
	if trial_id in control_trials_completed:
		return false
	control_trials_completed.append(trial_id)
	spell_growth_changed.emit()
	return true


## Wizard: one spellbook slot per level. Choosing the path at 5 grants all 5 at once.
func spellbook_slots() -> int:
	return level * int(spell_growth()["slots_per_level"]) if path == "wizard" else 0


## Wizard: highest spell circle open (1 to 7). Circles open every 3 levels.
func open_circle() -> int:
	if path != "wizard":
		return 0
	var circle := 0
	for l in spell_growth()["circle_levels"]:
		if level >= int(l):
			circle += 1
	return circle


## Wizard: rare spellbooks owed by key story quests. The spells system hands out the books.
func rare_spellbooks_earned() -> int:
	return key_quest_bonus_count() if path == "wizard" else 0


## Mage: Insight from every second level starting at 6, plus one per key story quest.
func insight_earned() -> int:
	if path != "mage":
		return 0
	var g := spell_growth()
	var first := int(g["first_insight_level"])
	var from_levels := 0 if level < first else (level - first) / int(g["insight_every"]) + 1
	return from_levels + key_quest_bonus_count()


func insight_available() -> int:
	return insight_earned() - insight_spent


## Mage: compound spells (a verb with two nouns) open at level 12.
func compounds_unlocked() -> bool:
	return path == "mage" and level >= int(spell_growth()["compound_level"])


## Sorcerer: 4 points at the path choice (one per level so far), one per level after,
## plus one per key story quest and per control trial.
func spell_points_earned() -> int:
	if path != "sorcerer":
		return 0
	var g := spell_growth()
	var path_level := int(ProgressionData.leveling()["path_choice_level"])
	var from_levels := int(g["points_at_path_choice"]) + (level - path_level) * int(g["points_per_level"])
	return maxi(from_levels, 0) + key_quest_bonus_count() + control_trials_completed.size()


func spell_points_available() -> int:
	return spell_points_earned() - spell_points_spent


## Sorcerer: how many rows of the spell tree are open (rows open at 5, 8, 11, 14, 17, 20).
func open_tree_rows() -> int:
	if path != "sorcerer":
		return 0
	var rows := 0
	for l in spell_growth()["tree_row_levels"]:
		if level >= int(l):
			rows += 1
	return rows


## Spends Insight (mage) or spell points (sorcerer). Wizards spend nothing: slots are counted, not spent.
func spend_spell_growth(amount := 1) -> bool:
	if amount <= 0 or amount > spell_growth_available():
		return false
	match path:
		"mage": insight_spent += amount
		"sorcerer": spell_points_spent += amount
		_: return false
	spell_growth_changed.emit()
	return true


## Returns spent Insight or spell points, e.g. after a trainer respec. [param amount] -1 refunds everything.
func refund_spell_growth(amount := -1) -> void:
	match path:
		"mage": insight_spent = 0 if amount < 0 else maxi(insight_spent - amount, 0)
		"sorcerer": spell_points_spent = 0 if amount < 0 else maxi(spell_points_spent - amount, 0)
		_: return
	spell_growth_changed.emit()


## The unspent amount of this path's growth currency (wizard: total slots).
func spell_growth_available() -> int:
	match path:
		"wizard": return spellbook_slots()
		"mage": return insight_available()
		"sorcerer": return spell_points_available()
	return 0


# --- Pending decisions ------------------------------------------------------

## Everything the player could decide right now, for a "!" badge on the character button.
func pending_choices() -> Array[StringName]:
	var out: Array[StringName] = []
	if unspent_attribute_points() > 0:
		out.append(&"attributes")
	if can_choose_path():
		out.append(&"path")
	if can_choose_specialization():
		out.append(&"specialization")
	if not open_talent_rows().is_empty():
		out.append(&"talent")
	if can_choose_crossing():
		out.append(&"crossing")
	if spell_growth_available() > 0 and path != "wizard":
		out.append(&"spell_growth")
	return out


func _announce_choices_at(l: int) -> void:
	var rules := ProgressionData.leveling()
	if l == int(rules["path_choice_level"]) and path.is_empty():
		choice_available.emit(&"path")
	if l == int(rules["specialization_level"]) and specialization.is_empty() and not path.is_empty():
		choice_available.emit(&"specialization")
	if l == int(rules["crossing_level"]) and crossing.is_empty() and not path.is_empty():
		choice_available.emit(&"crossing")
	if l in ProgressionData.talent_row_levels() and not specialization.is_empty():
		choice_available.emit(&"talent")


# --- Save data --------------------------------------------------------------

func to_dict() -> Dictionary:
	var attr := {}
	for a in ProgressionData.ATTRIBUTES:
		attr[String(a)] = get_attribute(a)
	var talent_dict := {}
	for l in talents:
		talent_dict[str(l)] = talents[l]
	return {
		"level": level,
		"xp": xp,
		"total_xp": total_xp,
		"attributes": attr,
		"bonus_attribute_points": bonus_attribute_points,
		"path": path,
		"specialization": specialization,
		"crossing": crossing,
		"talents": talent_dict,
		"key_quests_completed": Array(key_quests_completed),
		"control_trials_completed": Array(control_trials_completed),
		"insight_spent": insight_spent,
		"spell_points_spent": spell_points_spent,
		"tomes_of_unlearning": tomes_of_unlearning,
		"replay_unlocked": replay_unlocked,
	}


## Replaces this instance's state in place, so listeners stay connected, then emits [signal reloaded].
## Unknown or invalid values fall back to defaults rather than failing the load.
func apply_dict(d: Dictionary) -> void:
	_reset_state()
	replay_unlocked = bool(d.get("replay_unlocked", false))
	level = clampi(int(d.get("level", 1)), 1, max_level())
	xp = clampi(int(d.get("xp", 0)), 0, maxi(xp_to_next_level() - 1, 0))
	total_xp = maxi(int(d.get("total_xp", 0)), 0)
	bonus_attribute_points = maxi(int(d.get("bonus_attribute_points", 0)), 0)
	var attr: Dictionary = d.get("attributes", {})
	for a in ProgressionData.ATTRIBUTES:
		attributes[a] = maxi(int(attr.get(String(a), ProgressionData.base_attribute())), ProgressionData.base_attribute())
	if unspent_attribute_points() < 0:
		push_warning("CharacterProgression: saved attributes exceed points for level %d; resetting them" % level)
		_reset_attributes()
	var p: String = d.get("path", "")
	if not ProgressionData.get_path_data(p).is_empty():
		path = p
		var s: String = d.get("specialization", "")
		if not ProgressionData.get_specialization(path, s).is_empty():
			specialization = s
		var c: String = d.get("crossing", "")
		if c != path and not ProgressionData.get_path_data(c).is_empty():
			crossing = c
	var saved_talents: Dictionary = d.get("talents", {})
	for key in saved_talents:
		var row := ProgressionData.get_talent_row(path, specialization, int(key))
		for option in row.get("options", []):
			if option["id"] == saved_talents[key]:
				talents[int(key)] = option["id"]
	key_quests_completed = PackedStringArray(d.get("key_quests_completed", []))
	control_trials_completed = PackedStringArray(d.get("control_trials_completed", []))
	insight_spent = maxi(int(d.get("insight_spent", 0)), 0)
	spell_points_spent = maxi(int(d.get("spell_points_spent", 0)), 0)
	tomes_of_unlearning = maxi(int(d.get("tomes_of_unlearning", 0)), 0)
	_clamp_spending()
	reloaded.emit()
	attribute_points_changed.emit(unspent_attribute_points())
	spell_growth_changed.emit()
	stats_changed.emit()


static func from_dict(d: Dictionary) -> CharacterProgression:
	var p := CharacterProgression.new()
	p.apply_dict(d)
	return p


## Starts over at level 1 in place (new game), keeping listeners connected.
func reset() -> void:
	apply_dict({})


func _reset_state() -> void:
	level = 1
	xp = 0
	total_xp = 0
	bonus_attribute_points = 0
	path = ""
	specialization = ""
	crossing = ""
	talents = {}
	key_quests_completed = PackedStringArray()
	control_trials_completed = PackedStringArray()
	insight_spent = 0
	spell_points_spent = 0
	tomes_of_unlearning = 0
	replay_unlocked = false
	_reset_attributes()


func _reset_attributes() -> void:
	attributes = {}
	for a in ProgressionData.ATTRIBUTES:
		attributes[a] = ProgressionData.base_attribute()


func _clamp_spending() -> void:
	insight_spent = mini(insight_spent, insight_earned()) if path == "mage" else 0
	spell_points_spent = mini(spell_points_spent, spell_points_earned()) if path == "sorcerer" else 0
	for l in talents.keys():
		if l > level:
			talents.erase(l)

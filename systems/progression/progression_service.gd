extends Node
## Autoload "Progression": the player's character for the running game.
##
## Holds one CharacterAppearance and one CharacterProgression for the whole
## session. New games and loads replace their state in place, so anything that
## connects to these signals once (HUD, character sheet, combat) stays connected.
##
## Wire in project.godot as:  Progression="*res://systems/progression/progression_service.gd"

signal xp_gained(amount: int, source: String)
signal leveled_up(new_level: int)
signal stats_changed
signal attribute_points_changed(unspent: int)
signal spell_growth_changed
signal path_chosen(path_id: String)
signal specialization_chosen(specialization_id: String)
signal crossing_chosen(path_id: String)
signal talent_chosen(row_level: int, talent_id: String)
signal talents_reset
signal choice_available(kind: StringName)
## A new game started or a save loaded. Re-read everything.
signal character_loaded
signal appearance_changed
signal game_saved(slot: int)

const FORWARDED := [
	"xp_gained", "leveled_up", "stats_changed", "attribute_points_changed", "spell_growth_changed",
	"path_chosen", "specialization_chosen", "crossing_chosen", "talent_chosen", "talents_reset",
	"choice_available",
]

var appearance := CharacterAppearance.create_default()
var progression := CharacterProgression.new()
## Seconds played on this character, saved with it.
var play_time_seconds := 0.0
## Other systems' save data from the last load, keyed by system name.
var loaded_extra: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("progression")  # how GameUI finds its progression source
	for s in FORWARDED:
		progression.connect(s, Callable(self, "_forward_" + s))
	appearance.changed.connect(appearance_changed.emit)


func _process(delta: float) -> void:
	if not get_tree().paused:
		play_time_seconds += delta


## Starts a fresh level 1 character with the look from character creation.
func new_character(p_appearance: CharacterAppearance) -> void:
	appearance.apply_dict(p_appearance.to_dict())
	progression.reset()
	play_time_seconds = 0.0
	loaded_extra = {}
	character_loaded.emit()


## Starts a new character from the creation screen's UiSession.character dictionary.
func new_character_from_ui(ui_character: Dictionary) -> void:
	new_character(CharacterAppearance.from_ui_dict(ui_character))


func grant_xp(amount: int, source := "") -> int:
	return progression.add_xp(amount, source)


## Call when the player kills a monster. Applies the level-difference scaling.
func grant_kill_xp(monster_level: int, base_xp: int) -> int:
	return progression.add_xp(progression.xp_for_kill(monster_level, base_xp), "kill")


func complete_key_quest(quest_id: String) -> bool:
	return progression.complete_key_quest(quest_id)


## Saves to a slot. [param extra] holds other systems' data, keyed by system name.
func save_game(slot: int, extra := {}) -> Error:
	var err := ProgressionSave.save_to_file(ProgressionSave.slot_path(slot), appearance, progression,
			play_time_seconds, extra)
	if err == OK:
		game_saved.emit(slot)
	return err


## Loads a slot. Returns false if the slot is missing or unreadable.
func load_game(slot: int) -> bool:
	var data := ProgressionSave.read_file(ProgressionSave.slot_path(slot))
	if data.is_empty():
		return false
	appearance.apply_dict(data.get("appearance", {}))
	progression.apply_dict(data.get("progression", {}))
	play_time_seconds = float(data.get("play_time_seconds", 0.0))
	loaded_extra = data.get("extra", {})
	character_loaded.emit()
	return true


# --- UI contract (res://ui/README.md, "What the UI expects from progression") ---

## Everything the HUD, character sheet and talent picker draw, in one dictionary.
func get_stats() -> Dictionary:
	var p := progression
	var tree := {"name": "", "rows": []}
	var choices: Array[int] = []
	if not p.specialization.is_empty():
		tree["name"] = ProgressionData.get_specialization(p.path, p.specialization).get("name", "")
		for row in ProgressionData.get_specialization(p.path, p.specialization).get("talent_rows", []):
			var options: Array = []
			var chosen := -1
			for option in row["options"]:
				if p.talents.get(int(row["level"]), "") == option["id"]:
					chosen = options.size()
				options.append({"id": option["id"], "name": option["name"], "text": option["description"]})
			tree["rows"].append({"level": int(row["level"]), "options": options})
			choices.append(chosen)
	var attrs := {}
	for a in ProgressionData.ATTRIBUTES:
		attrs[a] = p.get_attribute(a)
	return {
		"name": appearance.character_name,
		"level": p.level,
		"xp": p.xp,
		"xp_to_next": p.xp_to_next_level(),
		"path": "arcanist" if p.path.is_empty() else p.path,
		"specialization": p.specialization,
		"attributes": attrs,
		"unspent_attribute_points": p.unspent_attribute_points(),
		"unspent_spell_points": 0 if p.path == "wizard" else p.spell_growth_available(),
		"talent_tree": tree,
		"talent_choices": choices,
		"max_health": p.max_health(),
		"pending_choices": p.pending_choices(),
	}


## Spends staged attribute points in one call, e.g. {&"intelligence": 3, &"dexterity": 2}.
func allocate_attributes(points: Dictionary) -> bool:
	return progression.allocate_many(points)


## Picks option [param choice] in talent row [param row] (indexes into get_stats().talent_tree.rows).
## Picking a different option in a filled row swaps it, since talent rows reset for free.
func choose_talent(row: int, choice: int) -> bool:
	var rows: Array = get_stats()["talent_tree"]["rows"]
	if row < 0 or row >= rows.size() or choice < 0 or choice >= rows[row]["options"].size():
		return false
	var row_level: int = rows[row]["level"]
	var talent_id: String = rows[row]["options"][choice]["id"]
	if not row_level in progression.unlocked_talent_rows():
		return false
	if progression.talents.get(row_level, "") == talent_id:
		return true
	if progression.talents.has(row_level):
		progression.reset_talent_row(row_level)
	return progression.choose_talent(row_level, talent_id)


func _forward_xp_gained(amount: int, source: String) -> void: xp_gained.emit(amount, source)
func _forward_leveled_up(new_level: int) -> void: leveled_up.emit(new_level)
func _forward_stats_changed() -> void: stats_changed.emit()
func _forward_attribute_points_changed(unspent: int) -> void: attribute_points_changed.emit(unspent)
func _forward_spell_growth_changed() -> void: spell_growth_changed.emit()
func _forward_path_chosen(path_id: String) -> void: path_chosen.emit(path_id)
func _forward_specialization_chosen(spec_id: String) -> void: specialization_chosen.emit(spec_id)
func _forward_crossing_chosen(path_id: String) -> void: crossing_chosen.emit(path_id)
func _forward_talent_chosen(row_level: int, talent_id: String) -> void: talent_chosen.emit(row_level, talent_id)
func _forward_talents_reset() -> void: talents_reset.emit()
func _forward_choice_available(kind: StringName) -> void: choice_available.emit(kind)

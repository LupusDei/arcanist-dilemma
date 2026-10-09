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

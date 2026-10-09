class_name QuestManager
extends Node
## Autoload "Quests": quest tracking, dialogue, story flags and alignment.
##
## Data lives in res://data/quests/ (see QuestDatabase). The world reports what
## happens (talk_to, notify_reached, notify_killed, notify_collected,
## notify_spell_cast, notify_event) and the manager moves quests along, runs
## dialogue, and applies effects: flags, alignment, standing, XP and items.
##
## Wire in project.godot as:  Quests="*res://systems/quests/quest_manager.gd"
## Other nodes find it with QuestManager.find(get_tree()), so the autoload name
## is never hard-coded and tests can make their own.

signal quest_started(quest_id: StringName)
signal quest_stage_changed(quest_id: StringName, stage_id: StringName)
signal objective_updated(quest_id: StringName, objective_id: StringName, count: int, required: int)
signal quest_completed(quest_id: StringName)
signal quest_failed(quest_id: StringName)
## Anything about this quest changed. The tracker redraws on it.
signal quest_updated(quest_id: StringName)
signal flag_changed(flag: StringName, value: Variant, previous: Variant)
signal alignment_changed(law: float, good: float, source: String)
signal standing_changed(faction: StringName, value: float, delta: float)
## A story beat the world should play, e.g. &"lightning_strike". Sent by "event" effects.
signal story_event(event_name: StringName)
## For the inventory: the story gave or took items (gold is &"gold").
signal item_granted(item_id: StringName, count: int)
signal item_removed(item_id: StringName, count: int)
signal xp_rewarded(amount: int, source: String)
signal dialogue_started(runner: DialogueRunner)
signal dialogue_ended(dialogue_id: StringName, npc_id: StringName)
## A new game started or a save was loaded. Re-read everything.
signal state_loaded

const GROUP := &"quest_manager"
## Enemies call on_enemy_died on nodes in this group (res://actors/enemies/).
const ENEMY_LISTENER_GROUP := &"enemy_listeners"
## Loot drops call on_loot_collected on nodes in this group.
const LOOT_LISTENER_GROUP := &"loot_listeners"
const SAVE_KEY := "quests"
const FORMAT_VERSION := 1
const MAX_SETTLE_PASSES := 64

@export var data_dir := QuestDatabase.DEFAULT_DIR
## Player name when the Progression autoload is missing or has no name yet.
@export var player_name_fallback := "Arcanist"
## Read level and name from, and send XP and key quests to, the Progression autoload.
@export var use_progression := true
## Start auto-start quests (the prologue) as soon as the manager is ready.
@export var start_on_ready := true

var database: QuestDatabase
var story := StoryState.new()
## quest id -> QuestProgress, in the order they started.
var quests: Dictionary = {}
var seen_dialogues: Dictionary = {}
var active_dialogue: DialogueRunner

var _active_npc: StringName
var _dialogue_queue: Array[StringName] = []
var _player_areas: Dictionary = {}
var _settling := false
var _needs_settle := false


static func find(tree: SceneTree) -> QuestManager:
	return tree.get_first_node_in_group(GROUP) as QuestManager if tree else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	add_to_group(ENEMY_LISTENER_GROUP)
	add_to_group(LOOT_LISTENER_GROUP)
	if database == null:
		database = QuestDatabase.load_from(data_dir)
		for error in database.errors:
			push_warning("Quest data: " + error)
	story.flag_changed.connect(_on_flag_changed)
	story.standing_changed.connect(standing_changed.emit)
	story.alignment.changed.connect(alignment_changed.emit)
	var progression := _progression()
	if progression and progression.has_signal("character_loaded"):
		progression.character_loaded.connect(_on_character_loaded)
	if start_on_ready:
		_settle()


# --- Reporting what happens in the world -------------------------------------

## The player interacts with an NPC. Plays that NPC's best dialogue; false if none.
func talk_to(npc_id: StringName) -> bool:
	if active_dialogue != null:
		return false
	var dialogue := pick_dialogue(npc_id)
	if dialogue == null:
		return false
	return start_dialogue(dialogue.id, npc_id) != null


## The player walked into a QuestArea.
func notify_reached(area_id: StringName) -> void:
	_player_areas[area_id] = true
	_progress(&"reach", [area_id])


## The player left a QuestArea (cast objectives with "where" stop counting).
func notify_left(area_id: StringName) -> void:
	_player_areas.erase(area_id)


func is_player_in(area_id: StringName) -> bool:
	return _player_areas.has(area_id)


## A monster of this type died to the player. Type ids are EnemyData file names.
func notify_killed(enemy_type: StringName, count := 1) -> void:
	_progress(&"kill", [enemy_type, &"any"], count)


func notify_collected(item_id: StringName, count := 1) -> void:
	_progress(&"collect", [item_id], count)


## The player cast a spell, e.g. &"nudge". Connect SpellCaster.spell_cast to this.
func notify_spell_cast(spell_id: StringName) -> void:
	_progress(&"cast", [spell_id, &"any"])


## Same as notify_spell_cast, taking the SpellData: connect SpellCaster.spell_cast here.
func on_spell_cast(spell: Resource) -> void:
	var id: Variant = spell.get("id") if spell else null
	if id != null and StringName(id) != &"":
		notify_spell_cast(StringName(id))


## Anything else the world wants quests to know, e.g. &"slept".
func notify_event(event_name: StringName) -> void:
	_progress(&"event", [event_name])


## enemy_listeners hook, called by every Enemy as it dies.
func on_enemy_died(enemy: Node, _xp_value: int, _loot: Array) -> void:
	notify_killed(enemy_type_of(enemy))


## loot_listeners hook, called when the player picks up a drop.
func on_loot_collected(loot: Array, _collector: Node) -> void:
	for entry in loot:
		if entry is Dictionary and entry.has("id"):
			notify_collected(StringName(entry["id"]), int(entry.get("count", 1)))


## Quest id for an enemy: its "quest_type" meta if set, else its EnemyData file name.
static func enemy_type_of(enemy: Node) -> StringName:
	if enemy.has_meta(&"quest_type"):
		return StringName(enemy.get_meta(&"quest_type"))
	var data: Variant = enemy.get("data")
	if data is Resource and not data.resource_path.is_empty():
		return StringName(data.resource_path.get_file().get_basename())
	return StringName(enemy.name.to_snake_case())


# --- Quests ------------------------------------------------------------------

func get_quest_state(quest_id: StringName) -> StringName:
	var progress: QuestProgress = quests.get(quest_id)
	return progress.state if progress else &"not_started"


func get_quest_stage(quest_id: StringName) -> StringName:
	var progress: QuestProgress = quests.get(quest_id)
	return progress.stage if progress else &""


func get_progress(quest_id: StringName) -> QuestProgress:
	return quests.get(quest_id)


func is_active(quest_id: StringName) -> bool:
	return get_quest_state(quest_id) == QuestProgress.ACTIVE


func start_quest(quest_id: StringName) -> bool:
	var quest := database.get_quest(quest_id)
	if quest == null:
		push_warning("No quest '%s'" % quest_id)
		return false
	if quests.has(quest_id):
		return false
	var progress := QuestProgress.new()
	progress.quest_id = quest_id
	quests[quest_id] = progress
	quest_started.emit(quest_id)
	apply_effects(quest.on_start, String(quest_id))
	_enter_stage(progress, quest, quest.first_stage_id())
	_settle()
	return true


func complete_quest(quest_id: StringName) -> bool:
	var progress: QuestProgress = quests.get(quest_id)
	if progress == null:
		if not start_quest(quest_id):
			return false
		progress = quests[quest_id]
	if not progress.is_active():
		return false
	var quest := database.get_quest(quest_id)
	progress.state = QuestProgress.COMPLETED
	_give_rewards(quest)
	quest_completed.emit(quest_id)
	quest_updated.emit(quest_id)
	apply_effects(quest.on_complete, String(quest_id))
	return true


func fail_quest(quest_id: StringName) -> bool:
	var progress: QuestProgress = quests.get(quest_id)
	if progress == null or not progress.is_active():
		return false
	progress.state = QuestProgress.FAILED
	quest_failed.emit(quest_id)
	quest_updated.emit(quest_id)
	apply_effects(database.get_quest(quest_id).on_fail, String(quest_id))
	return true


## Jumps an active quest to a stage (debugging, or effects that skip ahead).
func goto_stage(quest_id: StringName, stage_id: StringName) -> bool:
	var progress: QuestProgress = quests.get(quest_id)
	var quest := database.get_quest(quest_id)
	if progress == null or not progress.is_active() or quest.get_stage(stage_id) == null:
		return false
	_enter_stage(progress, quest, stage_id)
	_settle()
	return true


func complete_objective(quest_id: StringName, objective_id: StringName) -> bool:
	var progress: QuestProgress = quests.get(quest_id)
	if progress == null or not progress.is_active():
		return false
	var stage := _current_stage(progress)
	var objective := stage.get_objective(objective_id) if stage else null
	if objective == null or progress.is_objective_done(objective_id):
		return false
	_mark_done(progress, objective)
	_settle()
	return true


## Active quests in display order: main story, then key quests, then side quests.
func get_active_quests() -> Array[QuestData]:
	var result: Array[QuestData] = []
	for kind in [&"main", &"key", &"side"]:
		for id in quests:
			var quest := database.get_quest(id)
			if quests[id].is_active() and quest.kind == kind:
				result.append(quest)
	for id in quests:
		var quest := database.get_quest(id)
		if quests[id].is_active() and not quest in result:
			result.append(quest)
	return result


## What the quest tracker shows for one active quest:
## {id, title, kind, act, stage_text, objectives: [{text, count, required, done, optional}]}
func get_tracker_entry(quest_id: StringName) -> Dictionary:
	var progress: QuestProgress = quests.get(quest_id)
	var quest := database.get_quest(quest_id)
	if progress == null or quest == null:
		return {}
	var stage := _current_stage(progress)
	var objectives: Array[Dictionary] = []
	if stage:
		for objective in stage.objectives:
			if objective.hidden:
				continue
			objectives.append({
				"id": objective.id,
				"text": format_text(objective.description),
				"count": progress.get_count(objective.id),
				"required": objective.count,
				"done": progress.is_objective_done(objective.id),
				"optional": objective.optional,
			})
	return {
		"id": quest.id,
		"title": quest.title,
		"kind": quest.kind,
		"act": quest.act,
		"state": progress.state,
		"stage_text": format_text(stage.description) if stage else "",
		"any": stage != null and stage.complete_when == &"any",
		"objectives": objectives,
	}


# --- Dialogue ----------------------------------------------------------------

## The highest-priority dialogue for this NPC whose conditions pass right now.
func pick_dialogue(npc_id: StringName) -> DialogueData:
	var best: DialogueData = null
	for dialogue: DialogueData in database.dialogues_for_npc(npc_id):
		if dialogue.once and seen_dialogues.has(dialogue.id):
			continue
		if not StoryConditions.check_all(dialogue.conditions, self):
			continue
		if best == null or dialogue.priority > best.priority:
			best = dialogue
	return best


func has_dialogue_for(npc_id: StringName) -> bool:
	return pick_dialogue(npc_id) != null


## Starts a dialogue by id. If one is already running it is queued and null is returned.
func start_dialogue(dialogue_id: StringName, npc_id: StringName = &"") -> DialogueRunner:
	var dialogue := database.get_dialogue(dialogue_id)
	if dialogue == null:
		push_warning("No dialogue '%s'" % dialogue_id)
		return null
	if active_dialogue != null:
		if not dialogue_id in _dialogue_queue:
			_dialogue_queue.append(dialogue_id)
		return null
	var runner := DialogueRunner.new(dialogue, self)
	active_dialogue = runner
	_active_npc = npc_id if npc_id != &"" else dialogue.npc
	runner.finished.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
	dialogue_started.emit(runner)
	runner.begin()
	return runner


func is_in_dialogue() -> bool:
	return active_dialogue != null


func speaker_name(speaker_id: StringName) -> String:
	if speaker_id == &"player":
		return player_name()
	var s: Dictionary = database.speakers.get(speaker_id, {})
	if s.is_empty():
		return String(speaker_id).capitalize()
	var reveal := StringName(s.get("reveal_flag", ""))
	if reveal != &"" and story.is_set(reveal) and s.has("revealed_name"):
		return s["revealed_name"]
	return s.get("name", String(speaker_id).capitalize())


func speaker_color(speaker_id: StringName) -> Color:
	var s: Dictionary = database.speakers.get(speaker_id, {})
	if s.has("color"):
		return Color.from_string(str(s["color"]), Color(1.0, 0.85, 0.5))
	return Color(0.62, 0.8, 1.0) if speaker_id == &"player" else Color(1.0, 0.85, 0.5)


## Fills {player} and {speaker:id} tokens. {speaker:old_man} stays
## "the old man in grey" until the reveal flag is set.
func format_text(text: String) -> String:
	if not "{" in text:
		return text
	var result := text.replace("{player}", player_name())
	var regex := RegEx.create_from_string("\\{speaker:([a-z0-9_]+)\\}")
	for m in regex.search_all(result):
		result = result.replace(m.get_string(), speaker_name(StringName(m.get_string(1))))
	return result


func player_name() -> String:
	var progression := _progression()
	if progression:
		var appearance: Variant = progression.get("appearance")
		if appearance is Object:
			var n: Variant = appearance.get("character_name")
			if n is String and not n.is_empty():
				return n
	return player_name_fallback


func get_player_level() -> int:
	var progression := _progression()
	if progression:
		var p: Variant = progression.get("progression")
		if p is Object and p.get("level") != null:
			return int(p.get("level"))
	return 1


# --- Effects -----------------------------------------------------------------

## Runs effect dictionaries in a fixed order per entry:
## set, clear, add, alignment, standing, give, take, xp, event,
## complete_objective, start_quest, goto, complete_quest, fail_quest, dialogue.
## [param source] names the cause in alignment history.
func apply_effects(effects: Array, source := "") -> void:
	if effects.is_empty():
		return
	# Hold quest updates until the whole list has run, so a choice's flags,
	# alignment and items all land before any stage reacts to them.
	var outer := _settling
	_settling = true
	for e: Dictionary in effects:
		if e.has("set"):
			var value: Variant = e["set"]
			if value is Dictionary:
				for flag in value:
					story.set_flag(StringName(flag), StoryState._from_json(value[flag]))
			elif value is Array:
				for flag in value:
					story.set_flag(StringName(flag), true)
			else:
				story.set_flag(StringName(str(value)), true)
		if e.has("clear"):
			var flags: Array = e["clear"] if e["clear"] is Array else [e["clear"]]
			for flag in flags:
				story.clear_flag(StringName(flag))
		if e.has("add"):
			for flag in e["add"]:
				story.add_to_flag(StringName(flag), float(e["add"][flag]))
		if e.has("alignment"):
			var a: Dictionary = e["alignment"]
			story.alignment.shift(float(a.get("law", 0.0)), float(a.get("good", 0.0)), source)
		if e.has("standing"):
			for faction in e["standing"]:
				story.change_standing(StringName(faction), float(e["standing"][faction]))
		if e.has("give"):
			for item in e["give"]:
				item_granted.emit(StringName(item), int(e["give"][item]))
		if e.has("take"):
			for item in e["take"]:
				item_removed.emit(StringName(item), int(e["take"][item]))
		if e.has("xp"):
			_grant_xp(int(e["xp"]), source)
		if e.has("event"):
			var event_name := StringName(e["event"])
			story_event.emit(event_name)
			_progress(&"event", [event_name])
		if e.has("complete_objective"):
			var parts := str(e["complete_objective"]).split("/")
			if parts.size() == 2:
				complete_objective(StringName(parts[0]), StringName(parts[1]))
		if e.has("start_quest"):
			start_quest(StringName(e["start_quest"]))
		if e.has("goto"):
			goto_stage(StringName(e["goto"].get("quest", "")), StringName(e["goto"].get("stage", "")))
		if e.has("complete_quest"):
			complete_quest(StringName(e["complete_quest"]))
		if e.has("fail_quest"):
			fail_quest(StringName(e["fail_quest"]))
		if e.has("dialogue"):
			start_dialogue(StringName(e["dialogue"]))
	_settling = outer
	if not outer:
		_settle()


# --- Save and load -----------------------------------------------------------

func to_dict() -> Dictionary:
	var quest_data := {}
	for id in quests:
		quest_data[String(id)] = quests[id].to_dict()
	var seen: Array[String] = []
	for id in seen_dialogues:
		seen.append(String(id))
	return {"version": FORMAT_VERSION, "story": story.to_dict(), "quests": quest_data, "seen_dialogues": seen}


func from_dict(data: Dictionary) -> void:
	_stop_dialogue()
	quests.clear()
	seen_dialogues.clear()
	_player_areas.clear()
	var quest_data: Dictionary = data.get("quests", {})
	for id in quest_data:
		var sid := StringName(id)
		if database.get_quest(sid) == null:
			push_warning("Save has unknown quest '%s'; skipped" % id)
			continue
		quests[sid] = QuestProgress.from_dict(sid, quest_data[id])
	for id in data.get("seen_dialogues", []):
		seen_dialogues[StringName(id)] = true
	_settling = true  # flags reload without re-running quest logic
	story.from_dict(data.get("story", {}))
	_settling = false
	state_loaded.emit()
	_settle()


## Clears everything and starts the story over (auto-start quests begin again).
func new_game() -> void:
	_stop_dialogue()
	quests.clear()
	seen_dialogues.clear()
	_player_areas.clear()
	_settling = true
	story.reset()
	_settling = false
	state_loaded.emit()
	_settle()


func save_to_file(path: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	from_dict(data)
	return true


# --- Internals ---------------------------------------------------------------

func _progress(type: StringName, targets: Array, amount := 1) -> void:
	var changed := false
	for id in quests.keys():
		var progress: QuestProgress = quests[id]
		if not progress.is_active():
			continue
		var stage := _current_stage(progress)
		if stage == null:
			continue
		for objective in stage.objectives:
			if objective.type != type or progress.is_objective_done(objective.id):
				continue
			if not objective.target in targets:
				continue
			if type == &"cast" and objective.where != &"" and not _player_areas.has(objective.where):
				continue
			var count := mini(progress.get_count(objective.id) + amount, objective.count)
			progress.counts[objective.id] = count
			if count >= objective.count:
				progress.done[objective.id] = true
			objective_updated.emit(id, objective.id, count, objective.count)
			quest_updated.emit(id)
			changed = true
	if changed:
		_settle()


func _mark_done(progress: QuestProgress, objective: QuestObjective) -> void:
	progress.counts[objective.id] = objective.count
	progress.done[objective.id] = true
	objective_updated.emit(progress.quest_id, objective.id, objective.count, objective.count)
	quest_updated.emit(progress.quest_id)


## Brings everything up to date: auto-start quests, flag objectives, finished
## stages. Effects inside it only ask for another pass, so nothing re-enters.
func _settle() -> void:
	if _settling:
		_needs_settle = true
		return
	_settling = true
	for _pass in MAX_SETTLE_PASSES:
		_needs_settle = false
		for quest: QuestData in database.quests.values():
			if not quest.auto_start.is_empty() and not quests.has(quest.id) \
					and StoryConditions.check_all(quest.auto_start, self):
				start_quest(quest.id)
		for id in quests.keys():
			var progress: QuestProgress = quests[id]
			if progress.is_active():
				_check_stage(progress)
		if not _needs_settle:
			break
	_settling = false


func _check_stage(progress: QuestProgress) -> void:
	var quest := database.get_quest(progress.quest_id)
	var stage := _current_stage(progress)
	if stage == null:
		return
	for objective in stage.objectives:
		if objective.is_state_check() and not progress.is_objective_done(objective.id):
			var conditions: Array = objective.conditions if not objective.conditions.is_empty() \
					else [{"flag": String(objective.target)}]
			if StoryConditions.check_all(conditions, self):
				_mark_done(progress, objective)
	if not _is_stage_done(stage, progress):
		return
	progress.stage_history.append(stage.id)
	apply_effects(stage.on_complete, "%s/%s" % [quest.id, stage.id])
	if not progress.is_active() or progress.stage != stage.id:
		return  # an effect already moved the quest on
	var next := stage.next
	for branch in stage.branches:
		if StoryConditions.check_all(branch.get("conditions", []), self):
			next = StringName(branch.get("next", ""))
			break
	if next == &"" or next == QuestStage.COMPLETE:
		complete_quest(quest.id)
	elif next == QuestStage.FAIL:
		fail_quest(quest.id)
	else:
		_enter_stage(progress, quest, next)


func _is_stage_done(stage: QuestStage, progress: QuestProgress) -> bool:
	var required := stage.required_objectives()
	if required.is_empty():
		return true
	for objective in required:
		var done := progress.is_objective_done(objective.id)
		if stage.complete_when == &"any" and done:
			return true
		if stage.complete_when == &"all" and not done:
			return false
	return stage.complete_when == &"all"


func _enter_stage(progress: QuestProgress, quest: QuestData, stage_id: StringName) -> void:
	progress.enter_stage(stage_id)
	quest_stage_changed.emit(quest.id, stage_id)
	quest_updated.emit(quest.id)
	var stage := quest.get_stage(stage_id)
	if stage:
		apply_effects(stage.on_enter, "%s/%s" % [quest.id, stage_id])
		# Already standing in a reach area counts.
		for objective in stage.objectives:
			if objective.type == &"reach" and _player_areas.has(objective.target):
				_mark_done(progress, objective)
	_needs_settle = true


func _current_stage(progress: QuestProgress) -> QuestStage:
	var quest := database.get_quest(progress.quest_id)
	return quest.get_stage(progress.stage) if quest else null


func _give_rewards(quest: QuestData) -> void:
	var rewards := quest.rewards
	if rewards.has("xp"):
		_grant_xp(int(rewards["xp"]), String(quest.id))
	if int(rewards.get("gold", 0)) > 0:
		item_granted.emit(&"gold", int(rewards["gold"]))
	var items: Dictionary = rewards.get("items", {})
	for item in items:
		item_granted.emit(StringName(item), int(items[item]))
	if quest.key_quest:
		var progression := _progression()
		if progression and progression.has_method("complete_key_quest"):
			progression.complete_key_quest(String(quest.id))


func _grant_xp(amount: int, source: String) -> void:
	if amount <= 0:
		return
	xp_rewarded.emit(amount, source)
	var progression := _progression()
	if progression and progression.has_method("grant_xp"):
		progression.grant_xp(amount, "quest")


func _progression() -> Node:
	if not use_progression or not is_inside_tree():
		return null
	return get_node_or_null(^"/root/Progression")


func _on_flag_changed(flag: StringName, value: Variant, previous: Variant) -> void:
	flag_changed.emit(flag, value, previous)
	_settle()


func _on_dialogue_finished(dialogue_id: StringName) -> void:
	seen_dialogues[dialogue_id] = true
	var npc := _active_npc
	active_dialogue = null
	_active_npc = &""
	dialogue_ended.emit(dialogue_id, npc)
	var targets: Array = [dialogue_id]
	if npc != &"":
		targets.append(npc)
	_progress(&"talk", targets)
	if not _dialogue_queue.is_empty() and active_dialogue == null:
		start_dialogue(_dialogue_queue.pop_front())


func _stop_dialogue() -> void:
	_dialogue_queue.clear()
	if active_dialogue:
		var runner := active_dialogue
		runner.finished.disconnect(_on_dialogue_finished)
		active_dialogue = null
		runner.stop()
		dialogue_ended.emit(runner.dialogue.id, _active_npc)
		_active_npc = &""


func _on_character_loaded() -> void:
	var progression := _progression()
	var extra: Variant = progression.get("loaded_extra") if progression else null
	if extra is Dictionary and extra.get(SAVE_KEY) is Dictionary:
		from_dict(extra[SAVE_KEY])
	else:
		new_game()

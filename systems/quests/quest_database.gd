class_name QuestDatabase
extends RefCounted
## Loads quests, dialogues and speakers from JSON under res://data/quests/
## (every .json file, recursively) into QuestData / DialogueData resources,
## then checks every cross-reference so authoring mistakes show up in tests.
##
## One file can hold any of three top-level keys:
##   "speakers":  {id: {"name", "revealed_name", "reveal_flag", "color"}}
##   "quests":    [{id, title, kind, act, summary, stages: [...], ...}]
##   "dialogues": [{id, npc, priority, conditions, lines: [...]}]
## Dialogue "lines" may be an array: each line then continues to the one after
## it unless it sets "next", has choices, or sets "end": true. A choice with no
## "next" continues the same way. See res://systems/quests/README.md.

const DEFAULT_DIR := "res://data/quests"

const EFFECT_KEYS: Array[String] = [
	"set", "clear", "add", "alignment", "standing", "give", "take", "xp", "event",
	"complete_objective", "start_quest", "goto", "complete_quest", "fail_quest", "dialogue",
]
const CONDITION_KEYS: Array[String] = [
	"flag", "not_flag", "equals", "min", "max", "quest", "state", "stage",
	"alignment", "lean", "standing", "level_min", "any", "not",
]

var quests: Dictionary = {}     # StringName -> QuestData
var dialogues: Dictionary = {}  # StringName -> DialogueData
var speakers: Dictionary = {}   # StringName -> Dictionary
## Problems found while loading or validating, one readable line each.
var errors: PackedStringArray = []

var _dialogues_by_npc: Dictionary = {}  # StringName -> Array[DialogueData]


static func load_from(dir := DEFAULT_DIR) -> QuestDatabase:
	var db := QuestDatabase.new()
	db.load_dir(dir)
	db.validate()
	return db


func load_dir(dir: String) -> void:
	var files := _json_files(dir)
	files.sort()
	for path in files:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			errors.append("%s: not a JSON object" % path)
			continue
		load_dict(data, path)


## Adds everything in one parsed JSON document. [param origin] names it in errors.
func load_dict(data: Dictionary, origin := "") -> void:
	var speaker_data: Dictionary = data.get("speakers", {})
	for id in speaker_data:
		speakers[StringName(id)] = speaker_data[id]
	for q in data.get("quests", []):
		var quest := parse_quest(q)
		if quest.id == &"":
			errors.append("%s: quest without an id" % origin)
		elif quests.has(quest.id):
			errors.append("%s: duplicate quest '%s'" % [origin, quest.id])
		else:
			quests[quest.id] = quest
	for d in data.get("dialogues", []):
		var dialogue := parse_dialogue(d)
		if dialogue.id == &"":
			errors.append("%s: dialogue without an id" % origin)
		elif dialogues.has(dialogue.id):
			errors.append("%s: duplicate dialogue '%s'" % [origin, dialogue.id])
		else:
			add_dialogue(dialogue)


func add_quest(quest: QuestData) -> void:
	quests[quest.id] = quest


func add_dialogue(dialogue: DialogueData) -> void:
	dialogues[dialogue.id] = dialogue
	if dialogue.npc != &"":
		if not _dialogues_by_npc.has(dialogue.npc):
			_dialogues_by_npc[dialogue.npc] = []
		_dialogues_by_npc[dialogue.npc].append(dialogue)


func get_quest(id: StringName) -> QuestData:
	return quests.get(id)


func get_dialogue(id: StringName) -> DialogueData:
	return dialogues.get(id)


func dialogues_for_npc(npc: StringName) -> Array:
	return _dialogues_by_npc.get(npc, [])


func has_npc(npc: StringName) -> bool:
	return _dialogues_by_npc.has(npc)


# --- Parsing -----------------------------------------------------------------

static func parse_quest(d: Dictionary) -> QuestData:
	var q := QuestData.new()
	q.id = StringName(d.get("id", ""))
	q.title = d.get("title", String(q.id))
	q.kind = StringName(d.get("kind", "side"))
	q.act = str(d.get("act", ""))
	q.summary = d.get("summary", "")
	q.giver = StringName(d.get("giver", ""))
	q.level = int(d.get("level", 1))
	q.auto_start = _dicts(d.get("auto_start", []))
	q.start_stage = StringName(d.get("start_stage", ""))
	q.on_start = _dicts(d.get("on_start", []))
	q.on_complete = _dicts(d.get("on_complete", []))
	q.on_fail = _dicts(d.get("on_fail", []))
	q.rewards = d.get("rewards", {})
	q.key_quest = bool(d.get("key_quest", q.kind == &"key"))
	for s in d.get("stages", []):
		q.stages.append(parse_stage(s))
	return q


static func parse_stage(d: Dictionary) -> QuestStage:
	var s := QuestStage.new()
	s.id = StringName(d.get("id", ""))
	s.description = d.get("description", "")
	s.complete_when = StringName(d.get("complete_when", "all"))
	s.on_enter = _dicts(d.get("on_enter", []))
	s.on_complete = _dicts(d.get("on_complete", []))
	s.next = StringName(d.get("next", ""))
	s.branches = _dicts(d.get("branches", []))
	for o in d.get("objectives", []):
		var obj := QuestObjective.new()
		obj.id = StringName(o.get("id", ""))
		obj.type = StringName(o.get("type", "talk"))
		obj.target = StringName(o.get("target", ""))
		obj.count = int(o.get("count", 1))
		obj.where = StringName(o.get("where", ""))
		obj.description = o.get("description", "")
		obj.optional = bool(o.get("optional", false))
		obj.hidden = bool(o.get("hidden", false))
		obj.conditions = _dicts(o.get("conditions", []))
		s.objectives.append(obj)
	return s


static func parse_dialogue(d: Dictionary) -> DialogueData:
	var dlg := DialogueData.new()
	dlg.id = StringName(d.get("id", ""))
	dlg.npc = StringName(d.get("npc", ""))
	dlg.speaker = StringName(d.get("speaker", ""))
	dlg.priority = int(d.get("priority", 0))
	dlg.conditions = _dicts(d.get("conditions", []))
	dlg.once = bool(d.get("once", false))
	var raw_lines: Variant = d.get("lines", [])
	if raw_lines is Array:
		# Sequential form: ids default to "l<index>" and each line flows into the next.
		var ids: Array[StringName] = []
		for i in raw_lines.size():
			ids.append(StringName(raw_lines[i].get("id", "l%d" % i)))
		for i in raw_lines.size():
			var raw: Dictionary = raw_lines[i]
			var following: StringName = ids[i + 1] if i + 1 < ids.size() and not raw.get("end", false) else &""
			var line := _parse_line(raw, ids[i], following)
			dlg.lines[line.id] = line
		dlg.start = StringName(d.get("start", ids[0] if not ids.is_empty() else "start"))
	elif raw_lines is Dictionary:
		for id in raw_lines:
			var line := _parse_line(raw_lines[id], StringName(id), &"")
			dlg.lines[line.id] = line
		dlg.start = StringName(d.get("start", "start"))
	return dlg


static func _parse_line(raw: Dictionary, id: StringName, following: StringName) -> DialogueLine:
	var line := DialogueLine.new()
	line.id = id
	line.speaker = StringName(raw.get("speaker", ""))
	line.text = raw.get("text", "")
	line.effects = _dicts(raw.get("effects", []))
	line.branches = _dicts(raw.get("branches", []))
	line.next = StringName(raw.get("next", following))
	for c in raw.get("choices", []):
		var choice := DialogueChoice.new()
		choice.text = c.get("text", "")
		choice.conditions = _dicts(c.get("conditions", []))
		choice.effects = _dicts(c.get("effects", []))
		choice.next = StringName(c.get("next", following))
		choice.show_locked = bool(c.get("show_locked", false))
		choice.locked_text = c.get("locked_text", "")
		choice.hint = c.get("hint", "")
		line.choices.append(choice)
	return line


static func _dicts(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Dictionary:
		result.append(value)
	elif value is Array:
		for v in value:
			if v is Dictionary:
				result.append(v)
	return result


static func _json_files(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var da := DirAccess.open(dir)
	if da == null:
		return result
	for sub in da.get_directories():
		result.append_array(_json_files(dir.path_join(sub)))
	for file in da.get_files():
		if file.get_extension() == "json":
			result.append(dir.path_join(file))
	return result


# --- Validation --------------------------------------------------------------

## Checks every reference: stage and line links, quest ids in effects and
## conditions, speakers, objective types and unknown keys. Fills [member errors].
func validate() -> PackedStringArray:
	for quest: QuestData in quests.values():
		var where := "quest '%s'" % quest.id
		if quest.stages.is_empty():
			errors.append("%s has no stages" % where)
		if quest.start_stage != &"" and quest.get_stage(quest.start_stage) == null:
			errors.append("%s: start_stage '%s' does not exist" % [where, quest.start_stage])
		_check_conditions(quest.auto_start, where + " auto_start")
		_check_effects(quest.on_start, where + " on_start")
		_check_effects(quest.on_complete, where + " on_complete")
		_check_effects(quest.on_fail, where + " on_fail")
		var stage_ids := {}
		for stage in quest.stages:
			var swhere := "%s stage '%s'" % [where, stage.id]
			if stage_ids.has(stage.id):
				errors.append("%s: duplicate stage id" % swhere)
			stage_ids[stage.id] = true
			if not stage.complete_when in [&"all", &"any"]:
				errors.append("%s: complete_when must be all or any" % swhere)
			_check_stage_link(quest, stage.next, swhere + " next")
			for branch in stage.branches:
				_check_conditions(_dicts(branch.get("conditions", [])), swhere + " branch")
				_check_stage_link(quest, StringName(branch.get("next", "")), swhere + " branch")
			_check_effects(stage.on_enter, swhere + " on_enter")
			_check_effects(stage.on_complete, swhere + " on_complete")
			var obj_ids := {}
			for obj in stage.objectives:
				var owhere := "%s objective '%s'" % [swhere, obj.id]
				if obj.id == &"" or obj_ids.has(obj.id):
					errors.append("%s: missing or duplicate id" % owhere)
				obj_ids[obj.id] = true
				if not obj.type in QuestObjective.TYPES:
					errors.append("%s: unknown type '%s'" % [owhere, obj.type])
				if obj.target == &"" and not (obj.type == &"flag" and not obj.conditions.is_empty()):
					errors.append("%s: no target" % owhere)
				if obj.count < 1:
					errors.append("%s: count must be at least 1" % owhere)
				if obj.description.is_empty() and not obj.hidden:
					errors.append("%s: no description for the tracker" % owhere)
				_check_conditions(obj.conditions, owhere)
	for dialogue: DialogueData in dialogues.values():
		var where := "dialogue '%s'" % dialogue.id
		if dialogue.get_line(dialogue.start) == null:
			errors.append("%s: start line '%s' does not exist" % [where, dialogue.start])
		_check_conditions(dialogue.conditions, where)
		_check_speaker(dialogue.default_speaker(), where, true)
		for line: DialogueLine in dialogue.lines.values():
			var lwhere := "%s line '%s'" % [where, line.id]
			_check_speaker(line.speaker, lwhere, true)
			if line.text.is_empty() and line.branches.is_empty() and line.next == &"" and line.choices.is_empty():
				errors.append("%s: empty line that goes nowhere" % lwhere)
			if line.speaker == &"" and dialogue.default_speaker() == &"" and not line.text.is_empty():
				errors.append("%s: no speaker" % lwhere)
			_check_line_link(dialogue, line.next, lwhere + " next")
			_check_effects(line.effects, lwhere)
			for branch in line.branches:
				_check_conditions(_dicts(branch.get("conditions", [])), lwhere + " branch")
				_check_line_link(dialogue, StringName(branch.get("next", "")), lwhere + " branch")
			for i in line.choices.size():
				var choice := line.choices[i]
				var cwhere := "%s choice %d" % [lwhere, i + 1]
				if choice.text.is_empty():
					errors.append("%s: no text" % cwhere)
				_check_line_link(dialogue, choice.next, cwhere)
				_check_conditions(choice.conditions, cwhere)
				_check_effects(choice.effects, cwhere)
	return errors


func _check_stage_link(quest: QuestData, next: StringName, where: String) -> void:
	if next == &"" or next == QuestStage.COMPLETE or next == QuestStage.FAIL:
		return
	if quest.get_stage(next) == null:
		errors.append("%s: stage '%s' does not exist" % [where, next])


func _check_line_link(dialogue: DialogueData, next: StringName, where: String) -> void:
	if next != &"" and dialogue.get_line(next) == null:
		errors.append("%s: line '%s' does not exist" % [where, next])


func _check_speaker(id: StringName, where: String, allow_empty: bool) -> void:
	if id == &"":
		if not allow_empty:
			errors.append("%s: no speaker" % where)
		return
	if id != &"player" and not speakers.has(id):
		errors.append("%s: unknown speaker '%s'" % [where, id])


func _check_quest_ref(id: Variant, where: String) -> void:
	if not quests.has(StringName(str(id))):
		errors.append("%s: unknown quest '%s'" % [where, id])


func _check_effects(effects: Array[Dictionary], where: String) -> void:
	for effect in effects:
		for key in effect:
			if not key in EFFECT_KEYS:
				errors.append("%s: unknown effect '%s'" % [where, key])
		for key in ["start_quest", "complete_quest", "fail_quest"]:
			if effect.has(key):
				_check_quest_ref(effect[key], where)
		if effect.has("goto"):
			var goto: Dictionary = effect["goto"]
			var quest: QuestData = quests.get(StringName(goto.get("quest", "")))
			if quest == null:
				errors.append("%s: goto unknown quest '%s'" % [where, goto.get("quest", "")])
			elif quest.get_stage(StringName(goto.get("stage", ""))) == null:
				errors.append("%s: goto unknown stage '%s'" % [where, goto.get("stage", "")])
		if effect.has("complete_objective"):
			var parts := str(effect["complete_objective"]).split("/")
			var quest: QuestData = quests.get(StringName(parts[0]))
			var found := false
			if quest != null and parts.size() == 2:
				for stage in quest.stages:
					if stage.get_objective(StringName(parts[1])) != null:
						found = true
			if not found:
				errors.append("%s: complete_objective '%s' does not name quest/objective" % [where, effect["complete_objective"]])
		if effect.has("dialogue") and not dialogues.has(StringName(str(effect["dialogue"]))):
			errors.append("%s: unknown dialogue '%s'" % [where, effect["dialogue"]])
		if effect.has("alignment"):
			for axis in effect["alignment"]:
				if not StringName(axis) in Alignment.AXES:
					errors.append("%s: alignment axis must be law or good, not '%s'" % [where, axis])


func _check_conditions(conditions: Array[Dictionary], where: String) -> void:
	for condition in conditions:
		for key in condition:
			if not key in CONDITION_KEYS:
				errors.append("%s: unknown condition '%s'" % [where, key])
		if condition.has("quest"):
			_check_quest_ref(condition["quest"], where)
			var quest: QuestData = quests.get(StringName(str(condition["quest"])))
			if quest != null and condition.has("stage") and quest.get_stage(StringName(condition["stage"])) == null:
				errors.append("%s: quest '%s' has no stage '%s'" % [where, quest.id, condition["stage"]])
			if condition.has("state") and not StringName(condition["state"]) in QuestProgress.STATES_FOR_CONDITIONS:
				errors.append("%s: unknown quest state '%s'" % [where, condition["state"]])
		if condition.has("any"):
			_check_conditions(_dicts(condition["any"]), where)
		if condition.has("not"):
			_check_conditions(_dicts(condition["not"]), where)

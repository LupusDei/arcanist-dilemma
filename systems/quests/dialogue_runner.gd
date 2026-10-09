class_name DialogueRunner
extends RefCounted
## Steps through one DialogueData. The dialogue box reads [method get_view]
## and calls [method advance] or [method choose]; effects run through the
## QuestManager as lines are shown and choices are picked.

signal line_changed
signal finished(dialogue_id: StringName)

const MAX_ROUTING_STEPS := 64

var dialogue: DialogueData
var line: DialogueLine
var is_finished := false
## The choices on screen right now, after conditions: [{choice, enabled}].
var visible_choices: Array[Dictionary] = []
## Every choice picked, as "line_id:index", for tests and debugging.
var picked: Array[String] = []

var _manager: QuestManager
var _continue_to: StringName


func _init(p_dialogue: DialogueData, manager: QuestManager) -> void:
	dialogue = p_dialogue
	_manager = manager


## Enters the first line. Called by QuestManager after dialogue_started.
func begin() -> void:
	_go(dialogue.start)


func has_choices() -> bool:
	return not visible_choices.is_empty()


## What the dialogue box shows: speaker id and name, text with tokens filled in,
## and each choice's text, alignment hint and whether it can be picked.
func get_view() -> Dictionary:
	if line == null:
		return {}
	var speaker_id := line.speaker if line.speaker != &"" else dialogue.default_speaker()
	var choices: Array[Dictionary] = []
	for entry in visible_choices:
		var choice: DialogueChoice = entry["choice"]
		var enabled: bool = entry["enabled"]
		choices.append({
			"text": _manager.format_text(choice.text),
			"hint": choice.lean_hint(),
			"enabled": enabled,
			"locked_text": _manager.format_text(choice.locked_text) if not enabled else "",
		})
	return {
		"dialogue": dialogue.id,
		"line": line.id,
		"speaker_id": speaker_id,
		"speaker": _manager.speaker_name(speaker_id),
		"speaker_color": _manager.speaker_color(speaker_id),
		"text": _manager.format_text(line.text),
		"choices": choices,
	}


## Continues a line without choices.
func advance() -> void:
	if is_finished or has_choices():
		return
	_go(_continue_to)


## Picks a choice by its index in [method get_view]'s choices. Returns false if locked.
func choose(index: int) -> bool:
	if is_finished or index < 0 or index >= visible_choices.size():
		return false
	if not visible_choices[index]["enabled"]:
		return false
	var choice: DialogueChoice = visible_choices[index]["choice"]
	picked.append("%s:%d" % [line.id, line.choices.find(choice)])
	_manager.apply_effects(choice.effects, "%s/%s" % [dialogue.id, line.id])
	if is_finished:
		return true
	_go(choice.next)
	return true


## Ends the conversation early (the player walked away).
func stop() -> void:
	_finish()


func _go(line_id: StringName) -> void:
	for _i in MAX_ROUTING_STEPS:
		if line_id == &"":
			_finish()
			return
		line = dialogue.get_line(line_id)
		if line == null:
			push_error("Dialogue '%s': no line '%s'" % [dialogue.id, line_id])
			_finish()
			return
		_manager.apply_effects(line.effects, "%s/%s" % [dialogue.id, line.id])
		if is_finished:
			return
		var routed := _route(line)
		if line.text.is_empty() and line.choices.is_empty():
			line_id = routed
			continue
		# A line with text takes its branches when the player moves on.
		_continue_to = routed
		_build_choices()
		line_changed.emit()
		return
	push_error("Dialogue '%s': routing loop" % dialogue.id)
	_finish()


func _route(l: DialogueLine) -> StringName:
	for branch in l.branches:
		if StoryConditions.check_all(branch.get("conditions", []), _manager):
			return StringName(branch.get("next", ""))
	return l.next


func _build_choices() -> void:
	visible_choices.clear()
	for choice in line.choices:
		var ok := StoryConditions.check_all(choice.conditions, _manager)
		if ok or choice.show_locked:
			visible_choices.append({"choice": choice, "enabled": ok})


func _finish() -> void:
	if is_finished:
		return
	is_finished = true
	visible_choices.clear()
	finished.emit(dialogue.id)

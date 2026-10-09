class_name QuestData
extends Resource
## A quest: stages in order, what starts it and what it pays out.
## Authored as JSON in res://data/quests/ (see QuestDatabase), or as a .tres.

@export var id: StringName
@export var title := ""
## &"main" (story), &"key" (a key story quest with a big alignment choice) or &"side".
@export var kind: StringName = &"side"
## "Prologue", "I", "II" or "III".
@export var act := ""
@export_multiline var summary := ""
## NPC who gives it, for markers.
@export var giver: StringName
@export var level := 1
## Starts on its own the moment these all pass. Empty means only effects or code start it.
@export var auto_start: Array[Dictionary] = []
@export var start_stage: StringName
@export var stages: Array[QuestStage] = []
@export var on_start: Array[Dictionary] = []
@export var on_complete: Array[Dictionary] = []
@export var on_fail: Array[Dictionary] = []
## {"xp": int, "gold": int, "items": {item_id: count}}
@export var rewards: Dictionary = {}
## Key story quests give progression's bonus spell growth step on completion.
@export var key_quest := false


func get_stage(stage_id: StringName) -> QuestStage:
	for stage in stages:
		if stage.id == stage_id:
			return stage
	return null


func first_stage_id() -> StringName:
	if start_stage != &"":
		return start_stage
	return stages[0].id if not stages.is_empty() else &""

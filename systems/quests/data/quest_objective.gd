class_name QuestObjective
extends Resource
## One thing to do in a quest stage.
##
## [member type] decides what counts as progress and what [member target] names:
##   talk     an NPC id or a dialogue id; counts when that conversation ends
##   kill     an enemy type id (its EnemyData file name, e.g. "gloom_hound"), or "any"
##   reach    a QuestArea id; counts when the player walks in
##   collect  an item id; counts each one picked up after the stage starts
##   cast     a spell id (e.g. "nudge"); with [member where], only inside that QuestArea
##   event    a world event name sent with QuestManager.notify_event()
##   flag     a story flag; done while it is truthy. Use [member conditions] for anything richer.

const TYPES: Array[StringName] = [&"talk", &"kill", &"reach", &"collect", &"cast", &"event", &"flag"]

@export var id: StringName
@export var type: StringName = &"talk"
@export var target: StringName
@export var count := 1
## cast objectives only: the QuestArea the player has to stand in.
@export var where: StringName
## Shown in the quest tracker, e.g. "Light the stove with a spark".
@export var description := ""
## Optional objectives never hold a stage back.
@export var optional := false
## Hidden objectives still count but never show in the tracker.
@export var hidden := false
## flag objectives: every condition must pass (see StoryConditions).
@export var conditions: Array[Dictionary] = []


func is_state_check() -> bool:
	return type == &"flag"
